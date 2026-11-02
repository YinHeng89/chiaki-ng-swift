import Foundation
import GRDB

/// The controls configuration document in the one-row `input_configuration` table.
///
/// The document's shape and rules belong to the caller; this repository stores version 1 documents and refuses
/// any other version.
public final class ControlsRepository: Sendable {
    /// Reads the stored controls document and its version.
    static let select = "SELECT version, payload FROM input_configuration WHERE id = 1"

    /// Stores the controls document as version 1, replacing the previous one.
    static let upsert = """
    INSERT INTO input_configuration(id, version, payload) VALUES (1, 1, ?)
    ON CONFLICT(id) DO UPDATE SET version = excluded.version, payload = excluded.payload
    """

    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// Reads the stored configuration.
    ///
    /// - Parameter type: The document type.
    /// - Returns: The document, or `nil` when none is stored.
    /// - Throws: ``PersistenceError/unsupportedVersion(found:supported:)`` for a document from a newer app,
    ///   ``PersistenceError/corruptData`` when it does not decode, or a database error.
    public func configuration<Value: Decodable>(_ type: Value.Type) throws(PersistenceError) -> Value? {
        let row = try database.read { database in
            try Row.fetchOne(database, sql: Self.select)
        }
        guard let row else {
            return nil
        }
        let stored = try AppDatabase.mapping {
            try (row.decode(Int64.self, forColumn: "version"), row.decode(String.self, forColumn: "payload"))
        }
        guard stored.0 == 1 else {
            throw .unsupportedVersion(found: Int(stored.0), supported: 1)
        }
        do {
            return try JSONDecoder().decode(type, from: Data(stored.1.utf8))
        } catch {
            throw .corruptData
        }
    }

    /// Stores the configuration as a version 1 document.
    ///
    /// - Parameter value: The document, already validated by the caller.
    /// - Throws: ``PersistenceError/invalidInput`` when it does not encode, or a database error.
    public func save<Value: Encodable>(_ value: Value) throws(PersistenceError) {
        let json: String
        do {
            json = try String(bytes: JSONEncoder().encode(value), encoding: .utf8) ?? ""
        } catch {
            throw .invalidInput
        }
        try database.write { database in
            try database.execute(sql: Self.upsert, arguments: [json])
        }
    }
}
