import ChiakiModels
import Foundation
import GRDB

/// The profiles aggregate: the account list, deleting an account and merging duplicate profiles.
///
/// Deleting a profile cascades to its NPSSO, tokens, account context, cached resources and pairings.
public final class AccountRepository: Sendable {
    /// Returns a row when the profile has at least one console pairing.
    static let hasPairing = "SELECT 1 FROM registrations WHERE profile_id = ? LIMIT 1"

    /// Returns a row when the profile has a stored NPSSO.
    static let hasNPSSO = "SELECT 1 FROM profile_npsso WHERE profile_id = ?"

    /// Marks a kept profile as signed in, taking the merged profile's display name and online id.
    static let promote = """
    UPDATE profiles SET auth_method = 'npsso', display_name = ?, psn_online_id = ? WHERE id = ?
    """

    /// Copies a merged profile's cached resources to the kept profile, keeping any the kept profile already
    /// has.
    static let copyResources = """
    INSERT OR IGNORE INTO account_resource_cache(profile_id, resource, payload, source_url, fetched_at, expires_at)
    SELECT ?, resource, payload, source_url, fetched_at, expires_at FROM account_resource_cache WHERE profile_id = ?
    """

    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// Every account, oldest first, with its cached avatar and PS Plus membership.
    ///
    /// - Returns: The accounts; a row that breaks its schema is left out.
    /// - Throws: A database error.
    public func list() throws(PersistenceError) -> [AccountProfile] {
        try database.read { database in
            try ProfileRow.fetchAll(database, sql: ProfileRow.selectAll)
        }
        .compactMap(\.profile)
    }

    /// Deletes an account and everything stored for it.
    ///
    /// - Parameter id: The profile's id.
    /// - Throws: A database error.
    public func delete(_ id: UUID) throws(PersistenceError) {
        try database.write { database in
            try database.execute(sql: ProfileRow.delete, arguments: [id.uuidString])
        }
    }

    /// Merges later profiles of one account that hold no pairing and no NPSSO into the oldest one.
    ///
    /// The merged profile's tokens are re-sealed for the kept profile unless it holds newer ones, its cached
    /// resources fill gaps, and a signed-in merged profile marks the kept one as signed in.
    ///
    /// - Throws: The cipher's or database's errors; nothing is merged then.
    public func consolidateUnlinkedDuplicates() throws(PersistenceError) {
        let accounts = try list()
        try database.write { database in
            var canonical: [AccountID: AccountProfile] = [:]
            for account in accounts {
                guard let retained = canonical[account.accountID] else {
                    canonical[account.accountID] = account
                    continue
                }
                let id = account.id.uuidString
                guard try Row.fetchOne(database, sql: Self.hasPairing, arguments: [id]) == nil,
                      try Row.fetchOne(database, sql: Self.hasNPSSO, arguments: [id]) == nil
                else {
                    continue
                }
                try moveTokens(from: id, to: retained.id.uuidString, in: database)
                if account.method == .npsso {
                    try database.execute(
                        sql: Self.promote, arguments: [account.name, account.onlineID, retained.id.uuidString]
                    )
                }
                try database.execute(sql: Self.copyResources, arguments: [retained.id.uuidString, id])
                try database.execute(sql: ProfileRow.delete, arguments: [id])
            }
        }
    }

    private func moveTokens(from source: String, to target: String, in database: GRDB.Database) throws {
        for row in try TokenRow.fetchAll(database, sql: TokenRow.selectForProfile, arguments: [source]) {
            let access = try row.access.map { (envelope) throws(PersistenceError) in
                try reseal(envelope, kind: row.kind, part: .access, from: source, to: target)
            }
            let refresh = try row.refresh.map { (envelope) throws(PersistenceError) in
                try reseal(envelope, kind: row.kind, part: .refresh, from: source, to: target)
            }
            try database.execute(
                sql: TokenRow.upsertIfNewer,
                arguments: [
                    target, row.kind, access, refresh, row.accessExpiresAt, row.accessObtainedAt,
                    row.refreshObtainedAt, row.refreshExpiresAt, row.updatedAt
                ]
            )
        }
    }

    private func reseal(
        _ envelope: Data,
        kind: String,
        part: TokenRow.Part,
        from source: String,
        to target: String
    ) throws(PersistenceError) -> Data {
        let token = try database.cipher.open(
            envelope, context: TokenRow.context(profileID: source, kind: kind, part: part)
        )
        return try database.cipher.seal(
            token, context: TokenRow.context(profileID: target, kind: kind, part: part),
            allowKeyCreation: false
        )
    }
}
