import AVFoundation
import ChiakiClients
import ChiakiModels
import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Fetches, decodes and holds every image the library draws: covers, heroes, game detail art and trailer stills.
///
/// Identical requests share one fetch: a request joins a pending fetch whose box covers it, and the fetch is
/// cancelled only when every request waiting on it has left. Decoded images are held in one `ArtworkCache`
/// per ``Shelf``, which views read synchronously.
actor ArtworkPipeline {
    /// Which cache an image is held in.
    enum Shelf: Hashable, Sendable {
        /// Card covers.
        case thumbnail
        /// Full-size cloud heroes.
        case hero
        /// Game detail layers, screenshots and icons.
        case gameArt
        /// Trailer stills.
        case trailer
    }

    /// The caches the pipeline holds images in, one per ``Shelf``.
    struct Shelves: Sendable {
        /// Card covers.
        let thumbnails: ArtworkCache
        /// Full-size cloud heroes.
        let heroes: ArtworkCache
        /// Game detail layers, screenshots and icons.
        let gameArt: ArtworkCache
        /// Trailer stills.
        let trailers: ArtworkCache

        /// Creates the caches the app uses.
        ///
        /// - Returns: Caches sized for the library's grid, detail and trailers.
        static func standard() -> Shelves {
            Shelves(
                thumbnails: ArtworkCache(costLimit: 256 * 1024 * 1024, countLimit: 384),
                heroes: ArtworkCache(costLimit: 128 * 1024 * 1024, countLimit: 12),
                gameArt: ArtworkCache(costLimit: 192 * 1024 * 1024, countLimit: 64),
                trailers: ArtworkCache(costLimit: 48 * 1024 * 1024, countLimit: 64)
            )
        }

        /// Every cache.
        var all: [ArtworkCache] {
            [thumbnails, heroes, gameArt, trailers]
        }

        /// The cache of one shelf.
        ///
        /// - Parameter shelf: The shelf.
        /// - Returns: Its cache.
        func cache(_ shelf: Shelf) -> ArtworkCache {
            switch shelf {
            case .thumbnail:
                thumbnails
            case .hero:
                heroes
            case .gameArt:
                gameArt
            case .trailer:
                trailers
            }
        }
    }

    /// The largest cover the pipeline decodes, in bytes.
    static let thumbnailBytes = 8 * 1024 * 1024
    /// The largest hero or detail layer the pipeline decodes, in bytes.
    static let heroBytes = 16 * 1024 * 1024
    /// The box trailer stills decode to.
    static let trailerBox = ArtworkBox(width: 640, height: 384)

    private struct Key: Hashable {
        let url: URL
        let shelf: Shelf
    }

    private struct Pending {
        let task: Task<CGImage, Error>
        let box: ArtworkBox
        var waiters: Set<UUID>
    }

    /// The caches the pipeline fills.
    nonisolated let shelves: Shelves
    private let bytes: @Sendable (URL) async throws -> Data
    private let still: @Sendable (URL, ArtworkBox) async throws -> CGImage
    private let remembered = Mutex<[ProductID: GameDetails.Art]>([:])
    private let prefetched = Mutex<[URL: ArtworkBox]>([:])
    private var pending: [Key: Pending] = [:]

    /// Creates a pipeline.
    ///
    /// - Parameters:
    ///   - shelves: The caches to fill.
    ///   - bytes: Fetches the bytes of an image.
    ///   - still: Grabs a still of a trailer, fitted to a box.
    init(
        shelves: Shelves = .standard(),
        bytes: @escaping @Sendable (URL) async throws -> Data,
        still: @escaping @Sendable (URL, ArtworkBox) async throws -> CGImage = ArtworkDecoder.trailerStill
    ) {
        self.shelves = shelves
        self.bytes = bytes
        self.still = still
    }

    /// The fetches still running.
    var fetching: Int {
        pending.count
    }

    /// The decoded images still alive in any cache.
    nonisolated var decodedCount: Int {
        shelves.all.reduce(0) { total, cache in
            total + cache.count
        }
    }

    /// Drops every decoded image and forgets which covers were prefetched.
    nonisolated func clear() {
        for cache in shelves.all {
            cache.removeAll()
        }
        prefetched.withLock {
            $0 = [:]
        }
    }

    /// Fetches a cover decoded to fill a box.
    ///
    /// - Parameters:
    ///   - url: The cover's address.
    ///   - box: The box it fills.
    /// - Returns: The decoded cover.
    /// - Throws: When it cannot be fetched or decoded, or is larger than ``thumbnailBytes``.
    func thumbnail(_ url: URL, box: ArtworkBox) async throws -> CGImage {
        try await image(Key(url: url, shelf: .thumbnail), box: box) { [bytes] target in
            try await ArtworkDecoder.decoded(bytes(url), limit: Self.thumbnailBytes, box: target)
        }
    }

    /// Fetches a cloud hero at full size.
    ///
    /// - Parameter url: The hero's address.
    /// - Returns: The decoded hero.
    /// - Throws: When it cannot be fetched or decoded, or is larger than ``heroBytes``.
    func hero(_ url: URL) async throws -> CGImage {
        try await image(Key(url: url, shelf: .hero), box: .full) { [bytes] target in
            try await ArtworkDecoder.decoded(bytes(url), limit: Self.heroBytes, box: target)
        }
    }

    /// Fetches game detail art, trying the resized image first when the size asks for one.
    ///
    /// - Parameters:
    ///   - url: The original image address.
    ///   - size: The size it is drawn at.
    /// - Returns: The decoded image.
    /// - Throws: When no candidate can be fetched and decoded.
    func gameArt(_ url: URL, size: GameArtSize) async throws -> CGImage {
        let candidates = size.candidates(for: url)
        return try await image(Key(url: candidates[0], shelf: .gameArt), box: size.box) { [bytes] target in
            for candidate in candidates {
                try Task.checkCancellation()
                guard let data = try? await bytes(candidate),
                      let image = try? ArtworkDecoder.decoded(data, limit: Self.heroBytes, box: target) else {
                    continue
                }
                return image
            }
            throw URLError(.cannotDecodeContentData)
        }
    }

    /// The game detail art already decoded for a size.
    ///
    /// - Parameters:
    ///   - url: The original image address.
    ///   - size: The size it is drawn at.
    /// - Returns: `nil` when it has not been decoded large enough.
    nonisolated func heldGameArt(_ url: URL, size: GameArtSize) -> CGImage? {
        shelves.gameArt.image(for: size.candidates(for: url)[0], box: size.box)
    }

    /// Grabs a still of a trailer.
    ///
    /// - Parameter url: The trailer's address.
    /// - Returns: The still.
    /// - Throws: When no frame could be read.
    func trailerFrame(_ url: URL) async throws -> CGImage {
        try await image(Key(url: url, shelf: .trailer), box: Self.trailerBox) { [still] target in
            try await still(url, target)
        }
    }

    /// Fetches covers ahead of the page that shows them, asking for each address and box once.
    ///
    /// - Parameters:
    ///   - urls: The covers' addresses.
    ///   - box: The box they fill.
    func prefetch(_ urls: [URL], box: ArtworkBox) async {
        let wanted = prefetched.withLock { asked in
            urls.filter { url in
                if let had = asked[url], had.covers(box) {
                    return false
                }
                asked[url] = box
                return true
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for url in wanted {
                group.addTask {
                    _ = try? await self.thumbnail(url, box: box)
                }
            }
        }
    }

    /// Loads every layer of a game's detail art.
    ///
    /// - Parameter art: The art's addresses.
    /// - Returns: The layers, or `nil` when any layer the art needs could not be loaded.
    func layers(_ art: GameDetails.Art) async -> GameArtLayers? {
        switch art {
        case .layered(let layered):
            async let background = optionalArt(layered.background, size: .backdrop)
            async let hero = optionalArt(layered.hero, size: .hero)
            async let logo = optionalArt(layered.logo, size: .logo)
            guard let background = await background, let hero = await hero, let logo = await logo else {
                return nil
            }
            return GameArtLayers(background: background, hero: hero, logo: logo)
        case .gameHub(let gameHub):
            async let cover = optionalArt(gameHub.cover, size: .backdrop)
            guard let wanted = gameHub.logo else {
                return await cover.map { GameArtLayers(cover: $0, logo: nil) }
            }
            async let logo = optionalArt(wanted, size: .logo)
            guard let cover = await cover, let logo = await logo else {
                return nil
            }
            return GameArtLayers(cover: cover, logo: logo)
        }
    }

    /// The layers of a game's detail art when every one is already decoded.
    ///
    /// - Parameter art: The art's addresses.
    /// - Returns: `nil` when any layer the art needs is not held.
    nonisolated func heldLayers(_ art: GameDetails.Art) -> GameArtLayers? {
        switch art {
        case .layered(let layered):
            guard let background = held(layered.background, size: .backdrop),
                  let hero = held(layered.hero, size: .hero),
                  let logo = held(layered.logo, size: .logo) else {
                return nil
            }
            return GameArtLayers(background: background, hero: hero, logo: logo)
        case .gameHub(let gameHub):
            guard let cover = held(gameHub.cover, size: .backdrop) else {
                return nil
            }
            guard let wanted = gameHub.logo else {
                return GameArtLayers(cover: cover, logo: nil)
            }
            return held(wanted, size: .logo).map { GameArtLayers(cover: cover, logo: $0) }
        }
    }

    /// Remembers the detail art of a product so a later screen can draw it from memory.
    ///
    /// - Parameters:
    ///   - art: The art's addresses.
    ///   - product: The product the art belongs to.
    nonisolated func remember(_ art: GameDetails.Art, for product: ProductID) {
        remembered.withLock {
            $0[product] = art
        }
    }

    /// The layers of a product's remembered art when every one is already decoded.
    ///
    /// - Parameter product: The product.
    /// - Returns: `nil` when no art was remembered or a layer is not held.
    nonisolated func knownLayers(_ product: ProductID) -> GameArtLayers? {
        remembered.withLock {
            $0[product]
        }.flatMap(heldLayers)
    }

    private nonisolated func held(_ raw: String, size: GameArtSize) -> CGImage? {
        URL.secureArtwork(raw).flatMap { heldGameArt($0, size: size) }
    }

    private func optionalArt(_ raw: String, size: GameArtSize) async -> CGImage? {
        guard let url = URL.secureArtwork(raw) else {
            return nil
        }
        return try? await gameArt(url, size: size)
    }

    private func image(
        _ key: Key,
        box: ArtworkBox,
        load: @escaping @Sendable (ArtworkBox) async throws -> CGImage
    ) async throws -> CGImage {
        let cache = shelves.cache(key.shelf)
        if let image = cache.image(for: key.url, box: box) {
            return image
        }
        let waiter = UUID()
        let task: Task<CGImage, Error>
        if var entry = pending[key], entry.box.covers(box) {
            entry.waiters.insert(waiter)
            pending[key] = entry
            task = entry.task
        } else {
            let target = cache.box(for: key.url).map { box.union($0) } ?? box
            task = Task.detached(priority: .userInitiated) {
                let image = try await load(target)
                try Task.checkCancellation()
                cache.store(image, for: key.url, box: target)
                return image
            }
            pending[key] = Pending(task: task, box: target, waiters: [waiter])
        }
        return try await withTaskCancellationHandler {
            defer {
                leave(key, task: task, waiter: waiter)
            }
            return try await task.value
        } onCancel: {
            Task {
                await self.leave(key, task: task, waiter: waiter)
            }
        }
    }

    private func leave(_ key: Key, task: Task<CGImage, Error>, waiter: UUID) {
        guard var entry = pending[key], entry.task == task, entry.waiters.remove(waiter) != nil else {
            return
        }
        if entry.waiters.isEmpty {
            pending[key] = nil
            task.cancel()
        } else {
            pending[key] = entry
        }
    }
}

/// Turns fetched artwork into images sized for where they are drawn: image bytes decoded to fill a box, and
/// a still read from a trailer.
enum ArtworkDecoder {
    /// Decodes image bytes to fill a box, applying the image's orientation.
    ///
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - box: The box the image fills.
    /// - Returns: The decoded image, or `nil` when the bytes are not an image.
    static func decode(_ data: Data, box: ArtworkBox) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let orientation = properties?[kCGImagePropertyOrientation] as? UInt32,
           (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: box.fillPixelSize(sourceWidth: width, sourceHeight: height),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    /// Reads one frame five seconds into a trailer, fitted to a box.
    ///
    /// - Parameters:
    ///   - url: The trailer's address.
    ///   - box: The box the frame fits.
    /// - Returns: The frame.
    /// - Throws: When the trailer cannot be read.
    @Sendable static func trailerStill(_ url: URL, box: ArtworkBox) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: box.width, height: box.height)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        return try await generator.image(at: CMTime(seconds: 5, preferredTimescale: 600)).image
    }

    /// Decodes image bytes no larger than a limit, unless the task was cancelled.
    ///
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - limit: The largest byte count decoded.
    ///   - box: The box the image fills.
    /// - Returns: The decoded image.
    /// - Throws: `CancellationError` when the task was cancelled, or `URLError(.cannotDecodeContentData)` when
    ///   the bytes are too many or not an image.
    static func decoded(_ data: Data, limit: Int, box: ArtworkBox) throws -> CGImage {
        try Task.checkCancellation()
        guard data.count <= limit, let image = decode(data, box: box) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }
}

/// A bounded in-memory cache of decoded images, keyed by URL and the box each was decoded for.
///
/// An entry answers a request only when its box covers the box asked for, and a smaller decode never replaces
/// a larger one. Lookups are thread-safe, so views read it synchronously while the pipeline fills it.
public final class ArtworkCache: @unchecked Sendable {
    private final class Entry {
        let image: CGImage
        let box: ArtworkBox

        init(image: CGImage, box: ArtworkBox) {
            self.image = image
            self.box = box
        }
    }

    private let entries = NSCache<NSURL, Entry>()
    private let lock = NSLock()
    private let held = NSHashTable<Entry>.weakObjects()

    /// Creates a cache.
    ///
    /// - Parameters:
    ///   - costLimit: The decoded bytes the cache holds before it evicts.
    ///   - countLimit: The images the cache holds before it evicts.
    public init(costLimit: Int, countLimit: Int) {
        entries.totalCostLimit = costLimit
        entries.countLimit = countLimit
    }

    /// The decoded images still alive, in the cache or held by a view.
    public var count: Int {
        lock.withLock {
            held.allObjects.count
        }
    }

    /// Drops every image.
    public func removeAll() {
        entries.removeAllObjects()
        lock.withLock {
            held.removeAllObjects()
        }
    }

    /// The image held for a URL.
    ///
    /// - Parameters:
    ///   - url: The image's URL.
    ///   - box: The box the image must cover, or `nil` for any decode.
    /// - Returns: `nil` when no image is held or the held one is too small.
    public func image(for url: URL, box: ArtworkBox? = nil) -> CGImage? {
        guard let entry = entries.object(forKey: url as NSURL) else {
            return nil
        }
        if let box, !entry.box.covers(box) {
            return nil
        }
        return entry.image
    }

    /// The box the image held for a URL was decoded for.
    ///
    /// - Parameter url: The image's URL.
    /// - Returns: `nil` when no image is held.
    public func box(for url: URL) -> ArtworkBox? {
        entries.object(forKey: url as NSURL)?.box
    }

    /// Holds an image unless a decode at least as large is already held.
    ///
    /// - Parameters:
    ///   - image: The decoded image.
    ///   - url: The image's URL.
    ///   - box: The box it was decoded for.
    public func store(_ image: CGImage, for url: URL, box: ArtworkBox) {
        if let existing = entries.object(forKey: url as NSURL), existing.box.covers(box) {
            return
        }
        let entry = Entry(image: image, box: box)
        entries.setObject(entry, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        lock.withLock {
            held.add(entry)
        }
    }
}
