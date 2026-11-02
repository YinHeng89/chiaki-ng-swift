import Foundation

/// A per-account resource the app caches.
public enum AccountResource: String, Sendable {
    /// The profile details: online id, avatar address and PS Plus membership.
    case profile

    /// The avatar image.
    case avatar

    /// The PS Cloud status snapshot.
    case pscloud
}

/// A cached per-account resource with its freshness.
public struct CachedAccountResource: Sendable {
    /// The cached bytes.
    public let payload: Data

    /// Where the bytes were fetched from, if recorded.
    public let sourceURL: String?

    /// When the bytes were fetched.
    public let fetchedAt: Date

    /// When the bytes go stale.
    public let expiresAt: Date

    /// Describes a cached resource.
    ///
    /// - Parameters:
    ///   - payload: The cached bytes.
    ///   - sourceURL: Where they came from.
    ///   - fetchedAt: When they were fetched.
    ///   - expiresAt: When they go stale.
    public init(payload: Data, sourceURL: String?, fetchedAt: Date, expiresAt: Date) {
        self.payload = payload
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
    }
}
