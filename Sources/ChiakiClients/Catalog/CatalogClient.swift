import ChiakiModels
import CoreGraphics
import Dependencies
import Foundation

/// Reaches the cloud catalog: the account's games, their launch checks and store pages, the images the library
/// draws, the core's caches, the entitlements panel's explained titles and the time on the PlayStation Network
/// servers.
///
/// Every catalog call goes through the core. The core runs one library fetch per account and joins every further
/// caller to it; the live value, in `ChiakiClientsLive`, reaches it through the app's one cloud library service
/// and runs one artwork pipeline that coalesces identical image requests and holds decoded images in memory. The
/// test value answers as if no catalog were reachable and holds and fetches no image, so a test states every
/// answer it relies on.
public struct CatalogClient: Sendable {
    /// Fetches the cloud library of an account, telling the observer every state the core reports for the fetch.
    ///
    /// - Parameters: the account, whether the core must fetch again instead of answering from its cache, the
    ///   locale the catalog is listed in, such as `"en-GB"`, and the observer, which is first told the state of a
    ///   fetch already running and never called after the call returns.
    public var library: @Sendable (
        _ account: UUID,
        _ force: Bool,
        _ locale: String,
        _ observe: @escaping @Sendable (CloudLibraryFetchState) -> Void
    ) async throws -> CloudLibrarySnapshot

    /// Asks the core again whether one title is in the account's library.
    public var refreshTitle: @Sendable (_ account: UUID, _ game: CloudGame) async -> CloudTitleRefreshOutcome

    /// Fetches the account's recently played cloud games.
    public var recentlyPlayed: @Sendable (_ account: UUID) async throws -> [CloudRecentlyPlayed]

    /// Runs the launch checks for one product and reports each step, then the clearance.
    public var clearForLaunch: @Sendable (_ account: UUID, _ product: ProductID)
        -> AsyncStream<CloudLaunchClearanceEvent>

    /// Fetches the details the game detail draws for one product: art, media, ratings and facts.
    public var gameDetails: @Sendable (_ account: UUID, _ product: ProductID) async
        -> Result<GameDetails, CatalogFailure>

    /// Asks the store page whether one edition streams from the cloud and whether a trial is still offered.
    public var storefrontCheck: @Sendable (_ account: UUID, _ game: CloudGame) async -> CloudStoreCheck

    /// Resolves the store page of one product for the account's region.
    public var storePage: @Sendable (_ account: UUID, _ product: ProductID) async -> URL?

    /// Reads the PlayStation Plus tier of a signed-in account.
    public var plusTier: @Sendable (_ account: UUID) async -> PlusTier?

    /// Lists the PS5 cloud games an account holds as a trial or demo from what the core already holds, asking
    /// the store nothing.
    public var heldTrials: @Sendable (_ account: UUID) async -> [CloudGame]

    /// Fetches a cover decoded to fill a box.
    public var thumbnail: @Sendable (_ url: URL, _ box: ArtworkBox) async throws -> CGImage

    /// The cover already decoded for an address, large enough for the box when one is given.
    public var heldThumbnail: @Sendable (_ url: URL, _ box: ArtworkBox?) -> CGImage?

    /// Fetches a cloud hero at full size.
    public var hero: @Sendable (_ url: URL) async throws -> CGImage

    /// The hero already decoded for an address.
    public var heldHero: @Sendable (_ url: URL) -> CGImage?

    /// Fetches covers ahead of the page that shows them.
    public var prefetch: @Sendable (_ urls: [URL], _ box: ArtworkBox) async -> Void

    /// Fetches one piece of game detail art.
    public var gameArt: @Sendable (_ url: URL, _ size: GameArtSize) async -> CGImage?

    /// Loads every layer of a game's detail art.
    public var artLayers: @Sendable (_ art: GameDetails.Art) async -> GameArtLayers?

    /// The layers of a game's detail art when every one is already decoded.
    public var heldArtLayers: @Sendable (_ art: GameDetails.Art) -> GameArtLayers?

    /// Remembers the detail art of a product for ``knownArtLayers``.
    public var rememberArt: @Sendable (_ art: GameDetails.Art, _ product: ProductID) -> Void

    /// The decoded layers of a product's remembered art.
    public var knownArtLayers: @Sendable (_ product: ProductID) -> GameArtLayers?

    /// Grabs a still of a trailer.
    public var trailerFrame: @Sendable (_ url: URL) async -> CGImage?

    /// The decoded artwork images held in memory.
    public var decodedCount: @Sendable () -> Int

    /// Drops every decoded artwork image held in memory.
    public var clearDecoded: @Sendable () -> Void

    /// Reads the entry count and size of every core cache.
    public var cacheSummaries: @Sendable () async throws -> [CacheSummary]

    /// Reads the stored records of one cache.
    public var cacheEntries: @Sendable (CacheKind) async throws -> [CacheEntry]

    /// Clears one cache or all of them in the core.
    public var clearCache: @Sendable (CacheClearing) async throws -> Void

    /// Returns display names for saved accounts, keyed by account ID, to label account-scoped cache records.
    public var cacheAccountNames: @Sendable () async -> [Data: String]

    /// Lists the saved PlayStation accounts the entitlements panel offers.
    public var entitlementAccounts: @Sendable () async throws -> [EntitlementAccount]

    /// Fetches the account's cloud library for the given catalogue locale and explains each title.
    public var explainedTitles: @Sendable (_ account: EntitlementAccount, _ locale: String) async throws
        -> [ExplainedTitle]

    /// Reports how the catalogue was fetched for the account, or `nil` when no report is available.
    public var fetchReport: @Sendable (EntitlementAccount) async -> CatalogFetchReport?

    /// The time on the PlayStation Network servers from the last reply seen, or `nil` before any reply; it
    /// decides when a cloud title's release countdown ends.
    public var serverTime: @Sendable () -> Date?

    /// Creates a client from its operations; only the catalog's own are required.
    ///
    /// - Parameters:
    ///   - library: Fetches the cloud library of an account, telling the observer every state of the fetch.
    ///   - refreshTitle: Asks the core again whether one title is in the account's library.
    ///   - recentlyPlayed: Fetches the account's recently played cloud games.
    ///   - clearForLaunch: Runs the launch checks for one product and reports each step, then the clearance.
    ///   - gameDetails: Fetches the details the game detail draws for one product: art, media, ratings and facts.
    ///   - storefrontCheck: Asks the store page whether one edition streams from the cloud and whether a trial
    ///     is still offered.
    ///   - storePage: Resolves the store page of one product for the account's region.
    ///   - plusTier: Reads the PlayStation Plus tier of a signed-in account.
    ///   - heldTrials: Lists the games an account holds as a trial or demo, asking the store nothing; by default
    ///     none.
    ///   - thumbnail: Fetches a cover decoded to fill a box; by default it fails.
    ///   - heldThumbnail: The cover already decoded for an address; by default none.
    ///   - hero: Fetches a cloud hero at full size; by default it fails.
    ///   - heldHero: The hero already decoded for an address; by default none.
    ///   - prefetch: Fetches covers ahead of the page that shows them; by default nothing.
    ///   - gameArt: Fetches one piece of game detail art; by default none.
    ///   - artLayers: Loads every layer of a game's detail art; by default none.
    ///   - heldArtLayers: The layers of a game's detail art when every one is already decoded; by default none.
    ///   - rememberArt: Remembers the detail art of a product; by default nothing.
    ///   - knownArtLayers: The decoded layers of a product's remembered art; by default none.
    ///   - trailerFrame: Grabs a still of a trailer; by default none.
    ///   - decodedCount: The decoded artwork images held in memory; by default zero.
    ///   - clearDecoded: Drops every decoded artwork image; by default nothing.
    ///   - cacheSummaries: Reads every cache's counts and size; by default none.
    ///   - cacheEntries: Reads the records of one cache; by default none.
    ///   - clearCache: Clears one cache or all of them; by default nothing.
    ///   - cacheAccountNames: Returns saved account display names keyed by account ID; by default none.
    ///   - entitlementAccounts: Lists the saved PlayStation accounts; by default none.
    ///   - explainedTitles: Fetches an account's cloud library in a catalogue locale and explains each title; by
    ///     default it fails.
    ///   - fetchReport: Reports how the catalogue was fetched for an account; by default no report.
    ///   - serverTime: Reads the time on the PlayStation Network servers; by default unknown, so countdowns
    ///     follow the device clock.
    public init(
        library: @escaping @Sendable (
            UUID,
            Bool,
            String,
            @escaping @Sendable (CloudLibraryFetchState) -> Void
        ) async throws -> CloudLibrarySnapshot,
        refreshTitle: @escaping @Sendable (UUID, CloudGame) async -> CloudTitleRefreshOutcome,
        recentlyPlayed: @escaping @Sendable (UUID) async throws -> [CloudRecentlyPlayed],
        clearForLaunch: @escaping @Sendable (UUID, ProductID) -> AsyncStream<CloudLaunchClearanceEvent>,
        gameDetails: @escaping @Sendable (UUID, ProductID) async -> Result<GameDetails, CatalogFailure>,
        storefrontCheck: @escaping @Sendable (UUID, CloudGame) async -> CloudStoreCheck,
        storePage: @escaping @Sendable (UUID, ProductID) async -> URL?,
        plusTier: @escaping @Sendable (UUID) async -> PlusTier?,
        heldTrials: @escaping @Sendable (UUID) async -> [CloudGame] = { _ in
            []
        },
        thumbnail: @escaping @Sendable (URL, ArtworkBox) async throws -> CGImage = { _, _ in
            throw URLError(.resourceUnavailable)
        },
        heldThumbnail: @escaping @Sendable (URL, ArtworkBox?) -> CGImage? = { _, _ in
            nil
        },
        hero: @escaping @Sendable (URL) async throws -> CGImage = { _ in
            throw URLError(.resourceUnavailable)
        },
        heldHero: @escaping @Sendable (URL) -> CGImage? = { _ in
            nil
        },
        prefetch: @escaping @Sendable ([URL], ArtworkBox) async -> Void = { _, _ in
        },
        gameArt: @escaping @Sendable (URL, GameArtSize) async -> CGImage? = { _, _ in
            nil
        },
        artLayers: @escaping @Sendable (GameDetails.Art) async -> GameArtLayers? = { _ in
            nil
        },
        heldArtLayers: @escaping @Sendable (GameDetails.Art) -> GameArtLayers? = { _ in
            nil
        },
        rememberArt: @escaping @Sendable (GameDetails.Art, ProductID) -> Void = { _, _ in
        },
        knownArtLayers: @escaping @Sendable (ProductID) -> GameArtLayers? = { _ in
            nil
        },
        trailerFrame: @escaping @Sendable (URL) async -> CGImage? = { _ in
            nil
        },
        decodedCount: @escaping @Sendable () -> Int = {
            0
        },
        clearDecoded: @escaping @Sendable () -> Void = {
        },
        cacheSummaries: @escaping @Sendable () async throws -> [CacheSummary] = {
            []
        },
        cacheEntries: @escaping @Sendable (CacheKind) async throws -> [CacheEntry] = { _ in
            []
        },
        clearCache: @escaping @Sendable (CacheClearing) async throws -> Void = { _ in
        },
        cacheAccountNames: @escaping @Sendable () async -> [Data: String] = {
            [:]
        },
        entitlementAccounts: @escaping @Sendable () async throws -> [EntitlementAccount] = {
            []
        },
        explainedTitles: @escaping @Sendable (EntitlementAccount, String) async throws -> [ExplainedTitle] = {
            _, _ in
            throw EntitlementsFailure("Entitlements are unavailable in tests.")
        },
        fetchReport: @escaping @Sendable (EntitlementAccount) async -> CatalogFetchReport? = { _ in
            nil
        },
        serverTime: @escaping @Sendable () -> Date? = {
            nil
        }
    ) {
        self.library = library
        self.refreshTitle = refreshTitle
        self.recentlyPlayed = recentlyPlayed
        self.clearForLaunch = clearForLaunch
        self.gameDetails = gameDetails
        self.storefrontCheck = storefrontCheck
        self.storePage = storePage
        self.plusTier = plusTier
        self.heldTrials = heldTrials
        self.thumbnail = thumbnail
        self.heldThumbnail = heldThumbnail
        self.hero = hero
        self.heldHero = heldHero
        self.prefetch = prefetch
        self.gameArt = gameArt
        self.artLayers = artLayers
        self.heldArtLayers = heldArtLayers
        self.rememberArt = rememberArt
        self.knownArtLayers = knownArtLayers
        self.trailerFrame = trailerFrame
        self.decodedCount = decodedCount
        self.clearDecoded = clearDecoded
        self.cacheSummaries = cacheSummaries
        self.cacheEntries = cacheEntries
        self.clearCache = clearCache
        self.cacheAccountNames = cacheAccountNames
        self.entitlementAccounts = entitlementAccounts
        self.explainedTitles = explainedTitles
        self.fetchReport = fetchReport
        self.serverTime = serverTime
    }
}

extension CatalogClient: TestDependencyKey {
    /// Answers as if no catalog were reachable, holds and fetches no image, reports no caches and no
    /// entitlement accounts, fails every entitlements load and knows no server time; a test overrides each
    /// answer it relies on.
    public static let testValue = CatalogClient(
        library: { _, _, _, _ in
            throw CloudLibraryFailure.unavailable
        },
        refreshTitle: { _, _ in
            .failed(CloudTitleRefreshFailure("unavailable"))
        },
        recentlyPlayed: { _ in
            []
        },
        clearForLaunch: { _, _ in
            AsyncStream { continuation in
                continuation.yield(.finished(.failure(CatalogFailure(reason: .unavailable))))
                continuation.finish()
            }
        },
        gameDetails: { _, _ in
            .failure(CatalogFailure(reason: .coreClosed))
        },
        storefrontCheck: { _, _ in
            CloudStoreCheck(card: .unavailable("no answer"))
        },
        storePage: { _, _ in
            nil
        },
        plusTier: { _ in
            nil
        }
    )
}

extension DependencyValues {
    /// The cloud catalog the library reads, with its artwork, caches, entitlements and server clock.
    public var catalog: CatalogClient {
        get {
            self[CatalogClient.self]
        }
        set {
            self[CatalogClient.self] = newValue
        }
    }
}
