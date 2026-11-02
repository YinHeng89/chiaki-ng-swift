import Foundation
import GRDB

/// Brings a database up to the newest schema, one transaction per step.
///
/// Each step runs in an immediate transaction together with its row in `schema_migrations` and the new
/// `PRAGMA user_version`, after a foreign key check. Foreign key enforcement is off while steps run, so a step
/// may rebuild a parent table without cascading deletes into its children; the check before each commit
/// still refuses a step that leaves a dangling reference. A failing step rolls back completely. A database at
/// a version newer than the app knows, or whose ledger disagrees with its version, is refused untouched. A
/// ledger written by an older app with ISO-8601 times is rewritten in milliseconds before the next step.
public enum MigrationRunner {
    /// Swift code migrations, registered by number beside the bundled SQL files.
    public static let codeMigrations: [Migration] = [
        Migration(version: 18, name: "018_per_token_columns", body: .code(PerTokenColumnsMigration.run))
    ]

    /// Creates the `schema_migrations` ledger, with times in milliseconds since 1970, when it does not exist
    /// yet.
    static let ledgerTable = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
    )
    """

    /// Reads the declared type of the ledger's `applied_at` column, which is `TEXT` in ledgers written by
    /// older apps.
    static let ledgerTimeType = "SELECT type FROM pragma_table_info('schema_migrations') WHERE name = 'applied_at'"

    /// Rebuilds an ISO-8601 ledger with its times converted to milliseconds since 1970.
    static let ledgerInMilliseconds = """
    CREATE TABLE schema_migrations_ms (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
    );
    INSERT INTO schema_migrations_ms(version, applied_at)
    SELECT version, COALESCE(CAST(round((julianday(applied_at) - 2440587.5) * 86400000) AS INTEGER),
                             CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
    FROM schema_migrations;
    DROP TABLE schema_migrations;
    ALTER TABLE schema_migrations_ms RENAME TO schema_migrations
    """

    /// Reads the database's `user_version`, the number of the last step applied.
    static let currentVersion = "PRAGMA user_version"

    /// Lists the step numbers the ledger records, in ascending order.
    static let recordedVersions = "SELECT version FROM schema_migrations ORDER BY version"

    /// Lists every dangling foreign key reference; a step may only commit when it returns no rows.
    static let foreignKeyCheck = "PRAGMA foreign_key_check"

    /// Records a step's number in the ledger.
    static let recordVersion = "INSERT INTO schema_migrations(version) VALUES (?)"

    /// Turns foreign key enforcement back on after a step.
    static let enforceForeignKeys = "PRAGMA foreign_keys = ON"

    /// Turns foreign key enforcement off so a step can rebuild a parent table without cascading deletes.
    static let suspendForeignKeys = "PRAGMA foreign_keys = OFF"

    /// Every migration the app ships: the bundled SQL files and the registered code migrations, in order.
    ///
    /// - Returns: The steps, numbered one to N.
    /// - Throws: ``PersistenceError/invalidMigrations`` when a file name does not start with its number or
    ///   the numbers are not one to N without gaps or repeats.
    public static func bundled() throws(PersistenceError) -> [Migration] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "sql", subdirectory: "Migrations") ?? []
        var steps = codeMigrations
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            guard let version = Int(name.prefix { $0.isASCII && $0.isNumber }),
                  let sql = try? String(contentsOf: url, encoding: .utf8)
            else {
                throw .invalidMigrations
            }
            steps.append(Migration(version: version, name: name, body: .sql(sql)))
        }
        return try ordered(steps)
    }

    /// Applies every step the database has not run yet. An empty list leaves the database untouched.
    ///
    /// - Parameters:
    ///   - migrations: The steps, numbered one to N.
    ///   - queue: The database to migrate.
    ///   - cipher: Handed to code migrations that re-encrypt secrets; an in-memory key by default.
    /// - Throws: ``PersistenceError/invalidMigrations`` for a badly numbered list,
    ///   ``PersistenceError/unsupportedVersion(found:supported:)`` for a database from a newer app,
    ///   ``PersistenceError/corruptData`` for an inconsistent ledger or a broken foreign key, and
    ///   ``PersistenceError/database(code:)`` when a step's SQL fails.
    package static func apply(
        _ migrations: [Migration],
        to queue: DatabaseQueue,
        cipher: CredentialCipher = CredentialCipher(keys: KeychainKeyStore(source: .memory()))
    ) throws(PersistenceError) {
        guard !migrations.isEmpty else {
            return
        }
        let steps = try ordered(migrations)
        var finished = false
        while !finished {
            finished = try AppDatabase.mapping {
                try queue.writeWithoutTransaction { database in
                    try database.execute(sql: suspendForeignKeys)
                    defer {
                        try? database.execute(sql: enforceForeignKeys)
                    }
                    var done = false
                    try database.inTransaction(.immediate) {
                        done = try step(steps, in: database, cipher: cipher)
                        return .commit
                    }
                    return done
                }
            }
        }
    }

    private static func ordered(_ migrations: [Migration]) throws(PersistenceError) -> [Migration] {
        let sorted = migrations.sorted {
            $0.version < $1.version
        }
        guard sorted.map(\.version) == Array(stride(from: 1, through: sorted.count, by: 1)) else {
            throw .invalidMigrations
        }
        return sorted
    }

    private static func step(
        _ steps: [Migration],
        in database: GRDB.Database,
        cipher: CredentialCipher
    ) throws -> Bool {
        try database.execute(sql: ledgerTable)
        if try String.fetchOne(database, sql: ledgerTimeType)?.uppercased() == "TEXT" {
            try database.execute(sql: ledgerInMilliseconds)
        }
        guard let version = try Int.fetchOne(database, sql: currentVersion), version >= 0 else {
            throw PersistenceError.corruptData
        }
        guard version <= steps.count else {
            throw PersistenceError.unsupportedVersion(found: version, supported: steps.count)
        }
        guard try Int.fetchAll(database, sql: recordedVersions) == Array(stride(
            from: 1,
            through: version,
            by: 1
        ))
        else {
            throw PersistenceError.corruptData
        }
        guard version < steps.count else {
            return true
        }
        let migration = steps[version]
        switch migration.body {
        case .sql(let sql):
            try database.execute(sql: sql)
        case .code(let run):
            try run(database, cipher)
        }
        guard try Row.fetchAll(database, sql: foreignKeyCheck).isEmpty else {
            throw PersistenceError.corruptData
        }
        try database.execute(sql: recordVersion, arguments: [migration.version])
        try database.execute(sql: "PRAGMA user_version = \(migration.version)")
        return false
    }
}

/// One numbered, one-way schema step.
///
/// Most steps are SQL files bundled as `Migrations/NNN_name.sql`. A step that needs Swift, such as one
/// that re-encrypts data with the Keychain key, is a code migration registered under its number in
/// ``MigrationRunner/codeMigrations``. Both kinds run in the same transaction as their ledger entry.
public struct Migration: Sendable {
    /// What a step runs.
    public enum Body: Sendable {
        /// SQL statements, without transaction control, pragmas or ledger writes.
        case sql(String)

        /// Swift code given the open database inside the step's transaction, and the cipher for steps that
        /// re-encrypt stored secrets.
        case code(@Sendable (GRDB.Database, CredentialCipher) throws -> Void)
    }

    /// The step's number; steps run in order from one.
    public let version: Int

    /// The step's name, such as `"013_console_firmware_and_name_source"`.
    public let name: String

    /// What the step runs.
    public let body: Body

    /// Describes a step.
    ///
    /// - Parameters:
    ///   - version: The step's number.
    ///   - name: The step's name.
    ///   - body: What the step runs.
    public init(version: Int, name: String, body: Body) {
        self.version = version
        self.name = name
        self.body = body
    }
}
