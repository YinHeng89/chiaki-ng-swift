import ChiakiModels
import Foundation
import GRDB

/// Per-account cached resources in `account_resource_cache`: profile details, avatar and PS Cloud status.
public final class AccountResourceRepository: Sendable {
    /// Reads one cached resource of a profile with its source and fetch and expiry times.
    static let select = """
    SELECT payload, source_url, fetched_at, expires_at FROM account_resource_cache
    WHERE profile_id = ? AND resource = ?
    """

    /// Stores a profile's cached resource, replacing an earlier copy of the same resource.
    static let upsert = """
    INSERT INTO account_resource_cache(profile_id, resource, payload, source_url, fetched_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(profile_id, resource) DO UPDATE SET
        payload = excluded.payload,
        source_url = excluded.source_url,
        fetched_at = excluded.fetched_at,
        expires_at = excluded.expires_at
    """

    /// The largest payload cached, in bytes.
    public static let maximumPayload = 2_000_000

    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// A cached resource of an account.
    ///
    /// - Parameters:
    ///   - resource: The resource.
    ///   - profile: The profile's id.
    /// - Returns: The cached resource, or `nil` when none is cached.
    /// - Throws: A database error.
    public func cached(_ resource: AccountResource, for profile: UUID) throws(PersistenceError)
        -> CachedAccountResource? {
        let row = try database.read { database in
            try Row.fetchOne(database, sql: Self.select, arguments: [profile.uuidString, resource.rawValue])
        }
        guard let row else {
            return nil
        }
        return try AppDatabase.mapping {
            try CachedAccountResource(
                payload: row.decode(Data.self, forColumn: "payload"),
                sourceURL: row.decode(String?.self, forColumn: "source_url"),
                fetchedAt: Timestamp.date(milliseconds: row.decode(Int64.self, forColumn: "fetched_at")),
                expiresAt: Timestamp.date(milliseconds: row.decode(Int64.self, forColumn: "expires_at"))
            )
        }
    }

    /// Caches a resource of an account.
    ///
    /// - Parameters:
    ///   - resource: The resource.
    ///   - profile: The profile's id.
    ///   - payload: The bytes, at most ``maximumPayload``.
    ///   - sourceURL: Where they came from.
    ///   - now: When they were fetched.
    ///   - ttl: How long they stay fresh; positive.
    /// - Throws: ``PersistenceError/invalidInput`` for an empty or oversized payload or a non-positive lifetime,
    ///   or a database error; a profile deleted meanwhile is never recreated.
    public func cache(
        _ resource: AccountResource,
        for profile: UUID,
        payload: Data,
        sourceURL: String? = nil,
        now: Date,
        ttl: TimeInterval
    ) throws(PersistenceError) {
        guard !payload.isEmpty, payload.count <= Self.maximumPayload, ttl > 0 else {
            throw .invalidInput
        }
        try database.write { database in
            try database.execute(
                sql: Self.upsert,
                arguments: [
                    profile.uuidString, resource.rawValue, payload, sourceURL,
                    Timestamp.milliseconds(of: now),
                    Timestamp.milliseconds(of: now.addingTimeInterval(ttl))
                ]
            )
        }
    }
}
