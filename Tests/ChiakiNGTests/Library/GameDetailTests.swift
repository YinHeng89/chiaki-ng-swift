import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiCoreBridge
@testable import ChiakiFeatures
import ChiakiModels
@testable import ChiakiNG
import ComposableArchitecture
import CoreGraphics
import Foundation
import ImageIO
import MenuFocus
import SwiftUI
import Testing

private let productText = "EP9000-PPSA01968_00-DEATHSTRANDINGEU"
private let product = ProductID(rawValue: productText)!
private let anotherProduct = ProductID(rawValue: "another-product")!
private let otherProduct = ProductID(rawValue: "other")!
private let account = UUID()
private let art = GameDetails.LayeredArt(
    background: "https://image.api.playstation.com/background.png",
    hero: "https://image.api.playstation.com/hero.png",
    logo: "https://image.api.playstation.com/logo.png"
)

private let cover = GameDetails.GameHubArt(
    cover: "https://image.api.playstation.com/cover.png", logo: "https://image.api.playstation.com/logo.png"
)

private func pixel() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let image = context?.makeImage() else {
        fatalError("no bitmap context")
    }
    return image
}

private final class Held: @unchecked Sendable {
    private let lock = NSLock()
    private var layers: GameArtLayers?

    var value: GameArtLayers? {
        get {
            lock.withLock {
                layers
            }
        }
        set {
            lock.withLock {
                layers = newValue
            }
        }
    }
}

@MainActor private func detailStore(
    details: Result<GameDetails, CatalogFailure>, layers: GameArtLayers?, held: Held = Held(),
    state: GameDetailFeature.State = .init()
) -> TestStoreOf<GameDetailFeature> {
    TestStore(initialState: state) {
        GameDetailFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.gameDetails = { _, _ in details }
        $0.catalog.artLayers = { _ in layers }
        $0.catalog.heldArtLayers = { _ in held.value }
    }
}

@MainActor @Test func anUnknownGameShowsTheLoaderAndThenTheLayeredView() async {
    let details = GameDetails(layeredArt: art, publisher: "Sony Interactive Entertainment")
    let layers = GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
    let store = detailStore(details: .success(details), layers: layers)
    #expect(store.state.shown(for: product) == .card)
    await store.send(.open(account, product)) {
        $0.phase = .loadingDetails(product, UUID(0))
    }
    #expect(store.state.shown(for: product) == .loading)
    await store.receive(.detailsLoaded(UUID(0), .success(details))) {
        $0.known[product] = .layered(details)
        $0.phase = .loadingArt(product, UUID(0), details)
    }
    #expect(store.state.shown(for: product) == .loading)
    await store.receive(.artLoaded(UUID(0), layers)) {
        $0.arrival = .afterLoader
        $0.phase = .layered(product, details, layers)
    }
    #expect(store.state.shown(for: product)
        == .layered(.init(details: details, layers: layers, arrival: .afterLoader)))
    #expect(!GameDetailFeature.Shown.loading.isLayered && !GameDetailFeature.Shown.card.isLayered)
    #expect(store.state.shown(for: anotherProduct) == .card)
    await store.send(.open(account, product))
    #expect(GameDetailFeature.State(known: store.state.known).shown(for: product) == .card)
}

@MainActor @Test func anUnknownGameWithoutLayeredArtShowsTheLoaderAndThenTheCard() async {
    let details = GameDetails(screenshots: ["https://image.api.playstation.com/one.jpg"])
    let store = detailStore(details: .success(details), layers: nil)
    await store.send(.open(account, product)) {
        $0.phase = .loadingDetails(product, UUID(0))
    }
    #expect(store.state.shown(for: product) == .loading)
    await store.receive(.detailsLoaded(UUID(0), .success(details))) {
        $0.known[product] = .card
        $0.phase = .fallback(product, .noLayeredArt)
    }
    #expect(store.state.shown(for: product) == .card)
    let reopened = detailStore(
        details: .success(details), layers: nil, state: GameDetailFeature.State(known: store.state.known)
    )
    await reopened.send(.open(account, product)) {
        $0.phase = .fallback(product, .noLayeredArt)
    }
    #expect(reopened.state.shown(for: product) == .card)
}

@MainActor @Test func aKnownGameWithItsImagesInMemoryOpensDirectly() async {
    let details = GameDetails(layeredArt: art)
    let layers = GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
    let held = Held()
    var state = GameDetailFeature.State()
    state.known[product] = .layered(details)
    let store = detailStore(
        details: .failure(.init(reason: .unavailable)),
        layers: layers,
        held: held,
        state: state
    )
    await store.send(.open(account, product)) {
        $0.phase = .loadingArt(product, UUID(0), details)
    }
    #expect(store.state.shown(for: product) == .loading)
    await store.receive(.artLoaded(UUID(0), layers)) {
        $0.arrival = .afterLoader
        $0.phase = .layered(product, details, layers)
    }
    held.value = layers
    let reopened = detailStore(
        details: .success(details), layers: layers, held: held,
        state: GameDetailFeature.State(known: store.state.known)
    )
    await reopened.send(.open(account, product)) {
        $0.arrival = .direct
        $0.phase = .layered(product, details, layers)
    }
    #expect(reopened.state.shown(for: product)
        == .layered(.init(details: details, layers: layers, arrival: .direct)))
}

@MainActor @Test func aGameWithOnlyGameHubArtShowsTheLayeredView() async {
    let details = GameDetails(art: .gameHub(cover), publisher: "Sony Interactive Entertainment")
    let layers = GameArtLayers(cover: pixel(), logo: nil)
    let held = Held()
    let store = detailStore(details: .success(details), layers: layers, held: held)
    await store.send(.open(account, product)) {
        $0.phase = .loadingDetails(product, UUID(0))
    }
    await store.receive(.detailsLoaded(UUID(0), .success(details))) {
        $0.known[product] = .layered(details)
        $0.phase = .loadingArt(product, UUID(0), details)
    }
    await store.receive(.artLoaded(UUID(0), layers)) {
        $0.arrival = .afterLoader
        $0.phase = .layered(product, details, layers)
    }
    #expect(store.state.shown(for: product)
        == .layered(.init(details: details, layers: layers, arrival: .afterLoader)))
    held.value = layers
    let reopened = detailStore(
        details: .success(details), layers: layers, held: held,
        state: GameDetailFeature.State(known: store.state.known)
    )
    await reopened.send(.open(account, product)) {
        $0.arrival = .direct
        $0.phase = .layered(product, details, layers)
    }
}

@MainActor @Test func unansweredDetailsShowTheCardAndAreAskedAgainNextTime() async {
    let failure = CatalogFailure(reason: .unavailable, httpStatus: 503)
    let store = detailStore(details: .failure(failure), layers: nil)
    await store.send(.open(account, product)) {
        $0.phase = .loadingDetails(product, UUID(0))
    }
    await store.receive(.detailsLoaded(UUID(0), .failure(failure))) {
        $0.phase = .fallback(product, .unavailable)
    }
    #expect(store.state.shown(for: product) == .card)
    #expect(store.state.known.isEmpty)
    await store.send(.open(account, product)) {
        $0.phase = .loadingDetails(product, UUID(1))
    }
    await store.receive(.detailsLoaded(UUID(1), .failure(failure))) {
        $0.phase = .fallback(product, .unavailable)
    }
}

@MainActor @Test func aLayerThatFailsToLoadShowsTheCard() async {
    let details = GameDetails(layeredArt: art)
    let store = detailStore(details: .success(details), layers: nil)
    await store.send(.open(account, product)) {
        $0.phase = .loadingDetails(product, UUID(0))
    }
    await store.receive(.detailsLoaded(UUID(0), .success(details))) {
        $0.known[product] = .layered(details)
        $0.phase = .loadingArt(product, UUID(0), details)
    }
    await store.receive(.artLoaded(UUID(0), nil)) {
        $0.phase = .fallback(product, .artUnavailable)
    }
    #expect(store.state.shown(for: product) == .card)
}

@MainActor @Test func aGameOpenedWithoutAnAccountShowsTheCard() async {
    let store = detailStore(details: .success(GameDetails(layeredArt: art)), layers: nil)
    await store.send(.open(nil, product)) {
        $0.phase = .fallback(product, .noAccount)
    }
    #expect(store.state.shown(for: product) == .card)
}

@MainActor @Test func answersForAClosedOrReplacedGameAreIgnored() async {
    let details = GameDetails(layeredArt: art)
    let layers = GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
    var state = GameDetailFeature.State()
    state.phase = .loadingDetails(otherProduct, UUID(7))
    let store = detailStore(details: .success(details), layers: layers)
    await store.send(.detailsLoaded(UUID(3), .success(details)))
    await store.send(.artLoaded(UUID(3), layers))
    #expect(store.state.phase == .closed)
    let replaced = detailStore(details: .success(details), layers: layers, state: state)
    await replaced.send(.detailsLoaded(UUID(3), .success(details)))
    await replaced.send(.artLoaded(UUID(7), layers))
    #expect(replaced.state.phase == .loadingDetails(otherProduct, UUID(7)))
}

@MainActor @Test func anOpenedTrailerClosesWithItsViewerThePanelOrAnotherGame() async throws {
    let trailer = try #require(URL(string: "https://vulcan.dl.playstation.net/trailer.mp4"))
    let details = GameDetails(
        layeredArt: art, screenshots: ["https://image.api.playstation.com/one.jpg"], trailers: [trailer]
    )
    let layers = GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
    var state = GameDetailFeature.State()
    state.phase = .layered(product, details, layers)
    let store = detailStore(details: .success(GameDetails()), layers: nil, state: state)
    await store.send(.viewMedia(2))
    await store.send(.viewMedia(1)) {
        $0.media = .viewing(1)
    }
    #expect(store.state.viewed(for: product) == 1)
    #expect(store.state.viewed(for: anotherProduct) == nil)
    await store.send(.stepMedia(1))
    await store.send(.stepMedia(-1)) {
        $0.media = .viewing(0)
    }
    await store.send(.stepMedia(-1))
    await store.send(.stepMedia(1)) {
        $0.media = .viewing(1)
    }
    await store.send(.viewMedia(1)) {
        $0.media = .idle
    }
    await store.send(.viewMedia(1)) {
        $0.media = .viewing(1)
    }
    await store.send(.closeMedia) {
        $0.media = .idle
    }
    await store.send(.viewMedia(1)) {
        $0.media = .viewing(1)
    }
    await store.send(.open(account, anotherProduct)) {
        $0.media = .idle
        $0.phase = .loadingDetails(anotherProduct, UUID(0))
    }
    await store.receive(.detailsLoaded(UUID(0), .success(GameDetails()))) {
        $0.known[anotherProduct] = .card
        $0.phase = .fallback(anotherProduct, .noLayeredArt)
    }
    await store.send(.viewMedia(0))
}

@MainActor @Test func selectingAGameAsksForItsDetailsAndClosingForgetsThem() async {
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: productText, name: "Death Stranding", standing: .inLibrary)
    ])
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    await store.send(.select(productText)) {
        $0.destination = .gameDetail(GameDetailFeature.State(requested: product))
    }
    await store.receive(\.destination.presented.gameDetail.open) {
        $0.destination?.modify(\.gameDetail) { detail in
            detail.phase = .loadingDetails(product, UUID(0))
        }
    }
    await store.receive(\.destination.presented.gameDetail.detailsLoaded) {
        $0.destination?.modify(\.gameDetail) { detail in
            detail.known[product] = .card
            detail.phase = .fallback(product, .noLayeredArt)
        }
    }
    await store.send(.select(nil)) {
        $0.destination = nil
        $0.knownDetails[product] = .card
    }
    await store.send(.select(productText)) {
        $0.destination = .gameDetail(GameDetailFeature.State(known: [product: .card], requested: product))
    }
    await store.receive(\.destination.presented.gameDetail.open) {
        $0.destination?.modify(\.gameDetail) { detail in
            detail.phase = .fallback(product, .noLayeredArt)
        }
    }
}

@MainActor @Test func closeTappedShrinksEnlargedMediaBeforeItClosesTheDetail() async throws {
    let trailer = try #require(URL(string: "https://vulcan.dl.playstation.net/trailer.mp4"))
    let details = GameDetails(layeredArt: art, trailers: [trailer])
    let layers = GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: productText, name: "Death Stranding", standing: .inLibrary)
    ])
    state.phase = .ready
    state.selection = productText
    state.destination?.modify(\.gameDetail) { detail in
        detail.phase = .layered(product, details, layers)
        detail.media = .viewing(0)
    }
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    }
    await store.send(.closeTapped) {
        $0.destination?.modify(\.gameDetail) { detail in
            detail.media = .idle
        }
    }
    await store.send(.closeTapped) {
        $0.destination = nil
    }
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [String] = []

    func add(_ url: String) {
        lock.withLock {
            held.append(url)
        }
    }

    var urls: [String] {
        lock.withLock {
            held
        }
    }
}

private func png() throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, pixel(), nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func onlyScreenshotTilesAskForAResizedImage() throws {
    let url = try #require(URL(string: "https://image.api.playstation.com/one.jpg"))
    for size in [GameArtSize.backdrop, .hero, .logo, .icon, .enlarged] {
        #expect(size.candidates(for: url) == [url])
    }
    let resized = try #require(URL(string: "https://image.api.playstation.com/one.jpg?w=640"))
    #expect(GameArtSize.tile.candidates(for: url) == [resized, url])
    let versioned = try #require(URL(string: "https://image.api.playstation.com/one.jpg?v=2"))
    let versionedResized = try #require(URL(string: "https://image.api.playstation.com/one.jpg?v=2&w=640"))
    #expect(GameArtSize.tile.candidates(for: versioned) == [versionedResized, versioned])
}

private func artPipeline(_ answer: @escaping @Sendable (URL) throws -> Data) -> ArtworkPipeline {
    ArtworkPipeline(shelves: ArtworkPipeline.Shelves(
        thumbnails: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8),
        heroes: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8),
        gameArt: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8),
        trailers: ArtworkCache(costLimit: 1024 * 1024, countLimit: 8)
    )) { url in
        try answer(url)
    }
}

@Test func aRefusedResizedTileFallsBackToTheOriginalAndIsThenHeldInMemory() async throws {
    let raw = "https://image.api.playstation.com/one.jpg"
    let url = try #require(URL(string: raw))
    let image = try png()
    let asked = Asked()
    let pipeline = artPipeline { candidate in
        asked.add(candidate.absoluteString)
        guard candidate == url else {
            throw URLError(.fileDoesNotExist)
        }
        return image
    }
    #expect(pipeline.heldGameArt(url, size: .tile) == nil)
    _ = try await pipeline.gameArt(url, size: .tile)
    #expect(asked.urls == ["\(raw)?w=640", raw])
    #expect(pipeline.heldGameArt(url, size: .tile) != nil)
    _ = try await pipeline.gameArt(url, size: .tile)
    #expect(asked.urls.count == 2)
    _ = try await pipeline.gameArt(url, size: .backdrop)
    #expect(asked.urls.last == raw)
    let missing = try #require(URL(string: "https://image.api.playstation.com/missing.png"))
    await #expect(throws: URLError.self) {
        try await pipeline.gameArt(missing, size: .logo)
    }
}

@Test func layersAreKnownInMemoryOnlyWhenAllThreeAreHeld() async throws {
    let image = try png()
    let pipeline = artPipeline { _ in
        image
    }
    #expect(pipeline.heldLayers(.layered(art)) == nil)
    _ = try await pipeline.gameArt(#require(URL(string: art.background)), size: .backdrop)
    _ = try await pipeline.gameArt(#require(URL(string: art.hero)), size: .hero)
    #expect(pipeline.heldLayers(.layered(art)) == nil)
    _ = try await pipeline.gameArt(#require(URL(string: art.logo)), size: .logo)
    #expect(pipeline.heldLayers(.layered(art)) != nil)
}

@Test func gameHubArtIsKnownInMemoryOnlyWithItsCoverAndAnyLogo() async throws {
    let image = try png()
    let pipeline = artPipeline { _ in
        image
    }
    let unbranded = GameDetails.Art.gameHub(.init(cover: "https://image.api.playstation.com/bare.png"))
    #expect(pipeline.heldLayers(.gameHub(cover)) == nil)
    _ = try await pipeline.gameArt(#require(URL(string: cover.cover)), size: .backdrop)
    #expect(pipeline.heldLayers(.gameHub(cover)) == nil)
    _ = try await pipeline.gameArt(
        #require(URL(string: "https://image.api.playstation.com/logo.png")),
        size: .logo
    )
    let held = try #require(pipeline.heldLayers(.gameHub(cover)))
    #expect(held.layered == nil && held.logo != nil)
    #expect(pipeline.heldLayers(unbranded) == nil)
    _ = try await pipeline.gameArt(
        #require(URL(string: "https://image.api.playstation.com/bare.png")),
        size: .backdrop
    )
    let bare = try #require(pipeline.heldLayers(unbranded))
    #expect(bare.logo == nil && bare.layered == nil)
}

@Test func rememberedArtIsKnownOnlyOnceItsLayersAreDecoded() async throws {
    let image = try png()
    let pipeline = artPipeline { _ in
        image
    }
    let product = try #require(ProductID(rawValue: "UP0001-PPSA00001_00-0000000000000001"))
    #expect(pipeline.knownLayers(product) == nil)
    pipeline.remember(.layered(art), for: product)
    #expect(pipeline.knownLayers(product) == nil)
    #expect(await pipeline.layers(.layered(art)) != nil)
    #expect(pipeline.knownLayers(product) != nil)
}

@Test func coreDetailsBecomeTheViewsRatingsMediaAndFacts() throws {
    let trailer = try #require(URL(string: "https://vulcan.dl.playstation.net/trailer.mp4"))
    let details = GameDetails(
        layeredArt: art,
        screenshots: [
            "https://image.api.playstation.com/one.jpg",
            "https://image.api.playstation.com/two.jpg"
        ],
        trailers: [trailer],
        starRating: .init(
            average: 4.74,
            averageText: "4.74",
            ratings: 216_539,
            percentByStars: [2, 1, 3, 8, 86]
        ),
        ageRating: .init(
            authority: "PEGI", name: "PEGI 16", icon: "https://image.api.playstation.com/pegi.png",
            descriptors: ["Violence", "Bad Language"]
        ),
        publisher: "Sony Interactive Entertainment",
        releasedAt: Date(timeIntervalSince1970: 1_730_332_800),
        genres: ["Role Playing Games", "Action"]
    )
    let shown = GameDetailPresentation(details, locale: Locale(identifier: "en_GB"), timeZone: .gmt)
    let rating = try #require(shown.rating)
    #expect(rating.average == "4.74")
    #expect(rating.filledStars == 5)
    #expect(rating.count == "216,539 ratings")
    #expect(rating.bars.map(\.stars) == [5, 4, 3, 2, 1])
    #expect(rating.bars.map(\.percent) == [86, 8, 3, 1, 2])
    #expect(shown.age == .init(
        icon: "https://image.api.playstation.com/pegi.png", name: "PEGI 16",
        descriptors: "Violence, Bad Language"
    ))
    #expect(shown.media == [
        .screenshot("https://image.api.playstation.com/one.jpg"),
        .screenshot("https://image.api.playstation.com/two.jpg"), .trailer(trailer)
    ])
    #expect(shown.facts == [
        .init(label: "Publisher", value: "Sony Interactive Entertainment"),
        .init(label: "Released", value: "31 October 2024"),
        .init(label: "Genres", value: "Role Playing Games, Action")
    ])
    #expect(shown.showsRatingBand)
}

@Test func partsTheCoreHasNoDataForAreLeftOut() {
    let bare = GameDetailPresentation(GameDetails(layeredArt: art))
    #expect(bare.rating == nil)
    #expect(bare.age == nil)
    #expect(bare.media.isEmpty)
    #expect(bare.facts.isEmpty)
    #expect(!bare.showsRatingBand)
    let unrated = GameDetailPresentation(GameDetails(
        starRating: .init(average: 0, averageText: "", ratings: 0, percentByStars: [0, 0, 0, 0, 0]),
        ageRating: .init(name: ""), genres: ["Action"]
    ))
    #expect(unrated.rating == nil)
    #expect(unrated.age == nil)
    #expect(unrated.facts.map(\.label) == ["Genres"])
    let single = GameDetailPresentation(
        GameDetails(starRating: .init(
            average: 3.5,
            averageText: "",
            ratings: 1,
            percentByStars: [0, 0, 0, 100, 0]
        )),
        locale: Locale(identifier: "en_GB")
    )
    #expect(single.rating?.average == "3.50")
    #expect(single.rating?.count == "1 rating")
    #expect(single.rating?.filledStars == 4)
    #expect(single.age == nil && single.showsRatingBand)
}

@Test func layeredDetailFocusFollowsTheHeaderAndMediaRows() {
    let actions = ["play", "store"]
    let media = ["m0", "m1", "m2"]
    func next(_ current: String?, _ direction: MenuMoveDirection) -> String {
        GameDetailFocusGraph.next(
            from: current,
            direction: direction,
            close: "close",
            actions: actions,
            media: media
        )
    }
    #expect(next(nil, .down) == "play")
    #expect(next("close", .down) == "play")
    #expect(next("close", .left) == "play")
    #expect(next("close", .up) == "close")
    #expect(next("play", .right) == "store")
    #expect(next("store", .right) == "store")
    #expect(next("play", .left) == "play")
    #expect(next("store", .up) == "close")
    #expect(next("store", .down) == "m0")
    #expect(next("m0", .right) == "m1")
    #expect(next("m2", .right) == "m2")
    #expect(next("m1", .left) == "m0")
    #expect(next("m1", .up) == "play")
    #expect(next("m1", .down) == "m1")
    #expect(next("gone", .down) == "play")
    #expect(GameDetailFocusGraph.next(
        from: "close", direction: .down, close: "close", actions: [], media: media
    ) == "m0")
    #expect(GameDetailFocusGraph.next(
        from: "m0", direction: .up, close: "close", actions: [], media: media
    ) == "close")
    #expect(GameDetailFocusGraph.next(
        from: "close", direction: .down, close: "close", actions: [String](), media: []
    ) == "close")
}

@Test func revealStepsFollowTheApprovedOrder() {
    #expect(GameDetailRevealStep.logo.hiddenBlur == 8)
    #expect(GameDetailRevealStep.backdrop.hiddenScale == 1.08)
    #expect(GameDetailRevealStep.hero.hiddenOffset == .zero)
    #expect(GameDetailRevealStep.hero.hiddenScale == 1)
    #expect(GameDetailRevealStep.details.hiddenOffset == CGSize(width: 0, height: 22))
    #expect(GameDetailRevealStep.media.hiddenBlur == 0)
    let order: [GameDetailRevealStep] = [
        .backdrop,
        .hero,
        .logo,
        .facts,
        .actions,
        .ratings,
        .media,
        .details
    ]
    #expect(order.map(\.delay) == [0, 0.35, 0.95, 1.45, 1.6, 1.8, 2, 2.15])
    #expect(GameDetailGrowth.duration == 0.4)
    #expect(GameDetailGrowth.cardFade == 0.25)
}

@Test func anAgeRatingNameReadsWithoutUnderscores() {
    let details = GameDetails(
        ageRating: .init(authority: "PEGI", name: "PEGI_3", descriptors: ["In-Game Purchases"])
    )
    let shown = GameDetailPresentation(details, locale: Locale(identifier: "en_GB"), timeZone: .gmt)
    #expect(shown.age == .init(icon: nil, name: "PEGI 3", descriptors: "In-Game Purchases"))
}

private struct LayeredDetailHost: View {
    let store: StoreOf<CloudLibraryFeature>
    let game: CloudGame
    @MenuFocusState private var focus: CloudLibraryFocus?

    var body: some View {
        CloudGameDetail(
            game: game, accountID: account, height: 860, store: store, focus: $focus,
            heldFocus: { nil }
        )
    }
}

@MainActor @Test func layeredDetailRendersWithoutAWindow() {
    let game = CloudGame(
        productId: productText, name: "Death Stranding",
        imageUrl: "https://image.api.playstation.com/cover.png",
        platform: "PS5", isOwned: true, plusCatalog: false
    )
    var state = CloudLibraryFeature.State()
    state.selection = productText
    state.destination?.modify(\.gameDetail) { detail in
        detail.phase = .layered(
            product,
            GameDetails(layeredArt: art, publisher: "Sony Interactive Entertainment"),
            GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
        )
    }
    let store = Store(initialState: state) {
        CloudLibraryFeature()
    }
    let renderer = ImageRenderer(content: LayeredDetailHost(store: store, game: game).frame(
        width: 1200,
        height: 900
    ))
    #expect(renderer.cgImage != nil)
}

@MainActor @Test func gameHubDetailRendersWithoutAWindow() {
    let game = CloudGame(
        productId: productText, name: "Death Stranding",
        imageUrl: "https://image.api.playstation.com/cover.png",
        platform: "PS5", isOwned: true, plusCatalog: false
    )
    for layers in [GameArtLayers(cover: pixel(), logo: pixel()), GameArtLayers(cover: pixel(), logo: nil)] {
        var state = CloudLibraryFeature.State()
        state.selection = productText
        state.destination?.modify(\.gameDetail) { detail in
            detail.phase = .layered(product, GameDetails(art: .gameHub(cover)), layers)
        }
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        }
        let renderer = ImageRenderer(content: LayeredDetailHost(store: store, game: game).frame(
            width: 1200,
            height: 900
        ))
        #expect(renderer.cgImage != nil)
    }
}

@MainActor @Test func cloudLibraryRendersWithoutAWindow() {
    var state = CloudLibraryFeature.State()
    state.phase = .ready
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: (0..<30).map { index in
        CloudGame(
            productId: "game-\(index)", name: "Game \(index)", imageUrl: "https://image.example/\(index).png",
            platform: "PS5", isOwned: index.isMultiple(of: 2), plusCatalog: false
        )
    })
    state.gridShape = CloudGridShape(columns: 7, rows: 2)
    state.listing.resize(to: state.gridShape.size, keeping: nil)
    let store = Store(initialState: state) {
        CloudLibraryFeature()
    }
    let page = CloudLibraryView(store: store, height: 860)
        .frame(width: 1600, height: 1000)
    #expect(ImageRenderer(content: page).cgImage != nil)
}
