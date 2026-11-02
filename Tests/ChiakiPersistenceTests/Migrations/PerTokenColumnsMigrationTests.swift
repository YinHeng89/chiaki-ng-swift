import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct PerTokenColumnsMigrationTests {
    let profile = "6F1C2B8E-0000-4000-8000-0000000000AA"
    let account = AccountID(value: 0x0102_0304_0506_0708)

    func databaseAtSeventeen(keys: KeychainKeyStore = KeychainKeyStore(source: .memory())) throws
        -> LegacyDatabase {
        let legacy = try LegacyDatabase(version: 17, keys: keys)
        try insertAccount(into: legacy)
        try insertPairings(into: legacy)
        return legacy
    }

    func insertAccount(into legacy: LegacyDatabase) throws {
        try legacy.execute(
            """
            INSERT INTO profiles(id, display_name, auth_method, psn_account_id, psn_online_id)
            VALUES (?, 'Player', 'npsso', ?, 'player')
            """,
            [profile, account.data]
        )
        try legacy.execute(
            """
            INSERT INTO profile_npsso(profile_id, encrypted_value, key_version, acquired_at, validated_at, expires_at,
                expiry_source)
            VALUES (?, ?, 1, 1760000000000, 1760000000000, NULL, 'unknown')
            """,
            [profile, legacy.seal("npsso-value", context: "account:\(profile):npsso:v1")]
        )
        try legacy.execute(
            """
            INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_tokens, key_version, expires_at,
                updated_at, access_obtained_at_ms, refresh_obtained_at_ms, refresh_expires_at_ms)
            VALUES (?, 'remote_play', ?, 1, 1767225600000, 1760000000500, 1760000000001, 1760000000002,
                1790000000000)
            """,
            [
                profile,
                legacy.seal(
                    #"{"access":"rp-access\/1","refresh":"rp-refresh"}"#,
                    context: "account:\(profile):remote_play:v1"
                )
            ]
        )
        try legacy.execute(
            """
            INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_tokens, key_version, expires_at,
                updated_at, access_obtained_at_ms, refresh_obtained_at_ms, refresh_expires_at_ms)
            VALUES (?, 'mobile_sso', ?, 1, 0, 1760000000600, NULL, NULL, NULL)
            """,
            [
                profile,
                legacy.seal(
                    #"{"access":"","refresh":"store-refresh"}"#,
                    context: "account:\(profile):mobile_sso:v1"
                )
            ]
        )
    }

    func insertPairings(into legacy: LegacyDatabase) throws {
        try legacy.execute(
            """
            INSERT INTO consoles(id, hardware_id, name, generation, firmware)
            VALUES ('c', 'a1b2c3d4e5f6', 'Den', 'ps4', 'ps4_8');
            INSERT INTO consoles(id, hardware_id, name, generation, firmware)
            VALUES ('d', '0a0b0c0d0e0f', 'Lounge', 'ps5', 'ps5');
            """
        )
        let pairing = """
        {"version":1,"target":1000,"hardwareID":"obLD1OX2","nickname":"Den",\
        "registrationKey":"AwMDAwMDAwMDAwMDAwMDAw==","remotePlayKey":"BAQEBAQEBAQEBAQEBAQEBA==","keyType":7,\
        "remoteDeviceID":"\(Data(repeating: 9, count: 32).base64EncodedString())"}
        """
        try legacy.execute(
            """
            INSERT INTO registrations(id, profile_id, console_id, encrypted_credentials, key_version, created_at)
            VALUES ('kept', ?, 'c', ?, 1, 1760000000700)
            """,
            [profile, legacy.seal(pairing, context: "connection:kept:\(profile):c:v1")]
        )
        try legacy.execute(
            """
            INSERT INTO registrations(id, profile_id, console_id, encrypted_credentials, key_version, created_at)
            VALUES ('broken', ?, 'd', X'01DEADBEEF', 1, 1760000000800)
            """,
            [profile]
        )
    }

    func database(from legacy: LegacyDatabase, keys: KeychainKeyStore) throws -> AppDatabase {
        try legacy.migrate()
        let file = TestDatabase.scratchFile()
        try legacy.queue.backup(to: DatabaseQueue(path: file.path))
        return try AppDatabase(path: file.path, keys: keys)
    }

    @Test func eachTokenGetsItsOwnEnvelopeAndLoadsWithItsDates() throws {
        let keys = KeychainKeyStore(source: .memory())
        let legacy = try databaseAtSeventeen(keys: keys)
        try legacy.migrate()
        let rows = try legacy.rows(
            "SELECT * FROM profile_tokens ORDER BY credential_kind"
        )
        #expect(rows.count == 2)
        let store = rows[0]
        #expect(store["credential_kind"] as String == "mobile_sso")
        #expect(store["encrypted_access"] as Data? == nil)
        #expect(store["access_expires_at"] as Int64? == nil)
        #expect(store["encrypted_refresh"] as Data? != nil)
        let remote = rows[1]
        #expect(remote["access_expires_at"] as Int64? == 1_767_225_600_000)
        #expect(remote["access_obtained_at"] as Int64? == 1_760_000_000_001)
        #expect(remote["refresh_obtained_at"] as Int64? == 1_760_000_000_002)
        #expect(remote["refresh_expires_at"] as Int64? == 1_790_000_000_000)
        #expect(remote["updated_at"] as Int64 == 1_760_000_000_500)

        let database = try database(from: legacy, keys: keys)
        let signIns = try CredentialRepository(database: database).savedSignIns()
        let signIn = try #require(signIns.first)
        #expect(signIns.count == 1)
        #expect(signIn.account == account)
        #expect(Self.text(signIn.npsso) == "npsso-value")
        #expect(signIn.tokens[.remotePlayAccess].map { Self.text($0.value) } == "rp-access/1")
        #expect(signIn.tokens[.remotePlayRefresh].map { Self.text($0.value) } == "rp-refresh")
        #expect(signIn.tokens[.storeRefresh].map { Self.text($0.value) } == "store-refresh")
        #expect(signIn.tokens[.storeAccess] == nil)
        #expect(signIn.tokens[.remotePlayAccess]?.expiresAt == Date(timeIntervalSince1970: 1_767_225_600))
    }

    @Test func pairingKeysAreResealedAsRawBytesWithTheirKeyTypeAndDevice() throws {
        let keys = KeychainKeyStore(source: .memory())
        let legacy = try databaseAtSeventeen(keys: keys)
        try legacy.migrate()
        let rows = try legacy.rows("SELECT id, key_type, remote_device_id, created_at FROM registrations")
        #expect(rows.map { $0["id"] as String } == ["kept"])
        #expect(rows.first?["key_type"] as Int? == 7)
        #expect(rows.first?["remote_device_id"] as Data? == Data(repeating: 9, count: 32))
        #expect(rows.first?["created_at"] as Int64? == 1_760_000_000_700)

        let database = try database(from: legacy, keys: keys)
        let pairings = try ConsoleRepository(database: database).savedConsoles().pairings
        let pairing = try #require(pairings.first)
        #expect(pairings.count == 1)
        #expect(pairing.account == account)
        #expect(pairing.credentials.keyType == 7)
        var registration = [UInt8](repeating: 3, count: 16)
        var remotePlay = [UInt8](repeating: 4, count: 16)
        guard let expected = PairingCredentials(
            registrationKey: SecretBytes(wiping: &registration),
            remotePlayKey: SecretBytes(wiping: &remotePlay),
            keyType: 7
        ) else {
            Issue.record("The expected keys are malformed")
            return
        }
        let same = pairing.credentials.isEqual(to: expected)
        #expect(same)
    }

    @Test func aKeychainThatRefusesTheKeyLeavesTheDatabaseAtSeventeen() throws {
        let keys = KeychainKeyStore(source: .memory())
        let legacy = try databaseAtSeventeen(keys: keys)
        let refusing = LegacyDatabaseWithRefusingKeychain(legacy)
        #expect(throws: PersistenceError.keyUnavailable(status: -25308)) {
            try refusing.migrate()
        }
        #expect(try legacy.version() == 17)
        #expect(try legacy.rows("SELECT encrypted_tokens FROM profile_tokens").count == 2)
    }

    @Test func aDatabaseWithoutCredentialsNeedsNoKey() throws {
        let legacy = try LegacyDatabase(version: 17)
        try legacy.migrate(to: 18)
        #expect(try legacy.version() == 18)
        #expect(try legacy.rows("SELECT * FROM profile_tokens").isEmpty)
    }

    static func text(_ secret: borrowing SecretBytes) -> String {
        secret.withUnsafeBytes {
            String(bytes: $0, encoding: .utf8) ?? ""
        }
    }
}

struct LegacyDatabaseWithRefusingKeychain {
    let legacy: LegacyDatabase

    init(_ legacy: LegacyDatabase) {
        self.legacy = legacy
    }

    func migrate() throws {
        let refusing = KeySource(
            read: { () throws(ChiakiPersistence.PersistenceError) -> SecretBytes? in
                throw .keyUnavailable(status: -25308)
            },
            create: { (_: borrowing SecretBytes) throws(ChiakiPersistence.PersistenceError) -> SecretBytes in
                throw .keyUnavailable(status: -25308)
            }
        )
        try MigrationRunner.apply(
            MigrationRunner.bundled(),
            to: legacy.queue,
            cipher: CredentialCipher(keys: KeychainKeyStore(source: refusing))
        )
    }
}
