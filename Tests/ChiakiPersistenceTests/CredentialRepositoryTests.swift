import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct CredentialRepositoryTests {
    let account = AccountID(value: 0x1122_3344_5566_7788)

    static func secret(_ text: String) -> SecretBytes {
        var bytes = Array(text.utf8)
        return SecretBytes(wiping: &bytes)
    }

    static func text(_ secret: borrowing SecretBytes) -> String {
        secret.withUnsafeBytes {
            String(bytes: $0, encoding: .utf8) ?? ""
        }
    }

    static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    func signIn(
        npsso: String = "npsso-one",
        obtained: Date? = date(1_760_000_000_100),
        expires: Date? = date(1_790_000_000_200),
        context: StatedAccountContext = StatedAccountContext()
    ) -> StoredSignIn {
        StoredSignIn(
            account: account,
            onlineID: "player_one",
            npsso: Self.secret(npsso),
            npssoObtainedAt: obtained,
            npssoExpiresAt: expires,
            tokens: [
                .storeAccess: StoredToken(
                    value: Self.secret("store-access"),
                    obtainedAt: Self.date(1_760_000_001_000),
                    expiresAt: Self.date(1_760_003_600_000)
                ),
                .storeRefresh: StoredToken(
                    value: Self.secret("store-refresh"),
                    obtainedAt: Self.date(1_760_000_002_000),
                    expiresAt: Self.date(1_770_000_000_000)
                ),
                .remotePlayAccess: StoredToken(
                    value: Self.secret("remote-access"), obtainedAt: nil,
                    expiresAt: Self.date(1_760_007_200_000)
                ),
                .remotePlayRefresh: StoredToken(
                    value: Self.secret("remote-refresh"),
                    obtainedAt: nil,
                    expiresAt: nil
                )
            ],
            region: AccountRegion(country: "GB", language: "en"),
            context: context
        )
    }

    @Test func everyTokenAndDateSurvivesClosingAndReopening() throws {
        let file = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        let keys = KeychainKeyStore(source: .memory())
        let first = try CredentialRepository(database: AppDatabase(path: file.path, keys: keys))
        let context = StatedAccountContext(
            legalCountry: "GB", locale: "en-GB", age: 0, isChild: false,
            issuedAt: Self.date(1_760_000_000_000)
        )
        first.expect(PendingProfile(id: UUID(), name: "Player", expirySource: .tokenResponse))
        try first.save(signIn(context: context))

        let reopened = try CredentialRepository(database: AppDatabase(path: file.path, keys: keys))
        let loaded = try #require(reopened.savedSignIns().first)
        #expect(loaded.account == account)
        #expect(loaded.onlineID == "player_one")
        #expect(Self.text(loaded.npsso) == "npsso-one")
        #expect(loaded.npssoObtainedAt == Self.date(1_760_000_000_100))
        #expect(loaded.npssoExpiresAt == Self.date(1_790_000_000_200))
        #expect(loaded.tokens.count == 4)
        #expect(loaded.tokens[.storeAccess].map { Self.text($0.value) } == "store-access")
        #expect(loaded.tokens[.storeAccess]?.obtainedAt == Self.date(1_760_000_001_000))
        #expect(loaded.tokens[.storeAccess]?.expiresAt == Self.date(1_760_003_600_000))
        #expect(loaded.tokens[.storeRefresh]?.expiresAt == Self.date(1_770_000_000_000))
        #expect(loaded.tokens[.remotePlayAccess]?.obtainedAt == nil)
        #expect(loaded.tokens[.remotePlayRefresh].map { Self.text($0.value) } == "remote-refresh")
        #expect(loaded.tokens[.remotePlayRefresh]?.expiresAt == nil)
        #expect(loaded.region == AccountRegion(country: "GB", language: "en"))
        #expect(loaded.context == context)
        #expect(loaded.deviceID?.hasPrefix(CloudInstallationRepository.prefix) == true)
        let disk = try Data(contentsOf: file)
        for secret in ["npsso-one", "store-access", "store-refresh", "remote-access", "remote-refresh"] {
            #expect(disk.range(of: Data(secret.utf8)) == nil)
        }
    }

    @Test func aSaveFromTheCoreNeverErasesAnExpiryReadFromTheServer() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        repository.expect(PendingProfile(id: UUID(), name: "Player", expirySource: .cookie))
        try repository.save(signIn())
        try repository.save(signIn(obtained: nil, expires: nil))
        let loaded = try #require(repository.savedSignIns().first)
        #expect(loaded.npssoExpiresAt == Self.date(1_790_000_000_200))
        #expect(loaded.npssoObtainedAt == Self.date(1_760_000_000_100))
        let source: String? = try fixture.scalar("SELECT expiry_source FROM profile_npsso")
        #expect(source == "cookie")
    }

    @Test func anotherNPSSOStartsWithItsOwnDatesAndAnUnreadExpiryIsNotHandedBack() throws {
        let stamp = Self.date(1_765_000_000_000)
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database, now: {
            stamp
        })
        try repository.save(signIn(npsso: "first", obtained: nil, expires: nil))
        let first = try #require(repository.savedSignIns().first)
        #expect(first.npssoObtainedAt == stamp)
        #expect(first.npssoExpiresAt == nil)
        try repository.save(signIn(npsso: "second", obtained: nil, expires: Self.date(1_799_000_000_000)))
        let second = try #require(repository.savedSignIns().first)
        #expect(second.npssoExpiresAt == Self.date(1_799_000_000_000))
        let source: String? = try fixture.scalar("SELECT expiry_source FROM profile_npsso")
        #expect(source == "token_response")
    }

    @Test func theNewProfileTakesTheAnnouncedIdAndASignInAgainKeepsIt() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        let id = UUID()
        repository.expect(PendingProfile(id: id, name: "Player"))
        try repository.save(signIn())
        repository.expect(PendingProfile(id: UUID(), name: "Other"))
        try repository.save(signIn())
        let ids = try fixture.database.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM profiles")
        }
        #expect(ids == [id.uuidString])
    }

    @Test func withdrawingAnotherAttemptsProfileKeepsThisAnnouncement() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        let id = UUID()
        repository.expect(PendingProfile(id: id, name: "Player"))
        repository.withdraw(UUID())
        try repository.save(signIn())
        let ids = try fixture.database.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM profiles")
        }
        #expect(ids == [id.uuidString])
    }

    @Test func removingTheAccountTakesItsTokensAndContext() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        try repository.save(signIn(context: StatedAccountContext(age: 20)))
        try repository.remove(account)
        for table in ["profiles", "profile_npsso", "profile_tokens", "account_context"] {
            let count: Int? = try fixture.scalar("SELECT count(*) FROM \(table)")
            #expect(count == 0, "\(table)")
        }
    }

    @Test func homeUsersAreSavedOnceAndListedWithoutSignIns() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        let other = AccountID(value: 42)
        try repository.save(StoredHomeUser(account: other, name: "Guest"))
        try repository.save(StoredHomeUser(account: other, name: "Renamed"))
        try repository.save(signIn())
        #expect(try repository.homeUsers() == [StoredHomeUser(account: other, name: "Guest")])
        #expect(try repository.savedSignIns().count == 1)
    }

    @Test func aStatelessSaveKeepsTheStoredContextAndRegion() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        let context = StatedAccountContext(legalCountry: "DE", locale: "de-DE", age: 40, isChild: nil)
        try repository.save(signIn(context: context))
        try repository.save(StoredSignIn(
            account: account,
            onlineID: "player_one",
            npsso: Self.secret("npsso-one")
        ))
        let loaded = try #require(repository.savedSignIns().first)
        #expect(loaded.context == context)
        #expect(loaded.region == AccountRegion(country: "GB", language: "en"))
        #expect(loaded.tokens.isEmpty)
    }

    @Test func aTokenThatDoesNotOpenDropsOnlyItsSignIn() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        try repository.save(signIn())
        try fixture.database.write { database in
            try database
                .execute(
                    sql: "UPDATE profile_tokens SET encrypted_refresh = X'01DEAD' WHERE credential_kind = 'remote_play'"
                )
        }
        #expect(try repository.savedSignIns().isEmpty)
    }

    @Test func notingAnNPSSOChecksItsExpiry() throws {
        let fixture = try TestDatabase()
        let repository = CredentialRepository(database: fixture.database)
        let id = UUID()
        repository.expect(PendingProfile(id: id, name: "Player"))
        try repository.save(signIn(obtained: nil, expires: nil))
        #expect(throws: PersistenceError.invalidInput) {
            try repository.noteNPSSO(
                Self.secret("npsso-one"),
                expiresAt: Date(timeIntervalSinceNow: -60),
                source: .cookie,
                for: id
            )
        }
        #expect(throws: PersistenceError.invalidInput) {
            try repository.noteNPSSO(Self.secret("a;b"), expiresAt: nil, source: .unknown, for: id)
        }
        #expect(throws: PersistenceError.invalidInput) {
            try repository.noteNPSSO(Self.secret("npsso-one"), expiresAt: nil, source: .cookie, for: id)
        }
        let expiry = Date(timeIntervalSinceNow: 86400)
        try repository.noteNPSSO(Self.secret("npsso-one"), expiresAt: expiry, source: .cookie, for: id)
        let loaded = try #require(repository.savedSignIns().first)
        #expect(loaded.npssoExpiresAt.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
            == Int64((expiry.timeIntervalSince1970 * 1000).rounded()))
    }
}
