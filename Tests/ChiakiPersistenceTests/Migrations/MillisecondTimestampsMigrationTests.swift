@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct MillisecondTimestampsMigrationTests {
    func databaseAtSixteen() throws -> LegacyDatabase {
        let legacy = try LegacyDatabase(version: 16)
        try legacy.execute(
            """
            INSERT INTO profiles(id, display_name, auth_method, psn_account_id, psn_online_id, created_at, updated_at)
            VALUES ('p', 'Player', 'npsso', ?, 'player', '2025-10-09T08:00:00.123Z', '2025-10-09T08:05:00Z');
            INSERT INTO consoles(id, hardware_id, name, generation, last_address, firmware, connect_at_launch,
                encrypted_login_pin, login_pin_profile_id)
            VALUES ('c', 'a1b2c3d4e5f6', 'Den', 'ps5', '192.0.2.4', 'ps5', 1, X'01AABB', 'p');
            INSERT INTO registrations(id, profile_id, console_id, encrypted_credentials, key_version, created_at)
            VALUES ('r', 'p', 'c', X'01CCDD', 1, '2025-10-09T09:00:00.500Z');
            INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_tokens, key_version, expires_at,
                updated_at, access_obtained_at_ms, refresh_obtained_at_ms, refresh_expires_at_ms)
            VALUES ('p', 'remote_play', X'01EEFF', 1, '2026-01-01T00:00:00Z', '2025-10-09T08:05:00Z',
                '1760000000001', 1760000000002, NULL);
            INSERT INTO profile_npsso(profile_id, encrypted_value, key_version, acquired_at, validated_at, expires_at,
                expiry_source)
            VALUES ('p', X'010203', 1, 1760000000.25, '1760000001.5', 1790000000.0, 'cookie');
            INSERT INTO account_resource_cache(profile_id, resource, payload, source_url, fetched_at, expires_at)
            VALUES ('p', 'avatar', X'89504E47', 'https://example.invalid/a.png', 1760000002.0, 1760000902.0);
            INSERT INTO kakusan_identity(id, encrypted_seed, public_key, key_version, created_at)
            VALUES (1, X'0102', zeroblob(32), 1, 1760000003.0);
            INSERT INTO kakusan_peers(public_key, fingerprint, nickname, first_verified_at, last_seen_at)
            VALUES (randomblob(32), zeroblob(32), 'Alex', '1760000004.5', 1760000005.25);
            """,
            [Data(repeating: 7, count: 8)]
        )
        let settings = """
        {"selectsAtLaunch":true,"lastConnection":{"name":"frankfurt","rttMs":24,"service":"psnow",\
        "connectedAt":\(LegacyDatabase.referenceSeconds(1_760_000_100_250))}}
        """
        try legacy.execute(
            "INSERT INTO settings(key, value_json) VALUES ('cloud.datacenters.v1', ?)",
            [settings]
        )
        try legacy.execute(
            """
            DROP TABLE schema_migrations;
            CREATE TABLE schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
            );
            """
        )
        for version in 1 ... 16 {
            try legacy.execute(
                "INSERT INTO schema_migrations(version, applied_at) VALUES (?, '2025-10-09T08:00:00.123Z')",
                [version]
            )
        }
        return legacy
    }

    func single(_ legacy: LegacyDatabase, _ sql: String) throws -> Row {
        try #require(legacy.rows(sql).first)
    }

    @Test func everyEncodingBecomesWholeMilliseconds() throws {
        let legacy = try databaseAtSixteen()
        try legacy.migrate(to: 17)
        let profile = try single(
            legacy,
            "SELECT created_at, updated_at, typeof(created_at) AS kind FROM profiles"
        )
        #expect(profile["created_at"] as Int64 == 1_759_996_800_123)
        #expect(profile["updated_at"] as Int64 == 1_759_997_100_000)
        #expect(profile["kind"] as String == "integer")
        #expect(try single(legacy, "SELECT created_at FROM registrations")["created_at"] as Int64 ==
            1_760_000_400_500)
        let token = try single(
            legacy,
            "SELECT expires_at, updated_at, access_obtained_at_ms, refresh_obtained_at_ms FROM profile_tokens"
        )
        #expect(token["expires_at"] as Int64 == 1_767_225_600_000)
        #expect(token["updated_at"] as Int64 == 1_759_997_100_000)
        #expect(token["access_obtained_at_ms"] as Int64 == 1_760_000_000_001)
        #expect(token["refresh_obtained_at_ms"] as Int64 == 1_760_000_000_002)
        let npsso = try single(
            legacy,
            "SELECT acquired_at, validated_at, expires_at, expiry_source FROM profile_npsso"
        )
        #expect(npsso["acquired_at"] as Int64 == 1_760_000_000_250)
        #expect(npsso["validated_at"] as Int64 == 1_760_000_001_500)
        #expect(npsso["expires_at"] as Int64 == 1_790_000_000_000)
        #expect(npsso["expiry_source"] as String == "cookie")
        let cache = try single(legacy, "SELECT fetched_at, expires_at, payload FROM account_resource_cache")
        #expect(cache["fetched_at"] as Int64 == 1_760_000_002_000)
        #expect(cache["expires_at"] as Int64 == 1_760_000_902_000)
        #expect(cache["payload"] as Data == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(try single(legacy, "SELECT created_at FROM kakusan_identity")["created_at"] as Int64
            == 1_760_000_003_000)
        let peer = try single(legacy, "SELECT first_verified_at, last_seen_at FROM kakusan_peers")
        #expect(peer["first_verified_at"] as Int64 == 1_760_000_004_500)
        #expect(peer["last_seen_at"] as Int64 == 1_760_000_005_250)
    }

    @Test func theLedgerAndTheSettingsDatesBecomeMillisecondsToo() throws {
        let legacy = try databaseAtSixteen()
        try legacy.migrate(to: 17)
        let ledger = try legacy
            .rows("SELECT version, applied_at, typeof(applied_at) AS kind FROM schema_migrations")
        #expect(ledger.count == 17)
        #expect(ledger.allSatisfy {
            $0["kind"] as String == "integer"
        })
        #expect(ledger.first?["applied_at"] as Int64? == 1_759_996_800_123)
        let json: String = try single(legacy, "SELECT value_json FROM settings")["value_json"]
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let connection = try #require(object["lastConnection"] as? [String: Any])
        #expect((connection["connectedAt"] as? NSNumber)?.int64Value == 1_760_000_100_250)
    }

    @Test func theTriggersAndForeignKeysSurviveTheRebuild() throws {
        let legacy = try databaseAtSixteen()
        try legacy.migrate(to: 17)
        #expect(try legacy.rows("PRAGMA foreign_key_check").isEmpty)
        try legacy.execute("DELETE FROM registrations")
        let console = try single(legacy, "SELECT connect_at_launch, encrypted_login_pin FROM consoles")
        #expect(console["connect_at_launch"] as Int == 0)
        #expect(console["encrypted_login_pin"] as Data? == nil)
        try legacy.execute("DELETE FROM profiles")
        #expect(try legacy.rows("SELECT * FROM profile_tokens").isEmpty)
        #expect(try legacy.rows("SELECT * FROM profile_npsso").isEmpty)
        #expect(try legacy.rows("SELECT * FROM account_resource_cache").isEmpty)
    }

    @Test func aTextTimeIsRefusedAfterTheMigration() throws {
        let legacy = try databaseAtSixteen()
        try legacy.migrate(to: 17)
        #expect(throws: DatabaseError.self) {
            try legacy.execute("UPDATE profile_npsso SET acquired_at = 'soon'")
        }
    }
}
