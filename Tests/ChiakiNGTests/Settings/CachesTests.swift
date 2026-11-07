import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiCore
import ChiakiCoreBridge
@testable import ChiakiFeatures
import ChiakiModels
@testable import ChiakiNG
import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private let librariesCache = CacheKind.libraries
private let imagesCache = CacheKind.images
private let detailsCache = CacheKind.gameDetails
private let owner = Data([40, 0, 0, 0, 0, 0, 0, 0])
private let stored = Date(timeIntervalSince1970: 1_700_000_000)
private let summaries = [
    CacheSummary(id: librariesCache, entries: 1, bytes: 2048),
    CacheSummary(id: imagesCache, entries: 0, bytes: 0)
]
private let library = CacheEntry(
    cache: librariesCache, account: owner, bytes: 2048, storedAt: stored,
    expiresAt: stored.addingTimeInterval(86400)
)

private final class Cleared: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CacheClearing] = []

    func add(_ clearing: CacheClearing) {
        lock.withLock {
            held.append(clearing)
        }
    }

    var all: [CacheClearing] {
        lock.withLock {
            held
        }
    }
}

@MainActor @Test func cachesListTheirCountsAndOpenTheirEntries() async {
    let store = TestStore(initialState: CachesReducer.State()) {
        CachesReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.cacheSummaries = { summaries }
        $0.catalog.cacheEntries = { _ in [library] }
        $0.catalog.clearCache = { _ in }
        $0.catalog.cacheAccountNames = { [owner: "Player"] }
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.loaded(UUID(0), summaries, [owner: "Player"], 0)) {
        $0.summaries = summaries
        $0.accountNames = [owner: "Player"]
        $0.phase = .ready
    }
    #expect(store.state.holdsAnything)
    await store.send(.open(librariesCache)) {
        $0.entries = .loading(librariesCache, UUID(1))
    }
    await store.receive(.entriesLoaded(UUID(1), [library])) {
        $0.entries = .shown(librariesCache, [library])
    }
    await store.send(.close) {
        $0.entries = .closed
    }
}

@MainActor @Test func cachesClearOnlyBehindAConfirmationAndThenReload() async {
    let cleared = Cleared()
    var state = CachesReducer.State()
    state.summaries = summaries
    state.accountNames = [owner: "Player"]
    state.entries = .shown(librariesCache, [library])
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CachesReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.cacheSummaries = { summaries }
        $0.catalog.cacheEntries = { _ in [library] }
        $0.catalog.clearCache = { cleared.add($0) }
        $0.catalog.cacheAccountNames = { [owner: "Player"] }
    }
    await store.send(.askClear(.one(librariesCache)))
    await store.receive(.delegate(.confirmClear(.one(librariesCache))))
    #expect(cleared.all.isEmpty)
    await store.send(.askClear(.one(librariesCache)))
    await store.receive(.delegate(.confirmClear(.one(librariesCache))))
    await store.send(.clear(.one(librariesCache))) {
        $0.phase = .clearing(UUID(0))
    }
    await store.receive(.cleared(UUID(0))) {
        $0.phase = .loading(UUID(1))
    }
    await store.receive(.loaded(UUID(1), summaries, [owner: "Player"], 0)) {
        $0.phase = .ready
        $0.entries = .loading(librariesCache, UUID(2))
    }
    await store.receive(.entriesLoaded(UUID(2), [library])) {
        $0.entries = .shown(librariesCache, [library])
    }
    #expect(cleared.all == [.one(librariesCache)])
    await store.send(.askClear(.all))
    await store.receive(.delegate(.confirmClear(.all)))
    await store.send(.clear(.all)) {
        $0.phase = .clearing(UUID(3))
    }
    await store.receive(.cleared(UUID(3))) {
        $0.phase = .loading(UUID(4))
    }
    await store.receive(.loaded(UUID(4), summaries, [owner: "Player"], 0)) {
        $0.phase = .ready
        $0.entries = .loading(librariesCache, UUID(5))
    }
    await store.receive(.entriesLoaded(UUID(5), [library])) {
        $0.entries = .shown(librariesCache, [library])
    }
    #expect(cleared.all == [.one(librariesCache), .all])
}

@MainActor @Test func cacheFailuresAreShownAndLeaveTheListAlone() async {
    var state = CachesReducer.State()
    state.summaries = summaries
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CachesReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.cacheSummaries = { throw CatalogFailure(reason: .storage) }
        $0.catalog.cacheEntries = { _ in throw CatalogFailure(reason: .storage) }
        $0.catalog.clearCache = { _ in throw CatalogFailure(reason: .storage) }
        $0.catalog.cacheAccountNames = { [:] }
    }
    await store.send(.open(imagesCache)) {
        $0.entries = .loading(imagesCache, UUID(0))
    }
    await store.receive(.entriesFailed(UUID(0), .settingsCachesEntriesFailed)) {
        $0.entries = .failed(imagesCache, .settingsCachesEntriesFailed)
    }
    await store.send(.close) {
        $0.entries = .closed
    }
    await store.send(.askClear(.all))
    await store.receive(.delegate(.confirmClear(.all)))
    await store.send(.clear(.all)) {
        $0.phase = .clearing(UUID(1))
    }
    await store.receive(.failed(UUID(1), .settingsCachesClearFailed)) {
        $0.phase = .failed(.settingsCachesClearFailed)
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(2))
    }
    await store.receive(.failed(UUID(2), .settingsCachesReadFailed)) {
        $0.phase = .failed(.settingsCachesReadFailed)
    }
    #expect(store.state.summaries == summaries)
}

@Test func everyCoreCacheHasItsOwnName() {
    let all = CacheKind.allCases
    #expect(all.count == 8)
    #expect(Set(all.map { String(localized: $0.title) }).count == 8)
    #expect(String(localized: CacheKind.forSaleTitles.title) == "Available to buy")
    #expect(String(localized: CacheKind.playedGames.title) == "Played games")
    #expect(String(localized: imagesCache.title) == "Images")
    #expect(SettingsRoute.allCases.contains(.caches))
    #expect(String(localized: CacheClearing.one(imagesCache).confirmation.title) == "Clear Images?")
    #expect(CacheClearing.all.confirmation.tone == .destructive)
}

@Test func cacheEntriesSayWhatTheyAreAboutWithoutIdentifiers() {
    let locale = Locale(identifier: "en_GB")
    let saved = CacheEntryPresentation(
        library,
        accountNames: [owner: "Player"],
        locale: locale,
        timeZone: .gmt
    )
    #expect(saved.subjects == [.init(kind: .account, value: "Player")])
    #expect(saved.subjects.map { String(localized: $0.label) } == ["Account"])
    #expect(saved.size == "2.0 KB")
    #expect(saved.stored == "14 Nov 2023 at 22:13")
    #expect(saved.expires == "15 Nov 2023 at 22:13")
    let unsaved = CacheEntryPresentation(library, accountNames: [:], locale: locale, timeZone: .gmt)
    #expect(unsaved.subjects == [.init(kind: .account, value: "Unsaved account")])
    let details = CacheEntryPresentation(
        CacheEntry(
            cache: detailsCache, locale: "en-GB", productID: "EP9000-PPSA01968_00-DEATHSTRANDINGEU",
            bytes: 12,
            storedAt: stored
        ),
        accountNames: [:], locale: locale, timeZone: .gmt
    )
    #expect(details.subjects.map { String(localized: $0.label) } == ["Store region", "Product"])
    #expect(details.expires == "No expiry")
    let image = CacheEntryPresentation(
        CacheEntry(
            cache: imagesCache, imageURL: "https://image.api.playstation.com/logo.png", bytes: 7,
            storedAt: stored
        ),
        accountNames: [:], locale: locale, timeZone: .gmt
    )
    #expect(image.subjects == [.init(kind: .image, value: "https://image.api.playstation.com/logo.png")])
    #expect(image.subjects.map { String(localized: $0.label) } == ["Image"])
    let unreadable = CacheEntryPresentation(
        CacheEntry(cache: librariesCache, bytes: 2, storedAt: stored), accountNames: [:]
    )
    #expect(unreadable.subjects == [.init(kind: .record, value: "Unreadable")])
    #expect(unreadable.subjects.map { String(localized: $0.label) } == ["Record"])
    let summary = CacheSummaryPresentation(summaries[0])
    #expect(String(localized: summary.title) == "Libraries")
    #expect(String(localized: summary.entries) == "1 entry")
    #expect(summary.size == "2.0 KB")
    #expect(CacheSummaryPresentation(summaries[1]).isEmpty)
}

private func coverPixel() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let image = context?.makeImage() else {
        fatalError("no bitmap context")
    }
    return image
}

@Test func decodedArtworkCountsAndClearsEveryInMemoryCache() throws {
    let pipeline = ArtworkPipeline(shelves: ArtworkPipeline.Shelves(
        thumbnails: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8),
        heroes: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8),
        gameArt: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8),
        trailers: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8)
    )) { _ in
        throw URLError(.cancelled)
    }
    let artwork = CatalogClient.testValue.runningArtwork(on: pipeline)
    let box = ArtworkBox(width: 128, height: 128)
    let first = try #require(URL(string: "https://image.api.playstation.com/one.png"))
    let second = try #require(URL(string: "https://image.api.playstation.com/two.png"))
    pipeline.shelves.thumbnails.store(coverPixel(), for: first, box: box)
    pipeline.shelves.thumbnails.store(coverPixel(), for: second, box: box)
    pipeline.shelves.gameArt.store(coverPixel(), for: first, box: box)
    #expect(artwork.decodedCount() == 3)
    artwork.clearDecoded()
    #expect(artwork.decodedCount() == 0)
    #expect(pipeline.shelves.thumbnails.image(for: first) == nil)
    #expect(pipeline.shelves.gameArt.image(for: first) == nil)
}

@Test func theRetiredCoverStoreIsRemovedOnce() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("retired-covers-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("fsCachedData", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data(repeating: 7, count: 4096).write(to: directory.appendingPathComponent("fsCachedData/blob"))
    #expect(RetiredCoverStore.remove(at: directory))
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(!RetiredCoverStore.remove(at: directory))
    #expect(RetiredCoverStore.directory.lastPathComponent == "CloudArtwork")
}

@Test func theImagesRowAloneReportsDecodedArtwork() {
    let images = CacheSummaryPresentation(
        CacheSummary(id: imagesCache, entries: 4, bytes: 3 * 1_048_576), decoded: 12
    )
    #expect(String(localized: images.title) == "Images" && String(localized: images.entries) == "4 entries")
    #expect(images.size == "3.0 MB")
    #expect(images.memory.map { String(localized: $0) } == "12 in memory" && !images.isEmpty)
    let libraries = CacheSummaryPresentation(summaries[0], decoded: 12)
    #expect(libraries.memory == nil)
    let emptyShelf = CacheSummary(id: imagesCache, entries: 0, bytes: 0)
    #expect(!CacheSummaryPresentation(emptyShelf, decoded: 1).isEmpty)
    #expect(CacheSummaryPresentation(emptyShelf, decoded: 0).isEmpty)
}

@MainActor @Test func theImagesRowCountsDecodedArtworkAndItsClearEmptiesBoth() async {
    let held = [
        CacheSummary(id: librariesCache, entries: 1, bytes: 2048),
        CacheSummary(id: imagesCache, entries: 4, bytes: 3 * 1_048_576)
    ]
    let emptied = [
        CacheSummary(id: librariesCache, entries: 1, bytes: 2048),
        CacheSummary(id: imagesCache, entries: 0, bytes: 0)
    ]
    let cleared = Cleared()
    let decoded = LockIsolated(12)
    let store = TestStore(initialState: CachesReducer.State()) {
        CachesReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.cacheSummaries = {
            cleared.all.isEmpty
                ? held
                : emptied
        }
        $0.catalog.cacheEntries = { _ in [] }
        $0.catalog.clearCache = { cleared.add($0) }
        $0.catalog.cacheAccountNames = { [:] }
        $0.catalog.decodedCount = {
            decoded.value
        }
        $0.catalog.clearDecoded = {
            decoded.setValue(0)
        }
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.loaded(UUID(0), held, [:], 12)) {
        $0.summaries = held
        $0.decodedArtwork = 12
        $0.phase = .ready
    }
    let memory = CacheSummaryPresentation(held[1], decoded: store.state.decodedArtwork).memory
    #expect(memory.map { String(localized: $0) } == "12 in memory")
    await store.send(.askClear(.one(imagesCache)))
    await store.receive(.delegate(.confirmClear(.one(imagesCache))))
    await store.send(.clear(.one(imagesCache))) {
        $0.phase = .clearing(UUID(1))
    }
    await store.receive(.cleared(UUID(1))) {
        $0.phase = .loading(UUID(2))
    }
    await store.receive(.loaded(UUID(2), emptied, [:], 0)) {
        $0.summaries = emptied
        $0.decodedArtwork = 0
        $0.phase = .ready
    }
    #expect(cleared.all == [.one(imagesCache)])
    #expect(CacheSummaryPresentation(store.state.summaries[1], decoded: store.state.decodedArtwork).isEmpty)
}

@MainActor @Test func clearingAnotherCacheKeepsDecodedArtworkAndClearAllEmptiesIt() async {
    let decoded = LockIsolated(5)
    let store = TestStore(initialState: CachesReducer.State()) {
        CachesReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.cacheSummaries = { summaries }
        $0.catalog.cacheEntries = { _ in [] }
        $0.catalog.clearCache = { _ in }
        $0.catalog.cacheAccountNames = { [:] }
        $0.catalog.decodedCount = {
            decoded.value
        }
        $0.catalog.clearDecoded = {
            decoded.setValue(0)
        }
    }
    store.exhaustivity = .off
    await store.send(.askClear(.one(librariesCache)))
    await store.receive(.delegate(.confirmClear(.one(librariesCache))))
    await store.send(.clear(.one(librariesCache)))
    await store.receive(.cleared(UUID(0)))
    await store.receive(.loaded(UUID(1), summaries, [:], 5))
    #expect(decoded.value == 5)
    await store.send(.askClear(.all))
    await store.receive(.delegate(.confirmClear(.all)))
    await store.send(.clear(.all))
    await store.receive(.cleared(UUID(2)))
    await store.receive(.loaded(UUID(3), summaries, [:], 0))
    #expect(decoded.value == 0)
    #expect(store.state.decodedArtwork == 0)
}
