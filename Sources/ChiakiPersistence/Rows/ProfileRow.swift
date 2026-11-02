import ChiakiModels
import Foundation
import GRDB

/// One row of the `profiles` table with its cached avatar and profile details, decoded by column name.
struct ProfileRow: FetchableRecord, Sendable {
    /// Selects every profile, oldest first, with its cached avatar and profile details.
    static let selectAll = """
    SELECT p.id, p.display_name, p.auth_method, p.psn_account_id, p.psn_online_id,
           avatar.payload AS avatar, details.payload AS details,
           details.fetched_at AS details_fetched_at, details.expires_at AS details_expires_at
    FROM profiles p
    LEFT JOIN account_resource_cache avatar ON avatar.profile_id = p.id AND avatar.resource = 'avatar'
    LEFT JOIN account_resource_cache details ON details.profile_id = p.id AND details.resource = 'profile'
    ORDER BY p.created_at, p.id
    """

    /// Selects the oldest profile holding an account id.
    static let selectByAccount = """
    SELECT id FROM profiles WHERE psn_account_id = ? ORDER BY created_at, id LIMIT 1
    """

    /// Selects every profile id holding an account id.
    static let selectAllByAccount = "SELECT id FROM profiles WHERE psn_account_id = ?"

    /// Inserts a profile.
    static let insert = """
    INSERT INTO profiles(id, display_name, auth_method, psn_account_id, psn_online_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    /// Marks a profile as signed in under an online id.
    static let updateSignedIn = """
    UPDATE profiles SET display_name = ?, psn_online_id = ?, auth_method = 'npsso', updated_at = ? WHERE id = ?
    """

    /// Selects every profile without a signed-in NPSSO, oldest first.
    static let selectHomeUsers = """
    SELECT psn_account_id, display_name FROM profiles p
    WHERE auth_method = 'account_id' OR NOT EXISTS (SELECT 1 FROM profile_npsso n WHERE n.profile_id = p.id)
    ORDER BY created_at, id
    """

    /// Deletes a profile; everything stored for it cascades.
    static let delete = "DELETE FROM profiles WHERE id = ?"

    /// Deletes every profile holding an account id.
    static let deleteByAccount = "DELETE FROM profiles WHERE psn_account_id = ?"

    /// The `id` column.
    let id: String

    /// The `display_name` column.
    let name: String

    /// The `auth_method` column.
    let method: String

    /// The `psn_account_id` column.
    let accountID: Data

    /// The `psn_online_id` column.
    let onlineID: String?

    /// The cached avatar image.
    let avatar: Data?

    /// The cached profile details document.
    let details: Data?

    /// When the profile details were fetched.
    let detailsFetchedAt: Int64?

    /// When the profile details go stale.
    let detailsExpiresAt: Int64?

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectAll``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        id = try row.decode(String.self, forColumn: "id")
        name = try row.decode(String.self, forColumn: "display_name")
        method = try row.decode(String.self, forColumn: "auth_method")
        accountID = try row.decode(Data.self, forColumn: "psn_account_id")
        onlineID = try row.decode(String?.self, forColumn: "psn_online_id")
        avatar = try row.decode(Data?.self, forColumn: "avatar")
        details = try row.decode(Data?.self, forColumn: "details")
        detailsFetchedAt = try row.decode(Int64?.self, forColumn: "details_fetched_at")
        detailsExpiresAt = try row.decode(Int64?.self, forColumn: "details_expires_at")
    }

    /// The row as an account, or `nil` when a column breaks its schema.
    var profile: AccountProfile? {
        guard let uuid = UUID(uuidString: id), let method = AccountProfile.Method(rawValue: method),
              let account = AccountID(bytes: accountID)
        else {
            return nil
        }
        var profile = AccountProfile(
            id: uuid,
            name: name,
            method: method,
            accountID: account,
            onlineID: onlineID
        )
        profile.avatarData = avatar
        if let details, let membership = try? JSONDecoder().decode(Membership.self, from: details),
           let detailsFetchedAt, let detailsExpiresAt {
            profile.isPlus = membership.isPlus
            profile.membershipCheckedAt = Timestamp.date(milliseconds: detailsFetchedAt)
            profile.membershipExpiresAt = Timestamp.date(milliseconds: detailsExpiresAt)
        }
        return profile
    }

    private struct Membership: Decodable {
        let isPlus: Bool?
    }
}
