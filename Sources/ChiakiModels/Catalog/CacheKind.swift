import Foundation

/// A cache the core keeps on disk.
public enum CacheKind: CaseIterable, Hashable, Sendable {
    /// The lists of streamable games.
    case streamableLists

    /// The PlayStation Plus titles.
    case includedTitles

    /// The accounts' libraries.
    case libraries

    /// The stream server's refusals.
    case refusals

    /// The games' details.
    case gameDetails

    /// The downloaded images.
    case images

    /// The titles available to buy.
    case forSaleTitles

    /// The games each account has played.
    case playedGames
}

/// One record a core cache holds, described by whatever identifies it.
public struct CacheEntry: Equatable, Sendable {
    /// The cache the record belongs to.
    public let cache: CacheKind

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
        cache: CacheKind,
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

/// How much one core cache holds.
public struct CacheSummary: Equatable, Sendable {
    /// The cache.
    public let id: CacheKind

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
    public init(id: CacheKind, entries: Int, bytes: Int) {
        self.id = id
        self.entries = entries
        self.bytes = bytes
    }
}

/// What a clear removes: one cache, or every cache.
public enum CacheClearing: Equatable, Sendable {
    /// Clears the given cache.
    case one(CacheKind)

    /// Clears every cache.
    case all

    /// Whether this clear removes artwork, so decoded images in memory must be dropped too.
    public var holdsArtwork: Bool {
        switch self {
        case .one(let cache):
            cache == .images
        case .all:
            true
        }
    }
}
