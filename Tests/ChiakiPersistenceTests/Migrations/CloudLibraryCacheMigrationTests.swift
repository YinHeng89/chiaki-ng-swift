@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct CloudLibraryCacheMigrationTests {
    @Test func theDeadCacheTableGoesAndTheAccountStays() throws {
        let legacy = try LegacyDatabase(version: 15)
        try legacy.execute(
            "INSERT INTO profiles(id, display_name, auth_method, psn_account_id) VALUES ('p', 'Player', 'npsso', ?)",
            [Data(repeating: 4, count: 8)]
        )
        try legacy.execute(
            """
            INSERT INTO cloud_library_cache(profile_id, locale, schema_version, payload, fetched_at)
            VALUES ('p', 'en-GB', 1, X'7B7D', 1760000000.5)
            """
        )
        try legacy.migrate(to: 16)
        let tables = try legacy
            .rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cloud_library_cache'")
        #expect(tables.isEmpty)
        #expect(try legacy.rows("SELECT id FROM profiles").count == 1)
        #expect(try legacy.version() == 16)
    }
}
