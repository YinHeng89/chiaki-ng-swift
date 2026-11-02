import ChiakiModels
import Foundation
import GRDB
import Security

/// The installation's cloud device id, created once and kept in the `settings` table.
///
/// The id is sixteen fixed hex digits followed by 32 random ones, as PlayStation's cloud service expects.
public final class CloudInstallationRepository: Sendable {
    /// The `settings` key the device id is stored under.
    static let key = "installation.cloudDUID.v1"

    /// The sixteen fixed hex digits every cloud device id starts with.
    static let prefix = "0000000700410080"

    /// Reads the stored device id document.
    static let select = "SELECT value_json FROM settings WHERE key = ?"

    /// Stores a newly created device id; it fails rather than replacing one that already exists.
    static let insert = "INSERT INTO settings(key, value_json) VALUES (?, ?)"

    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// The installation's cloud device id, created and stored on first use.
    ///
    /// - Returns: The 48-digit lowercase hex id.
    /// - Throws: ``PersistenceError/corruptData`` when the stored id is malformed, which never rotates it, or a
    ///   database error.
    public func deviceID() throws(PersistenceError) -> String {
        try database.write { database in
            try Self.deviceID(in: database)
        }
    }

    /// The installation's cloud device id inside an open write transaction.
    ///
    /// - Parameter database: The database, in a write transaction.
    /// - Returns: The 48-digit lowercase hex id.
    /// - Throws: ``PersistenceError/corruptData`` for a malformed stored id, or a database error.
    static func deviceID(in database: GRDB.Database) throws -> String {
        if let json = try String.fetchOne(database, sql: select, arguments: [key]) {
            guard let value = try? JSONDecoder().decode(String.self, from: Data(json.utf8)),
                  isValid(value) else {
                throw PersistenceError.corruptData
            }
            return value
        }
        var random = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw PersistenceError.corruptData
        }
        let value = prefix + Hex.encode(random)
        let json = try String(bytes: JSONEncoder().encode(value), encoding: .utf8) ?? ""
        try database.execute(sql: insert, arguments: [key, json])
        return value
    }

    private static func isValid(_ value: String) -> Bool {
        value.utf8.count == 48 && value.hasPrefix(prefix) && value.utf8.allSatisfy {
            Hex.isDigit($0) && !(UInt8(ascii: "A") ... UInt8(ascii: "F")).contains($0)
        }
    }
}
