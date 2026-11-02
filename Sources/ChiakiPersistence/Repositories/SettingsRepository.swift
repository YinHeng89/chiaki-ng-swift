import ChiakiModels
import Foundation
import GRDB

/// Typed settings stored as JSON documents in the `settings` table, one per `ChiakiModels/SettingKey`.
///
/// Dates inside a document are stored as whole milliseconds since 1970. A stored document that does not
/// decode or validate is reported as corrupt rather than silently replaced with the default.
public final class SettingsRepository: Sendable {
    /// Reads the JSON document stored under a setting key.
    static let select = "SELECT value_json FROM settings WHERE key = ?"

    /// Stores a setting's JSON document, replacing the previous one.
    static let upsert = """
    INSERT INTO settings(key, value_json) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json
    """

    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// Reads a setting.
    ///
    /// - Parameter key: The setting.
    /// - Returns: The stored value after validation, or the default when nothing is stored.
    /// - Throws: ``PersistenceError/corruptData`` when the stored document does not decode or validate, or a
    ///   database error.
    public func value<Value>(_ key: SettingKey<Value>) throws(PersistenceError) -> Value {
        let json = try database.read { database in
            try String.fetchOne(database, sql: Self.select, arguments: [key.name])
        }
        guard let json else {
            return key.defaultValue
        }
        do {
            return try key.validate(Self.decoder.decode(Value.self, from: Data(json.utf8)))
        } catch {
            throw .corruptData
        }
    }

    /// Validates and stores a setting.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - key: The setting.
    /// - Throws: ``PersistenceError/invalidInput`` when the value does not validate, or a database error.
    public func save<Value>(_ value: Value, for key: SettingKey<Value>) throws(PersistenceError) {
        let json: String
        do {
            json = try String(bytes: Self.encoder.encode(key.validate(value)), encoding: .utf8) ?? ""
        } catch {
            throw .invalidInput
        }
        try database.write { database in
            try database.execute(sql: Self.upsert, arguments: [key.name, json])
        }
    }

    /// Reads, changes and stores a setting in one transaction.
    ///
    /// - Parameters:
    ///   - key: The setting.
    ///   - change: Returns the new value from the stored one.
    /// - Returns: The stored value after the change.
    /// - Throws: ``PersistenceError/corruptData`` or ``PersistenceError/invalidInput`` as ``value(_:)`` and
    ///   ``save(_:for:)`` do, or a database error.
    @discardableResult
    public func update<Value: Equatable>(
        _ key: SettingKey<Value>,
        _ change: (Value) -> Value
    ) throws(PersistenceError) -> Value {
        try database.write { database in
            let current: Value
            if let json = try String.fetchOne(database, sql: Self.select, arguments: [key.name]) {
                do {
                    current = try key.validate(Self.decoder.decode(Value.self, from: Data(json.utf8)))
                } catch {
                    throw PersistenceError.corruptData
                }
            } else {
                current = key.defaultValue
            }
            let updated = change(current)
            guard updated != current else {
                return current
            }
            let json: String
            do {
                json = try String(bytes: Self.encoder.encode(key.validate(updated)), encoding: .utf8) ?? ""
            } catch {
                throw PersistenceError.invalidInput
            }
            try database.execute(sql: Self.upsert, arguments: [key.name, json])
            return updated
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Timestamp.milliseconds(of: date))
        }
        return encoder
    }
}
