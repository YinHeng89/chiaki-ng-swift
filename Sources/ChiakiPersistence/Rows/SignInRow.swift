import Foundation
import GRDB

/// One signed-in profile joined with its `profile_npsso` row and `account_context`, decoded by column name.
struct SignInRow: FetchableRecord, Sendable {
    /// Selects every profile signed in with an NPSSO, oldest first.
    static let selectSaved = """
    SELECT p.id, p.psn_account_id, COALESCE(p.psn_online_id, p.display_name) AS online_id,
           n.encrypted_value, n.acquired_at, n.expires_at, n.expiry_source,
           c.country, c.language, c.legal_country, c.locale, c.age, c.is_child, c.issued_at
    FROM profiles p
    JOIN profile_npsso n ON n.profile_id = p.id
    LEFT JOIN account_context c ON c.profile_id = p.id
    WHERE p.auth_method = 'npsso'
    ORDER BY p.created_at, p.id
    """

    /// The `profiles.id` column.
    let profileID: String

    /// The `profiles.psn_account_id` column.
    let accountID: Data

    /// The online id, or the display name when none is stored.
    let onlineID: String

    /// The `profile_npsso.encrypted_value` envelope.
    let npsso: Data

    /// The `profile_npsso.acquired_at` column.
    let acquiredAt: Int64

    /// The `profile_npsso.expires_at` column.
    let expiresAt: Int64?

    /// The `profile_npsso.expiry_source` column.
    let expirySource: String

    /// The `account_context` columns.
    let context: AccountContextRow

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectSaved``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        profileID = try row.decode(String.self, forColumn: "id")
        accountID = try row.decode(Data.self, forColumn: "psn_account_id")
        onlineID = try row.decode(String.self, forColumn: "online_id")
        npsso = try row.decode(Data.self, forColumn: "encrypted_value")
        acquiredAt = try row.decode(Int64.self, forColumn: "acquired_at")
        expiresAt = try row.decode(Int64?.self, forColumn: "expires_at")
        expirySource = try row.decode(String.self, forColumn: "expiry_source")
        context = try AccountContextRow(joined: row)
    }

    /// The context string an NPSSO envelope is bound to.
    ///
    /// - Parameter profileID: The profile's row id.
    /// - Returns: The authenticated context.
    static func npssoContext(profileID: String) -> String {
        "account:\(profileID):npsso:v1"
    }
}
