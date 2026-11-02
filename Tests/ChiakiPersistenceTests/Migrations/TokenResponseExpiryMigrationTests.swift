@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct TokenResponseExpiryMigrationTests {
    func databaseAtEighteen() throws -> LegacyDatabase {
        let legacy = try LegacyDatabase(version: 18)
        let expiries: [Int64?] = [1_790_000_000_456, 1_790_000_000_457, nil]
        let sources = ["sony_response", "cookie", "unknown"]
        for (index, source) in sources.enumerated() {
            let profile = "p\(index)"
            try legacy.execute(
                """
                INSERT INTO profiles(id, display_name, auth_method, psn_account_id)
                VALUES (?, 'Player', 'npsso', ?)
                """,
                [profile, Data(repeating: UInt8(index + 1), count: 8)]
            )
            try legacy.execute(
                """
                INSERT INTO profile_npsso(profile_id, encrypted_value, key_version, acquired_at, validated_at,
                    expires_at, expiry_source)
                VALUES (?, ?, 1, 1760000000123, 1760000000124, ?, ?)
                """,
                [profile, Data([1, 2, UInt8(index)]), expiries[index], source]
            )
        }
        return legacy
    }

    @Test func aTokenResponseExpiryIsStoredUnderItsNewName() throws {
        let legacy = try databaseAtEighteen()
        try legacy.migrate(to: 19)
        let rows = try legacy.rows("SELECT * FROM profile_npsso ORDER BY profile_id")
        #expect(rows.map {
            $0["expiry_source"] as String
        } == ["token_response", "cookie", "unknown"])
        #expect(rows.map {
            $0["expires_at"] as Int64?
        } == [1_790_000_000_456, 1_790_000_000_457, nil])
        #expect(rows.map {
            $0["encrypted_value"] as Data
        } == [Data([1, 2, 0]), Data([1, 2, 1]), Data([1, 2, 2])])
        #expect(rows.allSatisfy {
            $0["acquired_at"] as Int64 == 1_760_000_000_123 && $0["validated_at"] as Int64 ==
                1_760_000_000_124
        })
    }

    @Test func theOldNameIsRefusedAfterTheUpgrade() throws {
        let legacy = try databaseAtEighteen()
        try legacy.migrate(to: 19)
        #expect(throws: DatabaseError.self) {
            try legacy
                .execute("UPDATE profile_npsso SET expiry_source = 'sony_response' WHERE profile_id = 'p1'")
        }
    }
}
