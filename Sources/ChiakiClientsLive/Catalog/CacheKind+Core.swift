import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
import Foundation

extension CacheEntry {
    /// A record the core reported.
    ///
    /// - Parameter entry: What the core reported.
    public init(_ entry: CoreCacheEntry) {
        self.init(
            cache: CacheKind(entry.cache),
            account: entry.account,
            locale: entry.locale,
            productID: entry.productID,
            conceptID: entry.conceptID,
            imageURL: entry.imageURL,
            bytes: entry.bytes,
            storedAt: entry.storedAt,
            expiresAt: entry.expiresAt
        )
    }
}

extension CacheKind {
    /// The kind of a cache the core names.
    ///
    /// - Parameter id: The core's cache.
    public init(_ id: CoreCacheID) {
        switch id {
        case .streamable_lists:
            self = .streamableLists
        case .included_titles:
            self = .includedTitles
        case .libraries:
            self = .libraries
        case .refusals:
            self = .refusals
        case .game_details:
            self = .gameDetails
        case .images:
            self = .images
        case .for_sale_titles:
            self = .forSaleTitles
        case .played_games:
            self = .playedGames
        }
    }

    /// The core's name for this cache.
    public var coreID: CoreCacheID {
        switch self {
        case .streamableLists:
            .streamable_lists
        case .includedTitles:
            .included_titles
        case .libraries:
            .libraries
        case .refusals:
            .refusals
        case .gameDetails:
            .game_details
        case .images:
            .images
        case .forSaleTitles:
            .for_sale_titles
        case .playedGames:
            .played_games
        }
    }
}

extension CacheSummary {
    /// The summary of a cache the core reported.
    ///
    /// - Parameter summary: What the core reported.
    public init(_ summary: CoreCacheSummary) {
        self.init(id: CacheKind(summary.id), entries: summary.entries, bytes: summary.bytes)
    }
}
