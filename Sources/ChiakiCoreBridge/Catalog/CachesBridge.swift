import ChiakiBridge
import Foundation

/// Reads and clears the caches the open core keeps on disk.
///
/// Each call reads or writes the core's record store, so it runs on a dispatch queue while the calling task
/// waits.
public struct CachesBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// How much each cache holds.
    ///
    /// - Returns: One summary per cache.
    /// - Throws: The ``CatalogUnanswered`` that stopped the listing.
    public func summaries() async throws(CatalogUnanswered) -> [CoreCacheSummary] {
        let result = await CoreCancellation.run(qos: .utility) { _ in
            Self.result(of: chiaki_bridge.CachesBridge.summaries())
        }
        return try result.get()
    }

    /// The records one cache holds.
    ///
    /// - Parameter cache: The cache.
    /// - Returns: Its records.
    /// - Throws: The ``CatalogUnanswered`` that stopped the listing.
    public func entries(of cache: CoreCacheID) async throws(CatalogUnanswered) -> [CoreCacheEntry] {
        let result = await CoreCancellation.run(qos: .utility) { _ in
            Self.result(of: chiaki_bridge.CachesBridge.entries(cache))
        }
        return try result.get()
    }

    /// Empties one cache.
    ///
    /// - Parameter cache: The cache.
    /// - Throws: The ``CatalogUnanswered`` that stopped the clearing.
    public func clear(_ cache: CoreCacheID) async throws(CatalogUnanswered) {
        let result = await CoreCancellation.run(qos: .utility) { _ in
            Self.result(of: chiaki_bridge.CachesBridge.clear(cache))
        }
        try result.get()
    }

    /// Empties every cache.
    ///
    /// - Throws: The ``CatalogUnanswered`` that stopped the clearing.
    public func clearAll() async throws(CatalogUnanswered) {
        let result = await CoreCancellation.run(qos: .utility) { _ in
            Self.result(of: chiaki_bridge.CachesBridge.clear_all())
        }
        try result.get()
    }

    /// The model result of a summary listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The summaries or the failure.
    static func result(of outcome: chiaki_bridge
        .SummariesOutcome) -> Result<[CoreCacheSummary], CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(outcome.summaries().map {
                CoreCacheSummary(id: $0.cache, entries: Int($0.entries), bytes: Int(clamping: $0.bytes))
            })
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of an entry listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The entries or the failure.
    static func result(of outcome: chiaki_bridge
        .EntriesOutcome) -> Result<[CoreCacheEntry], CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(outcome.entries().map(entry(of:)))
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model result of a clearing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: Nothing, or the failure.
    static func result(of outcome: chiaki_bridge.ClearOutcome) -> Result<Void, CatalogUnanswered> {
        switch outcome.kind() {
        case .answered:
            return .success(())
        case .unanswered:
            return .failure(CatalogUnanswered.of(outcome.why_unanswered()))
        case .refused:
            return .failure(CatalogUnanswered.of(outcome.refusal()))
        }
    }

    /// The model entry of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The entry.
    static func entry(of facts: chiaki_bridge.CacheEntryFacts) -> CoreCacheEntry {
        CoreCacheEntry(
            cache: facts.cache,
            account: facts.account_id.value.map { Data($0) },
            locale: facts.locale.value.map { String($0) },
            productID: facts.product_id.value.map { String($0) },
            conceptID: facts.concept_id.value.map { String($0) },
            imageURL: facts.image_url.value.map { String($0) },
            bytes: Int(clamping: facts.bytes),
            storedAt: CatalogBridge.date(of: facts.stored_at_ms),
            expiresAt: facts.expires_at_ms.value.map(CatalogBridge.date(of:))
        )
    }
}

/// One record a core cache holds, described by whatever identifies it.
public struct CoreCacheEntry: Equatable, Sendable {
    /// The cache the record belongs to.
    public let cache: CoreCacheID

    /// The account the record was kept for, when it is per account.
    public let account: Data?

    /// The store locale the record was kept for, when it has one.
    public let locale: String?

    /// The product the record describes, when it is kept by product.
    public let productID: String?

    /// The concept the record describes, when it is kept by concept.
    public let conceptID: String?

    /// The image's address, when the record is an image.
    public let imageURL: String?

    /// The record's size in bytes.
    public let bytes: Int

    /// When the record was written.
    public let storedAt: Date

    /// When the record stops being reused, when it does.
    public let expiresAt: Date?

    /// Describes a record.
    ///
    /// - Parameters:
    ///   - cache: The cache.
    ///   - account: The account.
    ///   - locale: The store locale.
    ///   - productID: The product.
    ///   - conceptID: The concept.
    ///   - imageURL: The image's address.
    ///   - bytes: The size in bytes.
    ///   - storedAt: When it was written.
    ///   - expiresAt: When it stops being reused.
    public init(
        cache: CoreCacheID,
        account: Data? = nil,
        locale: String? = nil,
        productID: String? = nil,
        conceptID: String? = nil,
        imageURL: String? = nil,
        bytes: Int,
        storedAt: Date,
        expiresAt: Date? = nil
    ) {
        self.cache = cache
        self.account = account
        self.locale = locale
        self.productID = productID
        self.conceptID = conceptID
        self.imageURL = imageURL
        self.bytes = bytes
        self.storedAt = storedAt
        self.expiresAt = expiresAt
    }
}

/// A cache the core keeps on disk.
public typealias CoreCacheID = libchiaking.catalog.CacheId

/// How much one core cache holds.
public struct CoreCacheSummary: Equatable, Sendable {
    /// The cache.
    public let id: CoreCacheID

    /// How many records it holds.
    public let entries: Int

    /// How many bytes those records take.
    public let bytes: Int

    /// Describes a cache.
    ///
    /// - Parameters:
    ///   - id: The cache.
    ///   - entries: How many records it holds.
    ///   - bytes: How many bytes they take.
    public init(id: CoreCacheID, entries: Int, bytes: Int) {
        self.id = id
        self.entries = entries
        self.bytes = bytes
    }
}
