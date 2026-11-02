import Foundation

/// A cached PS Cloud status for one account and locale, with per-title verdicts and its own expiry.
public struct CloudStatusSnapshot: Codable, Equatable, Sendable {
    /// The snapshot format version. Stored snapshots of another version are ignored when read back.
    public var schemaVersion = 1
    /// The account and locale this snapshot covers.
    public let scope: CloudAccountScope
    /// The catalog results.
    public let catalog: CloudCatalogEvidence
    /// When the catalog was read.
    public let checkedAt: Date
    /// When the snapshot stops being fresh.
    public let expiresAt: Date
    /// Per-title streaming verdicts, keyed by product ID.
    public var games: [String: CloudGameAccess]
    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - scope: The account and locale.
    ///   - catalog: The catalog results.
    ///   - checkedAt: When the catalog was read.
    ///   - expiresAt: When the snapshot stops being fresh.
    ///   - games: Per-title verdicts keyed by product ID.
    public init(
        scope: CloudAccountScope, catalog: CloudCatalogEvidence, checkedAt: Date, expiresAt: Date,
        games: [String: CloudGameAccess] = [:]
    ) {
        self.scope = scope
        self.catalog = catalog
        self.checkedAt = checkedAt
        self.expiresAt = expiresAt
        self.games = games
    }
    /// The unexpired verdict for a title.
    ///
    /// - Parameters:
    ///   - productID: The title's product ID.
    ///   - now: The current time.
    /// - Returns: The verdict, or `nil` when none is recorded or it has expired.
    public func access(for productID: String, now: Date) -> CloudGameAccess.Verdict? {
        guard let result = games[productID], result.expiresAt > now else {
            return nil
        }
        return result.verdict
    }
}

/// Whether a title was found streamable, and how long that answer holds.
public struct CloudGameAccess: Codable, Equatable, Sendable {
    /// Whether a title can be streamed.
    public enum Verdict: String, Codable, Sendable {
        /// The title can be streamed, or it cannot.
        case streamable, notStreamable
    }
    /// The answer.
    public let verdict: Verdict
    /// When the answer was obtained.
    public let checkedAt: Date
    /// When the answer stops being trusted.
    public let expiresAt: Date
    /// Creates a streaming verdict.
    ///
    /// - Parameters:
    ///   - verdict: The answer.
    ///   - checkedAt: When it was obtained.
    ///   - expiresAt: When it stops being trusted.
    public init(verdict: Verdict, checkedAt: Date, expiresAt: Date) {
        self.verdict = verdict
        self.checkedAt = checkedAt
        self.expiresAt = expiresAt
    }
}

/// What an account can do with PS Cloud streaming, as read from its catalog.
public enum CloudAvailability: String, Codable, Equatable, Sendable {
    /// The catalog is available, a subscription is needed, sign-in is needed, the catalog is empty, or only a
    /// partial catalog could be read.
    case catalogAvailable, subscriptionRequired, signInRequired, empty, limitedCatalog
}

/// What a catalog fetch found: how many games, whether the account service answered completely, any warning,
/// and Plus membership.
public struct CloudCatalogEvidence: Codable, Equatable, Sendable {
    /// A problem the catalog fetch reported alongside its results.
    public enum Warning: String, Codable, Sendable {
        /// No warning, the session expired, or another problem limited the results.
        case none, sessionExpired, other
    }
    /// The number of games in the catalog.
    public let gameCount: Int
    /// Whether the catalog came complete from the account service rather than a fallback.
    public let nativeCatalog: Bool
    /// The warning reported with the catalog.
    public let warning: Warning
    /// Whether the account has PlayStation Plus, or `nil` when unknown.
    public let isPlus: Bool?
    /// Creates catalog evidence.
    ///
    /// - Parameters:
    ///   - gameCount: The number of games found.
    ///   - nativeCatalog: Whether the account service answered completely.
    ///   - warning: The warning reported with the catalog.
    ///   - isPlus: Whether the account has PlayStation Plus, if known.
    public init(gameCount: Int, nativeCatalog: Bool, warning: Warning = .none, isPlus: Bool?) {
        self.gameCount = gameCount
        self.nativeCatalog = nativeCatalog
        self.warning = warning
        self.isPlus = isPlus
    }

    /// The availability these results imply. An expired session needs sign-in, other warnings or a fallback
    /// catalog are limited, no games is empty, and a known lack of Plus needs a subscription.
    public var availability: CloudAvailability {
        if warning == .sessionExpired {
            return .signInRequired
        }
        if warning == .other {
            return .limitedCatalog
        }
        if gameCount == 0 {
            return .empty
        }
        if isPlus == false {
            return .subscriptionRequired
        }
        return nativeCatalog
            ? .catalogAvailable
            : .limitedCatalog
    }
}

/// The account and store locale a cloud status belongs to.
public struct CloudAccountScope: Codable, Hashable, Sendable {
    /// The account.
    public let accountID: UUID
    /// The store locale the catalog was read in.
    public let locale: String
    /// Creates a scope.
    ///
    /// - Parameters:
    ///   - accountID: The account.
    ///   - locale: The store locale.
    public init(accountID: UUID, locale: String) {
        self.accountID = accountID
        self.locale = locale
    }
}

/// Why the PS Cloud status could not be read or stored.
public enum CloudStatusFailure: String, Error, Codable, Equatable, Sendable {
    /// Cloud status is not integrated, sign-in is needed or was rejected, the region is unsupported, the
    /// network failed, the answer was malformed, or the cache could not be written.
    case notIntegrated, signInRequired, authorizationRejected, regionUnsupported, network,
         malformedResponse, storage
}
