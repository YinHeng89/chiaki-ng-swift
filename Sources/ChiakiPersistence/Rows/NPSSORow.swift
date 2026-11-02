import ChiakiModels
import Foundation
import GRDB

/// One row of the `profile_npsso` table: a profile's sealed NPSSO and its dates.
struct NPSSORow: FetchableRecord, Sendable {
    /// Selects a profile's NPSSO row.
    static let selectForProfile = """
    SELECT encrypted_value, acquired_at, expires_at, expiry_source FROM profile_npsso WHERE profile_id = ?
    """

    /// Inserts a profile's NPSSO or replaces it.
    static let upsert = """
    INSERT INTO profile_npsso(profile_id, encrypted_value, key_version, acquired_at, validated_at, expires_at,
        expiry_source)
    VALUES (?, ?, 1, ?, ?, ?, ?)
    ON CONFLICT(profile_id) DO UPDATE SET
        encrypted_value = excluded.encrypted_value,
        acquired_at = excluded.acquired_at,
        validated_at = excluded.validated_at,
        expires_at = excluded.expires_at,
        expiry_source = excluded.expiry_source
    """

    /// The `encrypted_value` envelope.
    let envelope: Data

    /// The `acquired_at` column.
    let acquiredAt: Int64

    /// The `expires_at` column.
    let expiresAt: Int64?

    /// The `expiry_source` column.
    let expirySource: NPSSOExpirySource

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectForProfile``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type, and
    ///   ``PersistenceError/corruptData`` for an unknown expiry source.
    init(row: Row) throws {
        envelope = try row.decode(Data.self, forColumn: "encrypted_value")
        acquiredAt = try row.decode(Int64.self, forColumn: "acquired_at")
        expiresAt = try row.decode(Int64?.self, forColumn: "expires_at")
        guard let source = try NPSSOExpirySource(rawValue: row
            .decode(String.self, forColumn: "expiry_source")) else {
            throw PersistenceError.corruptData
        }
        expirySource = source
    }
}
