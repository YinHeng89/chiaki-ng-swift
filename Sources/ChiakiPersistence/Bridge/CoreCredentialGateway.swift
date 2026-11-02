import ChiakiModels
import Foundation

/// The credential store as the C++ credential store adapter reaches it through ``CoreStoreGateway``.
///
/// Every method takes and returns only what the generated C++ header can represent. Failures come back as
/// `false` or `nil`; the cause is reported by the store itself.
public final class CoreCredentialGateway {
    private let credentials: any CredentialStoring

    /// Creates the gateway over the credential store.
    ///
    /// - Parameter credentials: Where signed-in accounts and home users are persisted.
    init(credentials: any CredentialStoring) {
        self.credentials = credentials
    }

    /// Loads every saved sign-in.
    ///
    /// - Returns: The ledger, or `nil` when the store could not be read.
    public func loadSignIns() -> CoreSignInLedger? {
        do {
            return try CoreSignInLedger(credentials.savedSignIns())
        } catch {
            return nil
        }
    }

    /// Loads every saved home user.
    ///
    /// - Returns: The ledger, or `nil` when the store could not be read.
    public func loadHomeUsers() -> CoreHomeUserLedger? {
        do {
            return try CoreHomeUserLedger(credentials.homeUsers())
        } catch {
            return nil
        }
    }

    /// Starts a sign-in to save, copying its NPSSO straight into a wiping buffer.
    ///
    /// - Parameters:
    ///   - accountID: Exactly eight account id bytes, least significant first.
    ///   - onlineID: The online id.
    ///   - npsso: The NPSSO's text bytes.
    ///   - npssoCount: How many NPSSO bytes.
    /// - Returns: The draft to fill and pass to ``saveSignIn(_:)``.
    public func beginSignIn(
        accountID: UnsafeRawPointer,
        onlineID: String,
        npsso: UnsafeRawPointer,
        npssoCount: Int
    ) -> CoreSignInDraft {
        let secret = SecretBytes(count: npssoCount) { buffer in
            buffer.copyMemory(from: UnsafeRawBufferPointer(start: npsso, count: npssoCount))
        }
        let account = CoreRawBytes.account(accountID)
        return CoreSignInDraft(account: account ?? AccountID(value: 0), onlineID: onlineID, npsso: secret)
    }

    /// Saves a sign-in assembled with ``beginSignIn(accountID:onlineID:npsso:npssoCount:)``.
    ///
    /// - Parameter draft: The draft; it cannot be saved twice.
    /// - Returns: `true` when the sign-in was saved.
    public func saveSignIn(_ draft: CoreSignInDraft) -> Bool {
        guard let signIn = draft.finish() else {
            return false
        }
        do {
            try credentials.save(signIn)
            return true
        } catch {
            return false
        }
    }

    /// Saves an account added by id only.
    ///
    /// - Parameters:
    ///   - accountID: Exactly eight account id bytes.
    ///   - name: The display name.
    /// - Returns: `true` when the home user was saved or was saved already.
    public func saveHomeUser(accountID: UnsafeRawPointer, name: String) -> Bool {
        guard let account = CoreRawBytes.account(accountID) else {
            return false
        }
        do {
            try credentials.save(StoredHomeUser(account: account, name: name))
            return true
        } catch {
            return false
        }
    }

    /// Deletes an account and everything stored for it.
    ///
    /// - Parameter accountID: Exactly eight account id bytes.
    /// - Returns: `true` when the delete succeeded.
    public func removeAccount(accountID: UnsafeRawPointer) -> Bool {
        guard let account = CoreRawBytes.account(accountID) else {
            return false
        }
        do {
            try credentials.remove(account)
            return true
        } catch {
            return false
        }
    }
}

/// A sign-in a C++ store adapter assembles before saving it through ``CoreCredentialGateway/saveSignIn(_:)``.
///
/// Secrets are copied from the adapter's memory straight into wiping buffers. Times are whole milliseconds
/// since 1970.
public final class CoreSignInDraft {
    private let account: AccountID
    private let onlineID: String
    private var npsso: SecretBytes?
    private var npssoObtainedAt: Date?
    private var npssoExpiresAt: Date?
    private var tokens: [CredentialTokenKind: StoredToken] = [:]
    private var region: AccountRegion?
    private var legalCountry: String?
    private var locale: String?
    private var age: Int?
    private var isChild: Bool?
    private var contextIssuedAt: Date?

    /// Starts a draft.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - onlineID: The online id.
    ///   - npsso: The NPSSO's bytes.
    init(account: AccountID, onlineID: String, npsso: consuming SecretBytes) {
        self.account = account
        self.onlineID = onlineID
        self.npsso = .some(npsso)
    }

    /// Sets when the NPSSO was obtained.
    ///
    /// - Parameter milliseconds: Milliseconds since 1970.
    public func setNPSSOObtainedAt(_ milliseconds: Int64) {
        npssoObtainedAt = Timestamp.date(milliseconds: milliseconds)
    }

    /// Sets when the NPSSO expires.
    ///
    /// - Parameter milliseconds: Milliseconds since 1970.
    public func setNPSSOExpiresAt(_ milliseconds: Int64) {
        npssoExpiresAt = Timestamp.date(milliseconds: milliseconds)
    }

    /// Copies a token and its dates into the draft.
    ///
    /// - Parameters:
    ///   - kind: The token.
    ///   - bytes: The token's text bytes.
    ///   - count: How many bytes.
    ///   - obtainedAt: When it was obtained, in milliseconds since 1970, if known.
    ///   - expiresAt: When it expires, in milliseconds since 1970, if known.
    public func setToken(
        _ kind: CoreTokenKind,
        bytes: UnsafeRawPointer,
        count: Int,
        obtainedAt: Int64?,
        expiresAt: Int64?
    ) {
        let value = SecretBytes(count: count) { buffer in
            buffer.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: count))
        }
        tokens[kind.kind] = StoredToken(
            value: value,
            obtainedAt: obtainedAt.map(Timestamp.date(milliseconds:)),
            expiresAt: expiresAt.map(Timestamp.date(milliseconds:))
        )
    }

    /// Sets the region.
    ///
    /// - Parameters:
    ///   - country: The country code.
    ///   - language: The language code.
    public func setRegion(country: String, language: String) {
        region = AccountRegion(country: country, language: language)
    }

    /// Sets the stated legal country.
    ///
    /// - Parameter country: The country.
    public func setLegalCountry(_ country: String) {
        legalCountry = country
    }

    /// Sets the stated locale.
    ///
    /// - Parameter locale: The locale.
    public func setLocale(_ locale: String) {
        self.locale = locale
    }

    /// Sets the stated age.
    ///
    /// - Parameter age: The age.
    public func setAge(_ age: Int64) {
        self.age = Int(clamping: age)
    }

    /// Sets whether the account is stated to be a child account.
    ///
    /// - Parameter isChild: The statement.
    public func setIsChild(_ isChild: Bool) {
        self.isChild = isChild
    }

    /// Sets when the stated context was issued.
    ///
    /// - Parameter milliseconds: Milliseconds since 1970.
    public func setContextIssuedAt(_ milliseconds: Int64) {
        contextIssuedAt = Timestamp.date(milliseconds: milliseconds)
    }

    /// Hands the assembled sign-in over; a second call returns `nil`.
    ///
    /// - Returns: The sign-in, its NPSSO moved out of the draft.
    func finish() -> StoredSignIn? {
        switch npsso.take() {
        case .some(let secret):
            return StoredSignIn(
                account: account,
                onlineID: onlineID,
                npsso: secret,
                npssoObtainedAt: npssoObtainedAt,
                npssoExpiresAt: npssoExpiresAt,
                tokens: tokens,
                region: region,
                context: StatedAccountContext(
                    legalCountry: legalCountry, locale: locale, age: age, isChild: isChild,
                    issuedAt: contextIssuedAt
                )
            )
        case .none:
            return nil
        }
    }
}

/// Every saved sign-in, handed to a C++ store adapter in one load.
///
/// The ledger keeps the loaded sign-ins, whose NPSSOs and tokens stay in wiping buffers until the adapter
/// copies each secret into memory it owns. The secrets are wiped when the ledger is released.
public final class CoreSignInLedger {
    /// The non-secret parts of every sign-in, in the order the copy methods index them.
    public let signIns: [CoreSignInRecord]

    private let saved: [StoredSignIn]

    /// Mirrors a load from the credential store.
    ///
    /// - Parameter saved: The loaded sign-ins.
    init(_ saved: [StoredSignIn]) {
        signIns = saved.map(CoreSignInRecord.init)
        self.saved = saved
    }

    /// The length of a sign-in's NPSSO.
    ///
    /// - Parameter index: The sign-in's position in ``signIns``.
    /// - Returns: The length in bytes, or `-1` when `index` is out of range.
    public func npssoLength(ofSignIn index: Int) -> Int {
        guard saved.indices.contains(index) else {
            return -1
        }
        return saved[index].npsso.count
    }

    /// Copies a sign-in's NPSSO into a buffer the caller owns.
    ///
    /// - Parameters:
    ///   - index: The sign-in's position in ``signIns``.
    ///   - buffer: At least ``npssoLength(ofSignIn:)`` bytes.
    /// - Returns: `false` when `index` is out of range; nothing is written then.
    public func copyNPSSO(ofSignIn index: Int, into buffer: UnsafeMutableRawPointer) -> Bool {
        guard saved.indices.contains(index) else {
            return false
        }
        saved[index].npsso.withUnsafeBytes {
            UnsafeMutableRawBufferPointer(start: buffer, count: $0.count).copyMemory(from: $0)
        }
        return true
    }

    /// The length of one of a sign-in's tokens.
    ///
    /// - Parameters:
    ///   - index: The sign-in's position in ``signIns``.
    ///   - kind: The token.
    /// - Returns: The length in bytes, or `-1` when the sign-in holds no such token or `index` is out of range.
    public func tokenLength(ofSignIn index: Int, _ kind: CoreTokenKind) -> Int {
        token(index, kind)?.value.count ?? -1
    }

    /// Copies one of a sign-in's tokens into a buffer the caller owns.
    ///
    /// - Parameters:
    ///   - index: The sign-in's position in ``signIns``.
    ///   - kind: The token.
    ///   - buffer: At least ``tokenLength(ofSignIn:_:)`` bytes.
    /// - Returns: `false` when there is no such token; nothing is written then.
    public func copyToken(ofSignIn index: Int, _ kind: CoreTokenKind,
                          into buffer: UnsafeMutableRawPointer) -> Bool {
        guard let token = token(index, kind) else {
            return false
        }
        token.value.withUnsafeBytes {
            UnsafeMutableRawBufferPointer(start: buffer, count: $0.count).copyMemory(from: $0)
        }
        return true
    }

    /// When one of a sign-in's tokens was obtained.
    ///
    /// - Parameters:
    ///   - index: The sign-in's position in ``signIns``.
    ///   - kind: The token.
    /// - Returns: Milliseconds since 1970, or `nil` when unknown or there is no such token.
    public func tokenObtainedAt(ofSignIn index: Int, _ kind: CoreTokenKind) -> Int64? {
        token(index, kind)?.obtainedAt.map(Timestamp.milliseconds(of:))
    }

    /// When one of a sign-in's tokens expires.
    ///
    /// - Parameters:
    ///   - index: The sign-in's position in ``signIns``.
    ///   - kind: The token.
    /// - Returns: Milliseconds since 1970, or `nil` when unknown or there is no such token.
    public func tokenExpiresAt(ofSignIn index: Int, _ kind: CoreTokenKind) -> Int64? {
        token(index, kind)?.expiresAt.map(Timestamp.milliseconds(of:))
    }

    private func token(_ index: Int, _ kind: CoreTokenKind) -> StoredToken? {
        guard saved.indices.contains(index) else {
            return nil
        }
        return saved[index].tokens[kind.kind]
    }
}

/// The parts of a saved sign-in that are not secret, as the C++ store adapters read them.
///
/// The NPSSO and tokens are copied separately through ``CoreSignInLedger`` straight into buffers the adapter
/// owns and wipes. Times are whole milliseconds since 1970.
public struct CoreSignInRecord {
    /// The eight account id bytes, least significant first.
    public let accountID: [UInt8]

    /// The online id.
    public let onlineID: String

    /// When the NPSSO was obtained.
    public let npssoObtainedAt: Int64?

    /// When the NPSSO expires, when read from the server.
    public let npssoExpiresAt: Int64?

    /// The country, when a region is stored.
    public let country: String?

    /// The language, when a region is stored.
    public let language: String?

    /// The stated legal country.
    public let legalCountry: String?

    /// The stated locale.
    public let locale: String?

    /// The stated age.
    public let age: Int64?

    /// Whether the account is stated to be a child account.
    public let isChild: Bool?

    /// When the stated context was issued.
    public let contextIssuedAt: Int64?

    /// The installation's device id.
    public let deviceID: String?

    /// Mirrors the non-secret parts of a sign-in.
    ///
    /// - Parameter signIn: The sign-in.
    init(_ signIn: StoredSignIn) {
        accountID = signIn.account.bytes
        onlineID = signIn.onlineID
        npssoObtainedAt = signIn.npssoObtainedAt.map(Timestamp.milliseconds(of:))
        npssoExpiresAt = signIn.npssoExpiresAt.map(Timestamp.milliseconds(of:))
        country = signIn.region?.country
        language = signIn.region?.language
        legalCountry = signIn.context.legalCountry
        locale = signIn.context.locale
        age = signIn.context.age.map {
            Int64($0)
        }
        isChild = signIn.context.isChild
        contextIssuedAt = signIn.context.issuedAt.map(Timestamp.milliseconds(of:))
        deviceID = signIn.deviceID
    }
}

/// A credential token kind as the C++ store adapters see it.
///
/// It mirrors `ChiakiModels/CredentialTokenKind` case for case, because the generated C++ header cannot
/// expose a type from another module.
public enum CoreTokenKind {
    /// The PlayStation Store access token.
    case storeAccess

    /// The PlayStation Store refresh token.
    case storeRefresh

    /// The Remote Play access token.
    case remotePlayAccess

    /// The Remote Play refresh token.
    case remotePlayRefresh

    /// The model token kind.
    var kind: CredentialTokenKind {
        switch self {
        case .storeAccess:
            .storeAccess
        case .storeRefresh:
            .storeRefresh
        case .remotePlayAccess:
            .remotePlayAccess
        case .remotePlayRefresh:
            .remotePlayRefresh
        }
    }
}

/// Every saved home user, handed to a C++ store adapter in one load.
public final class CoreHomeUserLedger {
    /// The home users, oldest profile first.
    public let users: [CoreHomeUserRecord]

    /// Mirrors a load from the credential store.
    ///
    /// - Parameter users: The loaded home users.
    init(_ users: [StoredHomeUser]) {
        self.users = users.map(CoreHomeUserRecord.init)
    }
}

/// A saved home user as the C++ store adapters read it.
public struct CoreHomeUserRecord {
    /// The eight account id bytes, least significant first.
    public let accountID: [UInt8]

    /// The display name.
    public let name: String

    /// Mirrors a home user.
    ///
    /// - Parameter user: The home user.
    init(_ user: StoredHomeUser) {
        accountID = user.account.bytes
        name = user.name
    }
}
