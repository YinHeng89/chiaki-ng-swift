import ChiakiModels
import Foundation
import GRDB
import Synchronization

/// The core's signed-in accounts and home users: profiles, sealed NPSSOs, one sealed column per token, and
/// the region and context in `account_context`.
///
/// Each secret is sealed with the database's ``CredentialCipher`` straight from a wiping buffer and opened
/// back into one. A sign-in is written in one transaction, so its NPSSO and tokens commit together or not at
/// all. A save keeps the stored NPSSO's dates while the NPSSO is unchanged, takes the core's obtained time, and
/// takes the core's expiry only as a change: an expiry read from the server is never erased or downgraded by a later
/// save from the core, and only an expiry read from the server is handed back to the core.
public final class CredentialRepository: CredentialStoring {
    private let database: AppDatabase
    private let report: @Sendable (PersistenceError) -> Void
    private let now: @Sendable () -> Date
    private let pending = Mutex<PendingProfile?>(nil)

    /// Creates the repository over the app database.
    ///
    /// - Parameters:
    ///   - database: The open database.
    ///   - report: Receives every storage failure before it is turned into a
    ///     `ChiakiModels/CredentialStoreFailure`, so the cause can be logged. Ignored by default.
    ///   - now: The clock dating stored rows.
    public init(
        database: AppDatabase,
        report: @escaping @Sendable (PersistenceError) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = {
            Date()
        }
    ) {
        self.database = database
        self.report = report
        self.now = now
    }

    /// Announces the profile the core's next save creates, or withdraws the announcement.
    ///
    /// - Parameter profile: The profile to create, or `nil`.
    public func expect(_ profile: PendingProfile?) {
        pending.withLock {
            $0 = profile
        }
    }

    /// Withdraws the announcement of a profile, leaving another attempt's announcement in place.
    ///
    /// - Parameter profile: The announced profile's id.
    public func withdraw(_ profile: UUID) {
        pending.withLock {
            if $0?.id == profile {
                $0 = nil
            }
        }
    }

    /// Loads every signed-in account whose NPSSO and tokens all decrypt.
    ///
    /// - Returns: The sign-ins, oldest profile first, each with the installation's device id.
    /// - Throws: `ChiakiModels/CredentialStoreFailure/unavailable` when the tables cannot be read.
    public func savedSignIns() throws(CredentialStoreFailure) -> [StoredSignIn] {
        let loaded = try reporting { () throws(PersistenceError) in
            try database.write { database in
                let device = try CloudInstallationRepository.deviceID(in: database)
                let rows = try SignInRow.fetchAll(database, sql: SignInRow.selectSaved)
                let tokens = try rows.map {
                    try TokenRow.fetchAll(database, sql: TokenRow.selectForProfile, arguments: [$0.profileID])
                }
                return (device, rows, tokens)
            }
        }
        return zip(loaded.1, loaded.2).compactMap {
            signIn($0, tokens: $1, device: loaded.0)
        }
    }

    /// Loads every account added by id only, and every profile that holds no NPSSO.
    ///
    /// - Returns: The home users, oldest profile first.
    /// - Throws: `ChiakiModels/CredentialStoreFailure/unavailable` when the table cannot be read.
    public func homeUsers() throws(CredentialStoreFailure) -> [StoredHomeUser] {
        try reporting { () throws(PersistenceError) in
            try database.read { database in
                try HomeUserRow.fetchAll(database, sql: ProfileRow.selectHomeUsers)
            }
        }
        .compactMap(\.stored)
    }

    /// Saves a sign-in under the oldest profile holding its account, or under a new profile.
    ///
    /// A new profile takes the id announced with ``expect(_:)``. A new encryption key is created only while
    /// no credential of any kind is stored.
    ///
    /// - Parameter signIn: The sign-in.
    /// - Throws: `ChiakiModels/CredentialStoreFailure/unavailable` when the write failed; nothing is written then.
    public func save(_ signIn: StoredSignIn) throws(CredentialStoreFailure) {
        let expected = takePending()
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try SignInWriter(
                    signIn: signIn,
                    cipher: self.database.cipher,
                    stamp: Timestamp.milliseconds(of: now()),
                    database: database
                )
                .write(expected: expected)
            }
        }
    }

    /// Saves an account added by id only, unless a profile holds the account already.
    ///
    /// - Parameter homeUser: The home user.
    /// - Throws: `ChiakiModels/CredentialStoreFailure/unavailable` when the write failed.
    public func save(_ homeUser: StoredHomeUser) throws(CredentialStoreFailure) {
        let expected = takePending()
        let stamp = Timestamp.milliseconds(of: now())
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                guard try String.fetchOne(
                    database, sql: ProfileRow.selectByAccount, arguments: [homeUser.account.data]
                ) == nil
                else {
                    return
                }
                try database.execute(
                    sql: ProfileRow.insert,
                    arguments: [
                        (expected?.id ?? UUID()).uuidString, homeUser.name,
                        AccountProfile.Method.accountID.rawValue,
                        homeUser.account.data, nil, stamp, stamp
                    ]
                )
            }
        }
    }

    /// Deletes every profile holding an account; its NPSSO, tokens, context, cache and pairings cascade.
    ///
    /// - Parameter account: The account.
    /// - Throws: `ChiakiModels/CredentialStoreFailure/unavailable` when the delete failed.
    public func remove(_ account: AccountID) throws(CredentialStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(sql: ProfileRow.deleteByAccount, arguments: [account.data])
            }
        }
    }

    /// Replaces a profile's NPSSO with one whose expiry the app read itself, such as from the sign-in cookie.
    ///
    /// - Parameters:
    ///   - npsso: The NPSSO's text bytes.
    ///   - expiresAt: When it expires, or `nil` when unknown.
    ///   - source: Where the expiry came from; `ChiakiModels/NPSSOExpirySource/unknown` exactly when
    ///     `expiresAt` is `nil`.
    ///   - profile: The profile's id.
    /// - Throws: ``PersistenceError/invalidInput`` for an NPSSO that cannot be sent, an expiry in the past or a
    ///   source that disagrees with the expiry, and the cipher's or database's errors otherwise.
    public func noteNPSSO(
        _ npsso: borrowing SecretBytes,
        expiresAt: Date?,
        source: NPSSOExpirySource,
        for profile: UUID
    ) throws(PersistenceError) {
        let stamp = now()
        let sendable = npsso.withUnsafeBytes { bytes in
            !bytes.isEmpty && bytes.allSatisfy {
                (33 ... 126).contains($0) && ![34, 44, 59, 92].contains($0)
            }
        }
        guard sendable, (expiresAt == nil) == (source == .unknown), expiresAt.map({
            $0 > stamp
        }) ?? true
        else {
            throw .invalidInput
        }
        let id = profile.uuidString
        let allowKeyCreation = try database.read { database in
            try Row.fetchOne(database, sql: PairingRow.anyCredential) == nil
        }
        let envelope = try database.cipher.seal(
            npsso, context: SignInRow.npssoContext(profileID: id), allowKeyCreation: allowKeyCreation
        )
        try database.write { database in
            try database.execute(
                sql: NPSSORow.upsert,
                arguments: [
                    id, envelope, Timestamp.milliseconds(of: stamp), Timestamp.milliseconds(of: stamp),
                    expiresAt.map(Timestamp.milliseconds(of:)),
                    source.rawValue
                ]
            )
        }
    }

    private func takePending() -> PendingProfile? {
        pending.withLock {
            defer {
                $0 = nil
            }
            return $0
        }
    }

    private func signIn(_ row: SignInRow, tokens: [TokenRow], device: String) -> StoredSignIn? {
        guard let account = AccountID(bytes: row.accountID) else {
            report(.corruptData)
            return nil
        }
        let npsso: SecretBytes
        do {
            npsso = try database.cipher.open(
                row.npsso,
                context: SignInRow.npssoContext(profileID: row.profileID)
            )
        } catch {
            report(error)
            return nil
        }
        var opened: [CredentialTokenKind: StoredToken] = [:]
        for token in tokens {
            for (part, envelope, obtained, expires) in [
                (TokenRow.Part.access, token.access, token.accessObtainedAt, token.accessExpiresAt),
                (TokenRow.Part.refresh, token.refresh, token.refreshObtainedAt, token.refreshExpiresAt)
            ] {
                guard let envelope, let kind = TokenRow.token(kind: token.kind, part: part) else {
                    continue
                }
                do {
                    let value = try database.cipher.open(
                        envelope, context: TokenRow.context(
                            profileID: row.profileID,
                            kind: token.kind,
                            part: part
                        )
                    )
                    opened[kind] = StoredToken(
                        value: value,
                        obtainedAt: obtained.map(Timestamp.date(milliseconds:)),
                        expiresAt: expires.map(Timestamp.date(milliseconds:))
                    )
                } catch {
                    report(error)
                    return nil
                }
            }
        }
        let source = NPSSOExpirySource(rawValue: row.expirySource) ?? .unknown
        return StoredSignIn(
            account: account,
            onlineID: row.onlineID,
            npsso: npsso,
            npssoObtainedAt: Timestamp.date(milliseconds: row.acquiredAt),
            npssoExpiresAt: source.isReadFromServer
                ? row.expiresAt.map(Timestamp.date(milliseconds:))
                : nil,
            tokens: opened,
            region: row.context.region,
            context: row.context.context,
            deviceID: device
        )
    }

    private func reporting<Result>(_ body: () throws(PersistenceError)
        -> Result) throws(CredentialStoreFailure)
        -> Result {
        do {
            return try body()
        } catch {
            report(error)
            throw .unavailable
        }
    }
}

/// Writes one sign-in inside a transaction: its profile, its sealed NPSSO and tokens, and its region and
/// stated context.
///
/// The stored NPSSO's dates are kept while the NPSSO is unchanged, the core's obtained time is taken, and the
/// core's expiry is taken only as a change, so an expiry read from the server is never erased or downgraded by a
/// later save from the core. A new encryption key is created only while no credential of any kind is stored.
private struct SignInWriter {
    private let signIn: StoredSignIn
    private let cipher: CredentialCipher
    private let stamp: Int64
    private let database: GRDB.Database

    /// Prepares the write of a sign-in.
    ///
    /// - Parameters:
    ///   - signIn: The sign-in.
    ///   - cipher: Seals the NPSSO and the tokens.
    ///   - stamp: When the write happens, in milliseconds since 1970.
    ///   - database: The open transaction.
    init(signIn: StoredSignIn, cipher: CredentialCipher, stamp: Int64, database: GRDB.Database) {
        self.signIn = signIn
        self.cipher = cipher
        self.stamp = stamp
        self.database = database
    }

    /// Writes the sign-in under the oldest profile holding its account, or under a new profile.
    ///
    /// - Parameter expected: The profile announced for a new sign-in, if any.
    /// - Throws: The cipher's or the database's errors.
    func write(expected: PendingProfile?) throws {
        let creating = try Row.fetchOne(database, sql: PairingRow.anyCredential) == nil
        let profileID: String
        if let existing = try String.fetchOne(
            database, sql: ProfileRow.selectByAccount, arguments: [signIn.account.data]
        ) {
            profileID = existing
            try database.execute(
                sql: ProfileRow.updateSignedIn, arguments: [signIn.onlineID, signIn.onlineID, stamp, existing]
            )
        } else {
            profileID = (expected?.id ?? UUID()).uuidString
            try database.execute(
                sql: ProfileRow.insert,
                arguments: [
                    profileID, signIn.onlineID, AccountProfile.Method.npsso.rawValue, signIn.account.data,
                    signIn.onlineID, stamp, stamp
                ]
            )
        }
        try writeNPSSO(
            profileID: profileID,
            expected: expected?.expirySource ?? .unknown,
            allowKeyCreation: creating
        )
        try writeTokens(
            TokenRow.storeKind, access: .storeAccess, refresh: .storeRefresh,
            profileID: profileID, allowKeyCreation: creating
        )
        try writeTokens(
            TokenRow.remotePlayKind, access: .remotePlayAccess, refresh: .remotePlayRefresh,
            profileID: profileID, allowKeyCreation: creating
        )
        if let region = signIn.region {
            try database.execute(
                sql: AccountContextRow.upsertRegion, arguments: [profileID, region.country, region.language]
            )
        }
        if !signIn.context.statesNothing {
            try database.execute(
                sql: AccountContextRow.upsertContext,
                arguments: AccountContextRow.contextArguments(signIn.context, profileID: profileID)
            )
        }
    }

    private func writeNPSSO(profileID: String, expected: NPSSOExpirySource, allowKeyCreation: Bool) throws {
        let context = SignInRow.npssoContext(profileID: profileID)
        var acquired = stamp
        var expires: Int64?
        var source = NPSSOExpirySource.unknown
        if let kept = try NPSSORow.fetchOne(database, sql: NPSSORow.selectForProfile, arguments: [profileID]),
           holds(kept.envelope, context: context, signIn.npsso) {
            acquired = kept.acquiredAt
            expires = kept.expiresAt
            source = kept.expirySource
        }
        if let obtained = signIn.npssoObtainedAt.map(Timestamp.milliseconds(of:)) {
            acquired = obtained
        }
        let held = source.isReadFromServer
            ? expires
            : nil
        if let reported = signIn.npssoExpiresAt.map(Timestamp.milliseconds(of:)), held != reported {
            expires = reported
            if expected.isReadFromServer {
                source = expected
            } else if held == nil {
                source = .tokenResponse
            }
        }
        let envelope = try cipher.seal(
            signIn.npsso, context: context, allowKeyCreation: allowKeyCreation
        )
        try database.execute(
            sql: NPSSORow.upsert,
            arguments: [profileID, envelope, acquired, stamp, expires, source.rawValue]
        )
    }

    private func holds(_ envelope: Data, context: String, _ npsso: borrowing SecretBytes) -> Bool {
        do {
            let kept = try cipher.open(envelope, context: context)
            return kept.isEqual(to: npsso)
        } catch {
            return false
        }
    }

    private func writeTokens(
        _ kind: String,
        access: CredentialTokenKind,
        refresh: CredentialTokenKind,
        profileID: String,
        allowKeyCreation: Bool
    ) throws {
        let accessToken = signIn.tokens[access]
        let refreshToken = signIn.tokens[refresh]
        guard accessToken != nil || refreshToken != nil else {
            try database.execute(sql: TokenRow.delete, arguments: [profileID, kind])
            return
        }
        let sealedAccess = try accessToken.map { (token) throws(PersistenceError) in
            try cipher.seal(
                token.value,
                context: TokenRow.context(profileID: profileID, kind: kind, part: .access),
                allowKeyCreation: allowKeyCreation
            )
        }
        let sealedRefresh = try refreshToken.map { (token) throws(PersistenceError) in
            try cipher.seal(
                token.value,
                context: TokenRow.context(profileID: profileID, kind: kind, part: .refresh),
                allowKeyCreation: allowKeyCreation
            )
        }
        try database.execute(
            sql: TokenRow.upsert,
            arguments: [
                profileID, kind, sealedAccess, sealedRefresh,
                accessToken.map {
                    $0.expiresAt.map(Timestamp.milliseconds(of:)) ?? 0
                },
                accessToken?.obtainedAt.map(Timestamp.milliseconds(of:)),
                refreshToken?.obtainedAt.map(Timestamp.milliseconds(of:)),
                refreshToken?.expiresAt.map(Timestamp.milliseconds(of:)),
                stamp
            ]
        )
    }
}

/// A profile without a signed-in NPSSO, decoded by column name.
private struct HomeUserRow: FetchableRecord, Sendable {
    /// The `psn_account_id` column.
    let accountID: Data

    /// The `display_name` column.
    let name: String

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``ProfileRow/selectHomeUsers``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        accountID = try row.decode(Data.self, forColumn: "psn_account_id")
        name = try row.decode(String.self, forColumn: "display_name")
    }

    /// The row as a home user, or `nil` when the account id is malformed.
    var stored: StoredHomeUser? {
        AccountID(bytes: accountID).map {
            StoredHomeUser(account: $0, name: name)
        }
    }
}
