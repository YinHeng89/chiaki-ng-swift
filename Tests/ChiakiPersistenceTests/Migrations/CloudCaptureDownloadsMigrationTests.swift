import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct CloudCaptureDownloadsMigrationTests {
    static let account = Data([1, 2, 3, 4, 5, 6, 7, 8])

    static let upstreamCaptures = """
    INSERT INTO cloud_capture_downloads(gallery_id, account_id, title, file_extension, video, created, folder,
        attempts, queued_at)
    VALUES ('psn1', ?, 'Game', '.jpg', '0', '2026-10-18T10:31:08Z', '/tmp/captures', 0, '2026-10-18T10:31:10Z');
    INSERT INTO cloud_capture_downloads(gallery_id, account_id, title, file_extension, video, created, folder,
        attempts, queued_at)
    VALUES ('psn2', ?, 'Other', '', '1', '', '/tmp/clips', 2, '2026-10-18T10:30:00Z');
    """

    func profiles(_ legacy: LegacyDatabase) throws {
        try legacy.execute(
            """
            INSERT INTO profiles(id, display_name, auth_method, psn_account_id, psn_online_id, created_at, updated_at)
            VALUES ('p', 'Player', 'npsso', ?, 'player', '2026-10-01T08:00:00.123Z', '2026-10-02T08:00:00Z');
            INSERT INTO consoles(id, hardware_id, name, generation, last_address)
            VALUES ('c', 'a1b2c3d4e5f6', 'Den', 'ps5', '192.0.2.4');
            """,
            [Self.account]
        )
    }

    func upstreamLedger(_ legacy: LegacyDatabase, through version: Int) throws {
        try legacy.execute(
            """
            DROP TABLE schema_migrations;
            CREATE TABLE schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
            );
            """
        )
        for step in 1 ... version {
            try legacy.execute(
                "INSERT INTO schema_migrations(version, applied_at) VALUES (?, '2026-10-18T09:00:00.000Z')",
                [step]
            )
        }
    }

    @Test func twelveAddsAnEmptyCaptureQueueAndKeepsTheAccounts() throws {
        let legacy = try LegacyDatabase(version: 11)
        try profiles(legacy)
        try legacy.migrate(to: 12)
        #expect(try legacy.version() == 12)
        #expect(try legacy.rows("SELECT * FROM cloud_capture_downloads").isEmpty)
        #expect(try legacy.rows("SELECT id FROM profiles").count == 1)
        try legacy.execute(Self.upstreamCaptures, [Self.account, Self.account])
        let rows = try legacy
            .rows("SELECT gallery_id, video FROM cloud_capture_downloads ORDER BY gallery_id")
        #expect(rows.map { $0["gallery_id"] as String } == ["psn1", "psn2"])
        #expect(rows.map { $0["video"] as Int } == [0, 1])
        #expect(throws: DatabaseError.self) {
            try legacy.execute(
                """
                INSERT INTO cloud_capture_downloads(gallery_id, account_id, title, file_extension, video, created,
                    folder, queued_at)
                VALUES ('', X'01', '', '', 0, '', '/tmp', '2026-10-18T10:31:10Z')
                """
            )
        }
    }

    @Test func seventeenTurnsTheCaptureTimesIntoMilliseconds() throws {
        let legacy = try LegacyDatabase(version: 16)
        try profiles(legacy)
        try legacy.execute(Self.upstreamCaptures, [Self.account, Self.account])
        try legacy.migrate(to: 17)
        let rows = try legacy.rows(
            """
            SELECT gallery_id, created, queued_at, typeof(queued_at) AS kind, video, attempts
            FROM cloud_capture_downloads ORDER BY gallery_id
            """
        )
        #expect(rows.count == 2)
        #expect(rows[0]["created"] as Int64? == 1_792_319_468_000)
        #expect(rows[0]["queued_at"] as Int64 == 1_792_319_470_000)
        #expect(rows[0]["kind"] as String == "integer")
        #expect(rows[1]["created"] as Int64? == nil)
        #expect(rows[1]["queued_at"] as Int64 == 1_792_319_400_000)
        #expect(rows[1]["video"] as Int == 1)
        #expect(rows[1]["attempts"] as Int == 2)
        #expect(throws: DatabaseError.self) {
            try legacy.execute("UPDATE cloud_capture_downloads SET queued_at = 'soon'")
        }
    }

    @Test func aDatabaseAtUpstreamsTwelveUpgradesThroughNineteen() throws {
        let path = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: path)
        }
        let keys = KeychainKeyStore(source: .memory())
        do {
            let legacy = try LegacyDatabase(version: 12, keys: keys, path: path.path)
            try profiles(legacy)
            try legacy.execute(Self.upstreamCaptures, [Self.account, Self.account])
            try upstreamLedger(legacy, through: 12)
            #expect(try legacy.version() == 12)
        }
        let database = try AppDatabase(path: path.path, keys: keys)
        let version: Int? = try database.read { database in
            try Int.fetchOne(database, sql: "PRAGMA user_version")
        }
        #expect(version == 19)
        let ledger = try database.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT version, typeof(applied_at) AS kind FROM schema_migrations"
            )
        }
        #expect(ledger.map { $0["version"] as Int } == Array(1 ... 19))
        #expect(ledger.allSatisfy { $0["kind"] as String == "integer" })
        let broken = try database.read { database in
            try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
        }
        #expect(broken.isEmpty)
        let firmware = try database.read { database in
            try String.fetchOne(database, sql: "SELECT firmware FROM consoles")
        }
        #expect(firmware == "ps5")
        let created = try database.read { database in
            try Int64.fetchOne(database, sql: "SELECT created_at FROM profiles")
        }
        #expect(created == 1_790_841_600_123)
        let captures = try CloudCaptureRepository(database: database).pending()
        #expect(captures.map(\.upload.galleryID) == ["psn2", "psn1"])
        #expect(captures[1].account == AccountID(bytes: Self.account))
        #expect(captures[1].upload.created == Date(timeIntervalSince1970: 1_792_319_468))
        #expect(captures[0].upload.created == nil)
        #expect(captures[0].upload.video)
        #expect(captures[0].attempts == 2)
    }
}
