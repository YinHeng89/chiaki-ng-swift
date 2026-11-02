import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct ConsoleFirmwareMigrationTests {
    func databaseAtVersionTwelve() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try MigrationRunner.apply(Array(MigrationRunner.bundled().prefix(12)), to: queue)
        try queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO profiles(id, display_name, auth_method, psn_account_id, psn_online_id)
                VALUES ('profile-1', 'Player', 'npsso', ?, 'player_one');
                INSERT INTO consoles(id, hardware_id, name, generation, last_address, connect_at_launch)
                VALUES ('console-ps4', 'a1b2c3d4e5f6', 'Bedroom PS4', 'ps4', '192.0.2.4', 1);
                INSERT INTO consoles(id, hardware_id, name, generation, last_address)
                VALUES ('console-ps5', '0a0b0c0d0e0f', 'Living room', 'ps5', NULL);
                INSERT INTO consoles(id, hardware_id, name, generation, last_address)
                VALUES ('console-unreached', NULL, 'Spare', 'ps4', 'spare.local');
                INSERT INTO registrations(id, profile_id, console_id, encrypted_credentials, key_version,
                    remote_device_id)
                VALUES ('pairing-ps4', 'profile-1', 'console-ps4', X'01AABBCC', 1, NULL);
                INSERT INTO registrations(id, profile_id, console_id, encrypted_credentials, key_version,
                    remote_device_id)
                VALUES ('pairing-ps5', 'profile-1', 'console-ps5', X'01DDEEFF', 1, ?);
                """,
                arguments: [Data(repeating: 7, count: 8), Data(repeating: 9, count: 32)]
            )
        }
        return queue
    }

    @Test func everyStoredPS4BecomesFirmwareTenAndEveryNameCountsAsRenamed() throws {
        let queue = try databaseAtVersionTwelve()
        try MigrationRunner.apply(MigrationRunner.bundled(), to: queue)
        let rows = try queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT id, generation, firmware, name_source FROM consoles ORDER BY id"
            )
        }
        let facts = rows.map {
            [$0["id"], $0["generation"], $0["firmware"], $0["name_source"]] as [String?]
        }
        #expect(facts == [
            ["console-ps4", "ps4", "ps4_10", "renamed"],
            ["console-ps5", "ps5", "ps5", "renamed"],
            ["console-unreached", "ps4", "ps4_10", "renamed"]
        ])
    }

    @Test func consolesAndPairingsKeepEveryOtherColumn() throws {
        let queue = try databaseAtVersionTwelve()
        try MigrationRunner.apply(Array(MigrationRunner.bundled().prefix(17)), to: queue)
        let consoles = try queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT hardware_id, name, last_address, connect_at_launch FROM consoles ORDER BY id"
            )
        }
        #expect(consoles.map { $0["name"] as String } == ["Bedroom PS4", "Living room", "Spare"])
        #expect(consoles.map { $0["hardware_id"] as String? } == ["a1b2c3d4e5f6", "0a0b0c0d0e0f", nil])
        #expect(consoles.map { $0["last_address"] as String? } == ["192.0.2.4", nil, "spare.local"])
        #expect(consoles.map { $0["connect_at_launch"] as Int } == [1, 0, 0])
        let pairings = try queue.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT id, encrypted_credentials, remote_device_id FROM registrations ORDER BY id"
            )
        }
        #expect(pairings.map { $0["encrypted_credentials"] as Data } == [
            Data([1, 0xAA, 0xBB, 0xCC]), Data([1, 0xDD, 0xEE, 0xFF])
        ])
        #expect(pairings.map { $0["remote_device_id"] as Data? } == [nil, Data(repeating: 9, count: 32)])
        let foreignKeys = try queue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
        }
        #expect(foreignKeys.isEmpty)
    }

    @Test func theNewColumnsRefuseValuesTheModelsCannotRead() throws {
        let queue = try databaseAtVersionTwelve()
        try MigrationRunner.apply(MigrationRunner.bundled(), to: queue)
        for statement in [
            "UPDATE consoles SET firmware = 'ps3' WHERE id = 'console-ps4'",
            "UPDATE consoles SET firmware = 'ps5' WHERE id = 'console-ps4'",
            "UPDATE consoles SET firmware = 'ps4_8' WHERE id = 'console-ps5'",
            "UPDATE consoles SET name_source = 'guessed' WHERE id = 'console-ps4'"
        ] {
            #expect(throws: DatabaseError.self) {
                try queue.write { database in
                    try database.execute(sql: statement)
                }
            }
        }
        try queue.write { database in
            try database
                .execute(
                    sql: "UPDATE consoles SET firmware = 'ps4_8', name_source = 'discovered' WHERE id = 'console-ps4'"
                )
        }
    }
}
