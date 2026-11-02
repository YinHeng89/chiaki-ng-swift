/// Why a persistence operation failed, keeping the underlying cause where there is one.
public enum PersistenceError: Error, Hashable, Sendable {
    /// SQLite refused a statement; the associated value is its primary result code.
    case database(code: Int32)

    /// The values given were not valid for the operation.
    case invalidInput

    /// Stored data could not be read back: a row broke its schema, or an envelope failed to decrypt.
    case corruptData

    /// No encryption key exists yet and the operation may not create one.
    case missingKey

    /// The Keychain refused the key; the associated value is its status code when it gave one.
    case keyUnavailable(status: Int32?)

    /// The database was migrated by a newer app; it is at `found` and this app knows up to `supported`.
    case unsupportedVersion(found: Int, supported: Int)

    /// The bundled migrations are not numbered one to N without gaps or repeats.
    case invalidMigrations

    /// The database location could not be created or protected.
    case location

    /// A test harness asked for the live Keychain.
    case refusedLiveData
}
