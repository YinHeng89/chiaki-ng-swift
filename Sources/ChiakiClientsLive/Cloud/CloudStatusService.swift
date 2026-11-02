import ChiakiModels
import ChiakiPersistence
import Foundation

/// Caches each account's PS Cloud status and shares one fetch among every caller waiting on it.
public actor CloudStatusService {
    private let repositories: AppRepositories
    private let catalog: CloudCatalogClient
    private var flights: [CloudAccountScope: Task<CloudStatusSnapshot, Error>] = [:]
    private let now: @Sendable () -> Date

    /// Creates the service over the app's repositories.
    ///
    /// - Parameters:
    ///   - repositories: Where accounts and the cached status live.
    ///   - catalog: Fetches the status from the core.
    ///   - now: The clock dating snapshots.
    public init(
        repositories: AppRepositories,
        catalog: CloudCatalogClient,
        now: @escaping @Sendable () -> Date = {
            Date()
        }
    ) {
        self.repositories = repositories
        self.catalog = catalog
        self.now = now
    }

    /// The cached snapshot for an account and locale, if one is stored and readable.
    ///
    /// - Parameter scope: The account and locale.
    /// - Returns: The snapshot, or `nil`.
    /// - Throws: `ChiakiModels/CloudStatusFailure/storage` when the cache cannot be read.
    public func cached(_ scope: CloudAccountScope) throws -> CloudStatusSnapshot? {
        do {
            return try stored(scope)
        } catch is PersistenceError {
            throw CloudStatusFailure.storage
        }
    }

    /// Fetches a fresh snapshot, joining a fetch already running for the same scope.
    ///
    /// - Parameter scope: The account and locale.
    /// - Returns: The fresh snapshot.
    /// - Throws: `ChiakiModels/CloudStatusFailure`, with `ChiakiModels/CloudStatusFailure/storage` when the cache
    ///   cannot be read or written.
    public func refresh(_ scope: CloudAccountScope) async throws -> CloudStatusSnapshot {
        do {
            return try await joinedFetch(scope)
        } catch is PersistenceError {
            throw CloudStatusFailure.storage
        }
    }

    private func stored(_ scope: CloudAccountScope) throws -> CloudStatusSnapshot? {
        guard let record = try repositories.resources.cached(.pscloud, for: scope.accountID) else {
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(CloudStatusSnapshot.self, from: record.payload),
              snapshot.schemaVersion == 1, snapshot.scope == scope,
              snapshot.catalog.gameCount >= 0, snapshot.expiresAt > snapshot.checkedAt
        else {
            return nil
        }
        return snapshot
    }

    private func joinedFetch(_ scope: CloudAccountScope) async throws -> CloudStatusSnapshot {
        if let flight = flights[scope] {
            let value = try await flight.value
            try Task.checkCancellation()
            return value
        }
        let flight = Task {
            try await self.fetchAndSave(scope)
        }
        flights[scope] = flight
        defer {
            flights[scope] = nil
        }
        let snapshot = try await flight.value
        try Task.checkCancellation()
        return snapshot
    }

    private func fetchAndSave(_ scope: CloudAccountScope) async throws -> CloudStatusSnapshot {
        guard !scope.locale.isEmpty,
              let account = try repositories.accounts.list().first(where: {
                  $0.id == scope.accountID
              }), account.method == .npsso
        else {
            throw CloudStatusFailure.signInRequired
        }
        try Task.checkCancellation()
        let evidence = try await catalog.fetch(scope)
        try Task.checkCancellation()
        guard evidence.gameCount >= 0 else {
            throw CloudStatusFailure.malformedResponse
        }
        return try save(evidence, scope: scope, now: now())
    }

    private func save(_ evidence: CloudCatalogEvidence, scope: CloudAccountScope, now: Date) throws
        -> CloudStatusSnapshot {
        let previous = try repositories.resources.cached(.pscloud, for: scope.accountID).flatMap {
            try? JSONDecoder().decode(CloudStatusSnapshot.self, from: $0.payload)
        }
        .flatMap {
            $0.schemaVersion == 1 && $0.scope == scope
                ? $0
                : nil
        }
        let snapshot = CloudStatusSnapshot(
            scope: scope,
            catalog: evidence,
            checkedAt: now,
            expiresAt: now.addingTimeInterval(900),
            games: previous?.games.filter {
                $0.value.expiresAt > now
            } ?? [:]
        )
        try repositories.resources.cache(
            .pscloud,
            for: scope.accountID,
            payload: JSONEncoder().encode(snapshot),
            now: snapshot.checkedAt,
            ttl: snapshot.expiresAt.timeIntervalSince(snapshot.checkedAt)
        )
        return snapshot
    }
}

/// Fetches catalog evidence for an account and locale.
public struct CloudCatalogClient: Sendable {
    /// Reads the catalog for a scope.
    public var fetch: @Sendable (CloudAccountScope) async throws -> CloudCatalogEvidence
    /// Creates a client over a fetch closure.
    ///
    /// - Parameter fetch: Reads the catalog for a scope.
    public init(fetch: @escaping @Sendable (CloudAccountScope) async throws -> CloudCatalogEvidence) {
        self.fetch = fetch
    }
}
