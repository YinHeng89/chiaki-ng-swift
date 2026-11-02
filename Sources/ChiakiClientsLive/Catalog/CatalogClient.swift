import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import CoreGraphics
import Dependencies
import Foundation

extension CatalogClient {
    /// The catalog read through the open core, fetching libraries through one service, with images fetched
    /// through the core into one pipeline held for the app's lifetime, the core's cache store, the saved
    /// accounts, entitlements explained through the catalogue bridge and the server time the core saw in the last
    /// server reply.
    ///
    /// - Parameter library: The app's one cloud library service.
    /// - Returns: The live client.
    public static func live(library: CloudLibraryService) -> CatalogClient {
        CatalogClient(
            library: { account, force, locale, observe in
                let snapshot = try await library.fetch(
                    account: account,
                    force: force,
                    locale: locale,
                    observe: observe
                )
                guard CloudSamplePreorders.enabled else {
                    return snapshot
                }
                return CloudSamplePreorders.adding(to: snapshot, now: Date())
            },
            refreshTitle: { account, game in
                await library.refreshTitle(account: account, game: game)
            },
            recentlyPlayed: { account in
                try await library.recentlyPlayed(account: account)
            },
            clearForLaunch: { account, product in
                liveClearance(account: account, product: product)
            },
            gameDetails: { account, product in
                await liveGameDetails(account: account, product: product)
            },
            storefrontCheck: { account, game in
                await storefrontCheck(account: account, game: game)
            },
            storePage: { account, product in
                @Dependency(\.accountService) var accountService
                guard let id = try? await accountService.accountID(of: account) else {
                    return nil
                }
                return await TitleChecksBridge().storePage(account: id, productID: product.rawValue)
            },
            plusTier: { account in
                @Dependency(\.accountService) var accountService
                guard let id = try? await accountService.accountID(of: account) else {
                    return nil
                }
                return UsersBridge().find(id)?.tier ?? nil
            },
            heldTrials: { account in
                @Dependency(\.accountService) var accountService
                guard let id = try? await accountService.accountID(of: account) else {
                    return []
                }
                return CatalogBridge().heldTrials(account: id)
            },
            cacheSummaries: {
                try await CachesBridge().summaries().map { CacheSummary($0) }
            },
            cacheEntries: { cache in
                try await CachesBridge().entries(of: cache.coreID).map { CacheEntry($0) }
            },
            clearCache: { clearing in
                switch clearing {
                case .one(let cache):
                    try await CachesBridge().clear(cache.coreID)
                case .all:
                    try await CachesBridge().clearAll()
                }
            },
            cacheAccountNames: {
                @Dependency(\.accountService) var accountService
                let profiles = (try? await accountService.storage().accounts.list()) ?? []
                return Dictionary(
                    profiles.map { ($0.accountID.data, $0.onlineID ?? $0.name) },
                    uniquingKeysWith: { first, _ in first }
                )
            },
            entitlementAccounts: {
                @Dependency(\.accountService) var accountService
                return try await accountService.storage().accounts.list().map {
                    EntitlementAccount(id: $0.id, name: $0.onlineID ?? $0.name, accountID: $0.accountID)
                }
            },
            explainedTitles: { account, locale in
                try await Self.explainedTitles(account: account, locale: locale, library: library)
            },
            fetchReport: { account in
                CatalogBridge().howFetched(account: account.accountID)
            },
            serverTime: {
                UsersBridge().serverTime()
            }
        ).runningArtwork(on: artworkPipeline)
    }

    private static let artworkPipeline: ArtworkPipeline = {
        let calls = CoreImageCalls(limit: 12)
        return ArtworkPipeline { url in
            try await TitleChecksBridge().image(url: url.absoluteString, through: calls).get()
        }
    }()

    /// Returns this client with every artwork operation running on a pipeline.
    ///
    /// - Parameter pipeline: The pipeline that fetches, coalesces and holds the images.
    /// - Returns: A copy whose artwork calls all go through the pipeline.
    func runningArtwork(on pipeline: ArtworkPipeline) -> CatalogClient {
        var client = self
        client.thumbnail = { url, box in
            try await pipeline.thumbnail(url, box: box)
        }
        client.heldThumbnail = { url, box in
            pipeline.shelves.thumbnails.image(for: url, box: box)
        }
        client.hero = { url in
            try await pipeline.hero(url)
        }
        client.heldHero = { url in
            pipeline.shelves.heroes.image(for: url)
        }
        client.prefetch = { urls, box in
            await pipeline.prefetch(urls, box: box)
        }
        client.gameArt = { url, size in
            try? await pipeline.gameArt(url, size: size)
        }
        client.artLayers = { art in
            await Self.artLayers(art, in: pipeline)
        }
        client.heldArtLayers = { art in
            pipeline.heldLayers(art)
        }
        client.rememberArt = { art, product in
            pipeline.remember(art, for: product)
        }
        client.knownArtLayers = { product in
            pipeline.knownLayers(product)
        }
        client.trailerFrame = { url in
            try? await pipeline.trailerFrame(url)
        }
        client.decodedCount = {
            pipeline.decodedCount
        }
        client.clearDecoded = {
            pipeline.clear()
        }
        return client
    }

    private static func artLayers(
        _ art: GameDetails.Art,
        in pipeline: ArtworkPipeline
    ) async -> GameArtLayers? {
        @Dependency(\.logger) var logger
        let clock = ContinuousClock()
        let start = clock.now
        let layers = await pipeline.layers(art)
        let outcome = layers == nil
            ? "a layer failed, showing the card"
            : "layered view ready"
        await logger.log(.diagnostic(
            .cloudLibrary, .info,
            "Game detail art: \(outcome) after \(LogFormat.milliseconds(start.duration(to: clock.now))) ms"
        ))
        return layers
    }

    private static func explainedTitles(
        account: EntitlementAccount,
        locale: String,
        library: CloudLibraryService
    ) async throws -> [ExplainedTitle] {
        let catalog = CatalogBridge()
        do {
            let snapshot = try await library.fetch(
                account: account.id,
                force: false,
                locale: locale,
                observe: { _ in
                }
            )
            return snapshot.games.map {
                ExplainedTitle(
                    game: $0,
                    explanation: catalog.explain(account: account.accountID, productID: $0.productId)
                        ?? CatalogExplanation(listed: false, steps: [])
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EntitlementsFailure(CloudLibraryLog.reason(error))
        }
    }

    private static func liveGameDetails(
        account: UUID,
        product: ProductID
    ) async -> Result<GameDetails, CatalogFailure> {
        @Dependency(\.logger) var logger
        let clock = ContinuousClock()
        let start = clock.now
        @Dependency(\.accountService) var accountService
        guard let id = try? await accountService.accountID(of: account) else {
            return .failure(CatalogFailure(reason: .unknownUser))
        }
        let now = Date()
        let kept = (try? await CachesBridge().entries(of: CoreCacheID.game_details)) ?? []
        let cached = kept.contains { entry in
            entry.productID?.caseInsensitiveCompare(product.rawValue) == .orderedSame
                && (entry.expiresAt ?? now) > now
        }
        let checked = clock.now
        let result = await TitleChecksBridge().details(account: id, productID: product.rawValue)
            .mapError { CatalogFailure($0) }
        let source = cached
            ? "core cache"
            : "network"
        let timing = "cache check \(LogFormat.milliseconds(start.duration(to: checked))) ms, details "
            + "\(LogFormat.milliseconds(checked.duration(to: clock.now))) ms (\(source))"
        let outcome = switch result {
        case .success(let details) where details.art != nil:
            "layered or game hub art listed"
        case .success:
            "no layered or game hub art, showing the card"
        case .failure(let failure):
            "not answered (\(failure.reason)), showing the card"
        }
        await logger.log(.diagnostic(
            .cloudLibrary,
            .info,
            "Game detail \(product.rawValue): \(timing), \(outcome)"
        ))
        return result
    }

    private static func liveClearance(account: UUID,
                                      product: ProductID) -> AsyncStream<CloudLaunchClearanceEvent> {
        AsyncStream { continuation in
            let task = Task {
                @Dependency(\.accountService) var accountService
                guard let id = try? await accountService.accountID(of: account) else {
                    continuation.yield(.finished(.failure(CatalogFailure(
                        reason: .user,
                        needsSignIn: true
                    ))))
                    continuation.finish()
                    return
                }
                let result = await TitleChecksBridge()
                    .clearForLaunch(account: id, productID: product.rawValue) { check in
                        continuation.yield(.check(check))
                    }
                let finished = result
                    .map { CloudLaunchDecision($0) }
                    .mapError { CatalogFailure($0) }
                continuation.yield(.finished(finished))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func storefrontCheck(account: UUID, game: CloudGame) async -> CloudStoreCheck {
        @Dependency(\.accountService) var accountService
        guard let bytes = try? await accountService.accountID(of: account) else {
            return CloudStoreCheck(card: .unavailable("no PSN sign-in"))
        }
        switch await TitleChecksBridge().storefront(account: bytes, productID: game.productId) {
        case .success(let answer):
            return CloudStoreCheck(card: CloudCardCheck(answer.streaming), offersTrial: answer.offersTrial)
        case .failure(let failure):
            return CloudStoreCheck(card: .unavailable(
                failure.needsSignIn
                    ? "no PSN sign-in"
                    : "no answer"
            ))
        }
    }
}

extension CloudLaunchDecision {
    /// The decision the bridge reported, with a cleared launch carried as an opaque token.
    ///
    /// - Parameter clearance: What the bridge reported.
    public init(_ clearance: CloudLaunchClearance) {
        switch clearance {
        case .cleared(let launch):
            self = .cleared(launch.map(CloudLaunchClearanceToken.init))
        case .refused(let refusal):
            self = .refused(refusal)
        }
    }
}
