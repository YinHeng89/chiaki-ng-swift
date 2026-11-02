import ChiakiModels
import Foundation
import GRDB

/// The app's one SQLite database: a single GRDB queue, migrated on open, with the cipher for its secrets.
///
/// Every repository works through the same ``AppDatabase``, so writes are serialised by one queue. Opening
/// runs every bundled migration; a database that cannot be migrated is not returned.
public final class AppDatabase: Sendable {
    /// The serial queue every read and write goes through.
    package let queue: DatabaseQueue

    /// Seals and opens the secrets stored in this database.
    public let cipher: CredentialCipher

    /// Holds the key ``cipher`` uses.
    public let keys: KeychainKeyStore

    /// Opens a database file, or an in-memory database, and migrates it.
    ///
    /// - Parameters:
    ///   - path: The file path, or `nil` for a private in-memory database.
    ///   - keys: Where the encryption key is held.
    ///   - migrations: The steps to apply; the bundled steps by default.
    /// - Throws: ``PersistenceError`` when the file cannot be opened or migrated.
    public init(
        path: String?,
        keys: KeychainKeyStore,
        migrations: [Migration]? = nil
    ) throws(PersistenceError) {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.publicStatementArguments = false
        configuration.foreignKeysEnabled = true
        let queue = try Self.mapping {
            if let path {
                try DatabaseQueue(path: path, configuration: configuration)
            } else {
                try DatabaseQueue(configuration: configuration)
            }
        }
        let steps = if let migrations {
            migrations
        } else {
            try MigrationRunner.bundled()
        }
        let cipher = CredentialCipher(keys: keys)
        try MigrationRunner.apply(steps, to: queue, cipher: cipher)
        self.queue = queue
        self.keys = keys
        self.cipher = cipher
    }

    /// Opens the database at a user data location, creating its folder with owner-only permissions.
    ///
    /// - Parameter data: The location; its `ChiakiModels/UserData/keys` choose the Keychain or memory.
    /// - Returns: The open, migrated database.
    /// - Throws: ``PersistenceError/location`` when the folder or file cannot be created or protected,
    ///   ``PersistenceError/refusedLiveData`` when a harness asks for the Keychain, or a migration error.
    public static func open(_ data: UserData) throws(PersistenceError) -> AppDatabase {
        let files = FileManager.default
        do {
            try files.createDirectory(
                at: data.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw .location
        }
        let source = switch data.keys {
        case .keychain:
            try KeySource.keychain()
        case .memory:
            KeySource.memory(scope: data.support.path)
        }
        let database = try AppDatabase(path: data.database.path, keys: KeychainKeyStore(source: source))
        do {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: data.database.path)
        } catch {
            throw .location
        }
        return database
    }

    /// Reads inside a deferred transaction.
    ///
    /// - Parameter body: The read.
    /// - Returns: What `body` returns.
    /// - Throws: ``PersistenceError`` for a SQLite failure or the persistence error `body` throws.
    package func read<Result>(_ body: (GRDB.Database) throws -> Result) throws(PersistenceError) -> Result {
        try Self.mapping {
            try queue.read(body)
        }
    }

    /// Writes inside an immediate transaction that rolls back when `body` throws.
    ///
    /// - Parameter body: The write.
    /// - Returns: What `body` returns.
    /// - Throws: ``PersistenceError`` for a SQLite failure or the persistence error `body` throws.
    package func write<Result>(_ body: (GRDB.Database) throws -> Result) throws(PersistenceError) -> Result {
        try Self.mapping {
            try queue.writeWithoutTransaction { database in
                var result: Result?
                try database.inTransaction(.immediate) {
                    result = try body(database)
                    return .commit
                }
                guard let result else {
                    throw PersistenceError.corruptData
                }
                return result
            }
        }
    }

    /// Runs GRDB work and maps its failures to ``PersistenceError``, keeping the SQLite result code.
    ///
    /// - Parameter body: The work.
    /// - Returns: What `body` returns.
    /// - Throws: The ``PersistenceError`` `body` throws, ``PersistenceError/database(code:)`` for a SQLite
    ///   error, or ``PersistenceError/corruptData`` for anything else.
    package static func mapping<Result>(_ body: () throws -> Result) throws(PersistenceError) -> Result {
        do {
            return try body()
        } catch let error as PersistenceError {
            throw error
        } catch let error as DatabaseError {
            throw .database(code: error.resultCode.primaryResultCode.rawValue)
        } catch {
            throw .corruptData
        }
    }
}
