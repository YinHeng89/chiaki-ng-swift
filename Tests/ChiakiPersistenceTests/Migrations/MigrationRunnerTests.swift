import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct MigrationRunnerTests {
    func queue() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try DatabaseQueue(configuration: configuration)
    }

    func version(_ queue: DatabaseQueue) throws -> Int? {
        try queue.read { database in
            try Int.fetchOne(database, sql: "PRAGMA user_version")
        }
    }

    @Test func discoversEveryBundledStepInOrderWithoutTransactionControl() throws {
        let steps = try MigrationRunner.bundled()
        #expect(steps.map(\.version) == Array(1 ... 19))
        #expect(steps.first?.name == "001_initial")
        #expect(steps[17].name == "018_per_token_columns")
        #expect(steps.last?.name == "019_token_response_expiry")
        guard case .code = steps[17].body else {
            Issue.record("018 is not a code step")
            return
        }
        for step in steps.prefix(17) + steps.suffix(1) {
            guard case .sql(let sql) = step.body else {
                Issue.record("\(step.name) is not a SQL step")
                continue
            }
            let upper = sql.uppercased()
            #expect(!upper.contains("COMMIT"))
            #expect(!upper.contains("PRAGMA"))
            #expect(!upper.contains("SCHEMA_MIGRATIONS"))
        }
    }

    @Test func upgradesVersionOneWithoutLosingAccountsAndReopensIdempotently() throws {
        let queue = try queue()
        let steps = try MigrationRunner.bundled()
        try MigrationRunner.apply(Array(steps.prefix(1)), to: queue)
        try queue.write { database in
            try database.execute(
                sql: "INSERT INTO profiles(id, display_name, auth_method, psn_account_id) "
                    + "VALUES ('test', 'Kept', 'account_id', ?)",
                arguments: [Data(repeating: 1, count: 8)]
            )
        }
        try MigrationRunner.apply(steps, to: queue)
        try MigrationRunner.apply(steps, to: queue)
        let name = try queue.read { database in
            try String.fetchOne(database, sql: "SELECT display_name FROM profiles")
        }
        let ledger = try queue.read { database in
            try Int.fetchAll(database, sql: "SELECT version FROM schema_migrations")
        }
        #expect(name == "Kept")
        #expect(try version(queue) == 19)
        #expect(ledger == Array(1 ... 19))
    }

    @Test func aFailingStepRollsBackItsSchemaChangeAndVersion() throws {
        let queue = try queue()
        let steps = try MigrationRunner.bundled()
        try MigrationRunner.apply(Array(steps.prefix(1)), to: queue)
        let broken = Migration(
            version: 2, name: "002_broken",
            body: .sql("CREATE TABLE must_roll_back(value TEXT); INSERT INTO missing_table VALUES (1);")
        )
        #expect(throws: PersistenceError.database(code: ResultCode.SQLITE_ERROR.rawValue)) {
            try MigrationRunner.apply([steps[0], broken], to: queue)
        }
        let leftover = try queue.read { database in
            try String.fetchOne(database, sql: "SELECT name FROM sqlite_master WHERE name = 'must_roll_back'")
        }
        #expect(try version(queue) == 1)
        #expect(leftover == nil)
        try MigrationRunner.apply(steps, to: queue)
    }

    @Test func refusesANewerDatabaseAndAnInconsistentLedgerWithoutResettingThem() throws {
        let queue = try queue()
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE keep_me(value TEXT); PRAGMA user_version = 99")
        }
        let steps = try MigrationRunner.bundled()
        #expect(throws: PersistenceError.unsupportedVersion(found: 99, supported: 19)) {
            try MigrationRunner.apply(steps, to: queue)
        }
        let kept = try queue.read { database in
            try String.fetchOne(database, sql: "SELECT name FROM sqlite_master WHERE name = 'keep_me'")
        }
        #expect(kept == "keep_me")
        try queue.write { database in
            try database.execute(sql: "PRAGMA user_version = 0")
        }
        try MigrationRunner.apply(steps, to: queue)
        try queue.write { database in
            try database.execute(sql: "DELETE FROM schema_migrations WHERE version = 1")
        }
        #expect(throws: PersistenceError.corruptData) {
            try MigrationRunner.apply(steps, to: queue)
        }
    }

    @Test func aCodeMigrationRunsInItsOwnTransactionAndLedgerEntry() throws {
        let queue = try queue()
        let steps = try MigrationRunner.bundled()
        let code = Migration(version: 20, name: "020_code", body: .code { database, _ in
            try database.execute(sql: "UPDATE profiles SET display_name = upper(display_name)")
        })
        try MigrationRunner.apply(steps, to: queue)
        try queue.write { database in
            try database.execute(
                sql: "INSERT INTO profiles(id, display_name, auth_method, psn_account_id) "
                    + "VALUES ('p', 'quiet', 'account_id', ?)",
                arguments: [Data(repeating: 2, count: 8)]
            )
        }
        try MigrationRunner.apply(steps + [code], to: queue)
        let name = try queue.read { database in
            try String.fetchOne(database, sql: "SELECT display_name FROM profiles")
        }
        let recorded = try queue.read { database in
            try Int.fetchOne(database, sql: "SELECT max(version) FROM schema_migrations")
        }
        #expect(name == "QUIET")
        #expect(recorded == 20)
        #expect(try version(queue) == 20)
    }

    @Test func refusesGapsAndRepeatsInTheStepNumbers() throws {
        let queue = try queue()
        let first = Migration(version: 1, name: "001", body: .sql("CREATE TABLE a(value TEXT)"))
        let third = Migration(version: 3, name: "003", body: .sql("CREATE TABLE c(value TEXT)"))
        #expect(throws: PersistenceError.invalidMigrations) {
            try MigrationRunner.apply([first, third], to: queue)
        }
        #expect(throws: PersistenceError.invalidMigrations) {
            try MigrationRunner.apply([first, first], to: queue)
        }
    }

    @Test func upgradesVersionThreeWithoutTouchingTheSealedNPSSO() throws {
        let queue = try queue()
        let steps = try MigrationRunner.bundled()
        try MigrationRunner.apply(Array(steps.prefix(3)), to: queue)
        let envelope = Data([1, 2, 3, 4])
        try queue.write { database in
            try database.execute(
                sql: "INSERT INTO profiles(id, display_name, auth_method, psn_account_id) "
                    + "VALUES ('existing', 'Kept', 'npsso', ?)",
                arguments: [Data(repeating: 1, count: 8)]
            )
            try database.execute(
                sql: "INSERT INTO profile_npsso VALUES ('existing', ?, 1, 100, 100, NULL, 'unknown')",
                arguments: [envelope]
            )
        }
        try MigrationRunner.apply(steps, to: queue)
        let stored = try queue.read { database in
            try Data.fetchOne(database, sql: "SELECT encrypted_value FROM profile_npsso")
        }
        #expect(stored == envelope)
    }
}
