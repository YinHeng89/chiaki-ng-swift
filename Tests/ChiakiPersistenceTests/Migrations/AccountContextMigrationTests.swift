@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct AccountContextMigrationTests {
    let signedIn = "6F1C2B8E-0000-4000-8000-000000000001"
    let regionOnly = "6F1C2B8E-0000-4000-8000-000000000002"
    let deleted = "6F1C2B8E-0000-4000-8000-000000000003"

    func databaseAtFourteen() throws -> LegacyDatabase {
        let legacy = try LegacyDatabase(version: 14)
        for (index, id) in [signedIn, regionOnly].enumerated() {
            try legacy.execute(
                """
                INSERT INTO profiles(id, display_name, auth_method, psn_account_id, psn_online_id)
                VALUES (?, 'Player', 'npsso', ?, 'player')
                """,
                [id, Data(repeating: UInt8(index + 1), count: 8)]
            )
        }
        let settings = [
            ("accounts.region.v1.\(signedIn)", #"{"country":"GB","language":"en"}"#),
            (
                "accounts.context.v1.\(signedIn)",
                #"{"legalCountry":"GB","locale":"en-GB","age":0,"isChild":false,"issuedAtMs":1760000000123}"#
            ),
            ("accounts.region.v1.\(regionOnly)", #"{"country":"JP","language":"ja"}"#),
            ("accounts.region.v1.\(deleted)", #"{"country":"US","language":"en"}"#),
            ("accounts.context.v1.\(deleted)", #"{"age":30}"#),
            ("accounts.active.v1", "\"\(signedIn)\"")
        ]
        for (key, value) in settings {
            try legacy.execute("INSERT INTO settings(key, value_json) VALUES (?, ?)", [key, value])
        }
        return legacy
    }

    @Test func regionAndContextMoveIntoOneRowPerProfile() throws {
        let legacy = try databaseAtFourteen()
        try legacy.migrate(to: 15)
        let rows = try legacy.rows("SELECT * FROM account_context ORDER BY profile_id")
        #expect(rows.count == 2)
        let first = rows[0]
        #expect(first["profile_id"] as String == signedIn)
        #expect(first["country"] as String? == "GB")
        #expect(first["language"] as String? == "en")
        #expect(first["legal_country"] as String? == "GB")
        #expect(first["locale"] as String? == "en-GB")
        #expect(first["age"] as Int? == 0)
        #expect(first["is_child"] as Int? == 0)
        #expect(first["issued_at"] as Int64? == 1_760_000_000_123)
        let second = rows[1]
        #expect(second["country"] as String? == "JP")
        #expect(second["legal_country"] as String? == nil)
        #expect(second["age"] as Int? == nil)
    }

    @Test func theSettingsKeysAreRemovedEvenForDeletedProfiles() throws {
        let legacy = try databaseAtFourteen()
        try legacy.migrate(to: 15)
        let keys = try legacy.rows("SELECT key FROM settings ORDER BY key").map {
            $0["key"] as String
        }
        #expect(keys == ["accounts.active.v1"])
    }

    @Test func deletingAProfileTakesItsContext() throws {
        let legacy = try databaseAtFourteen()
        try legacy.migrate(to: 15)
        try legacy.execute("DELETE FROM profiles WHERE id = ?", [signedIn])
        #expect(try legacy.rows("SELECT profile_id FROM account_context").map {
            $0["profile_id"] as String
        } == [regionOnly])
    }
}
