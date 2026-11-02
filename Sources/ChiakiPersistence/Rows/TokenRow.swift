import ChiakiModels
import Foundation
import GRDB

/// One row of the `profile_tokens` table: the access and refresh token of one kind, each in its own envelope.
struct TokenRow: FetchableRecord, Sendable {
    /// Which token of a row an envelope holds.
    enum Part: String {
        /// The access token.
        case access

        /// The refresh token.
        case refresh
    }

    /// The `credential_kind` of the PlayStation Store tokens.
    static let storeKind = "mobile_sso"

    /// The `credential_kind` of the Remote Play tokens.
    static let remotePlayKind = "remote_play"

    /// Selects a profile's token rows.
    static let selectForProfile = """
    SELECT profile_id, credential_kind, encrypted_access, encrypted_refresh, key_version, access_expires_at,
           access_obtained_at, refresh_obtained_at, refresh_expires_at, updated_at
    FROM profile_tokens WHERE profile_id = ?
    """

    /// Inserts a token row or replaces the one of the same kind.
    static let upsert = """
    INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_access, encrypted_refresh, key_version,
        access_expires_at, access_obtained_at, refresh_obtained_at, refresh_expires_at, updated_at)
    VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
    ON CONFLICT(profile_id, credential_kind) DO UPDATE SET
        encrypted_access = excluded.encrypted_access,
        encrypted_refresh = excluded.encrypted_refresh,
        key_version = excluded.key_version,
        access_expires_at = excluded.access_expires_at,
        access_obtained_at = excluded.access_obtained_at,
        refresh_obtained_at = excluded.refresh_obtained_at,
        refresh_expires_at = excluded.refresh_expires_at,
        updated_at = excluded.updated_at
    """

    /// Inserts a token row moved from another profile unless the target already holds a newer one.
    static let upsertIfNewer = """
    INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_access, encrypted_refresh, key_version,
        access_expires_at, access_obtained_at, refresh_obtained_at, refresh_expires_at, updated_at)
    VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
    ON CONFLICT(profile_id, credential_kind) DO UPDATE SET
        encrypted_access = excluded.encrypted_access,
        encrypted_refresh = excluded.encrypted_refresh,
        key_version = excluded.key_version,
        access_expires_at = excluded.access_expires_at,
        access_obtained_at = excluded.access_obtained_at,
        refresh_obtained_at = excluded.refresh_obtained_at,
        refresh_expires_at = excluded.refresh_expires_at,
        updated_at = excluded.updated_at
    WHERE excluded.updated_at >= profile_tokens.updated_at
    """

    /// Deletes a profile's tokens of one kind.
    static let delete = "DELETE FROM profile_tokens WHERE profile_id = ? AND credential_kind = ?"

    /// The `profile_id` column.
    let profileID: String

    /// The `credential_kind` column.
    let kind: String

    /// The `encrypted_access` envelope.
    let access: Data?

    /// The `encrypted_refresh` envelope.
    let refresh: Data?

    /// The `access_expires_at` column.
    let accessExpiresAt: Int64?

    /// The `access_obtained_at` column.
    let accessObtainedAt: Int64?

    /// The `refresh_obtained_at` column.
    let refreshObtainedAt: Int64?

    /// The `refresh_expires_at` column.
    let refreshExpiresAt: Int64?

    /// The `updated_at` column.
    let updatedAt: Int64

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectForProfile``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        profileID = try row.decode(String.self, forColumn: "profile_id")
        kind = try row.decode(String.self, forColumn: "credential_kind")
        access = try row.decode(Data?.self, forColumn: "encrypted_access")
        refresh = try row.decode(Data?.self, forColumn: "encrypted_refresh")
        accessExpiresAt = try row.decode(Int64?.self, forColumn: "access_expires_at")
        accessObtainedAt = try row.decode(Int64?.self, forColumn: "access_obtained_at")
        refreshObtainedAt = try row.decode(Int64?.self, forColumn: "refresh_obtained_at")
        refreshExpiresAt = try row.decode(Int64?.self, forColumn: "refresh_expires_at")
        updatedAt = try row.decode(Int64.self, forColumn: "updated_at")
    }

    /// The context string a token envelope is bound to.
    ///
    /// - Parameters:
    ///   - profileID: The profile's row id.
    ///   - kind: The `credential_kind`.
    ///   - part: Which token of the row.
    /// - Returns: The authenticated context.
    static func context(profileID: String, kind: String, part: Part) -> String {
        "account:\(profileID):\(kind):\(part.rawValue):v2"
    }

    /// The row kind and part a token is stored under.
    ///
    /// - Parameter token: The token kind.
    /// - Returns: The `credential_kind` and the part.
    static func place(of token: CredentialTokenKind) -> (kind: String, part: Part) {
        switch token {
        case .storeAccess:
            (storeKind, .access)
        case .storeRefresh:
            (storeKind, .refresh)
        case .remotePlayAccess:
            (remotePlayKind, .access)
        case .remotePlayRefresh:
            (remotePlayKind, .refresh)
        }
    }

    /// The token kind stored under a row kind and part.
    ///
    /// - Parameters:
    ///   - kind: The `credential_kind`.
    ///   - part: The part.
    /// - Returns: The token kind, or `nil` for an unknown row kind.
    static func token(kind: String, part: Part) -> CredentialTokenKind? {
        switch (kind, part) {
        case (storeKind, .access):
            .storeAccess
        case (storeKind, .refresh):
            .storeRefresh
        case (remotePlayKind, .access):
            .remotePlayAccess
        case (remotePlayKind, .refresh):
            .remotePlayRefresh
        default:
            nil
        }
    }
}
