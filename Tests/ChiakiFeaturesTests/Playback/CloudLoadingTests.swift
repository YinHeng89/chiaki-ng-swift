import ChiakiModels
import ChiakiClients
import ComposableArchitecture
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChiakiFeatures

private let art = GameDetails.LayeredArt(
    background: "https://image.api.playstation.com/background.png",
    hero: "https://image.api.playstation.com/hero.png",
    logo: "https://image.api.playstation.com/logo.png"
)

private func layers() -> GameArtLayers {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let image = context?.makeImage() else {
        fatalError("no bitmap context")
    }
    return GameArtLayers(background: image, hero: image, logo: image)
}

private let session = StreamSessionID(uuid: UUID(0))

private let offer = CloudDatacenterLaunchOffer(
    entries: [.init(name: "fraa", rttMs: 1), .init(name: "lona", rttMs: 9)], timeoutSeconds: 2
)

private func source() -> StreamSource {
    .cloud(CloudStreamRequest(
        profile: ProfileID(uuid: UUID()),
        title: CloudStreamTitle(
            product: ProductID(rawValue: "EP9000-PPSA01968_00-DEATHSTRANDINGEU")!,
            name: "Death Stranding",
            service: .psCloud
        )
    ))
}

@MainActor private func loadingStore(
    known: GameArtLayers?,
    details: GameDetails,
    fetched: GameArtLayers?,
    clock: TestClock<Duration> = TestClock()
) -> TestStoreOf<StreamFeature> {
    StreamSessionCalls().store(clock: clock) {
        $0.catalog.gameDetails = { _, _ in .success(details) }
        $0.catalog.artLayers = { _ in fetched }
        $0.catalog.heldArtLayers = { _ in nil }
        $0.catalog.knownArtLayers = { _ in known }
    }
}

private func chrome(_ state: StreamFeature.State) -> CloudLoadingChrome {
    state.session.stage?.datacenterChoice?.offer == nil
        ? .status
        : .picker
}

@MainActor @Test func aGameWhoseThreeLayersAreKnownLoadsOnTheLayeredScreen() async {
    let known = layers()
    let clock = TestClock()
    let store = loadingStore(known: known, details: GameDetails(), fetched: nil, clock: clock)
    await store.send(.start(source()))
    #expect(store.state.loading == .shown(.layered(known)))
    await store.send(.event(session, .cloudStep(.connecting)))
    await store.send(.event(session, .firstFrame))
    #expect(store.state.loading == .leaving(.layered(known)))
    await clock.advance(by: .milliseconds(1699))
    #expect(store.state.loading.isLeaving)
    await clock.advance(by: .milliseconds(1))
    await store.receive(.loadingLeft(session))
    #expect(store.state.loading == .hidden)
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func aGameMissingALayerStaysOnTheCardAndTheCardAlsoLeaves() async {
    let clock = TestClock()
    let store = loadingStore(
        known: nil, details: GameDetails(screenshots: ["https://image.api.playstation.com/one.jpg"]),
        fetched: layers(), clock: clock
    )
    await store.send(.start(source()))
    #expect(store.state.loading == .shown(.card))
    await store.send(.event(session, .firstFrame))
    #expect(store.state.loading == .leaving(.card))
    await clock.advance(by: .milliseconds(600))
    await store.receive(.loadingLeft(session))
    #expect(store.state.loading == .hidden)
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func layersArrivingWhileLoadingSwitchToTheLayeredScreen() async {
    let fetched = layers()
    let store = loadingStore(known: nil, details: GameDetails(layeredArt: art), fetched: fetched)
    await store.send(.start(source()))
    await store.receive(.loadingArtArrived(session, fetched))
    #expect(store.state.loading == .shown(.layered(fetched)))
    await store.send(.loadingArtArrived(session, layers()))
    #expect(store.state.loading == .shown(.layered(fetched)))
    await store.send(.stop)
    #expect(store.state.loading == .hidden)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func gameHubArtArrivingWhileLoadingSwitchesToTheLayeredScreen() async throws {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    let image = try #require(context?.makeImage())
    let fetched = GameArtLayers(cover: image, logo: nil)
    let store = loadingStore(
        known: nil,
        details: GameDetails(art: .gameHub(.init(cover: "https://image.api.playstation.com/cover.png"))),
        fetched: fetched
    )
    await store.send(.start(source()))
    await store.receive(.loadingArtArrived(session, fetched))
    #expect(store.state.loading == .shown(.layered(fetched)))
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func theLoadingScreenDrawsGameHubArtWithoutAWindow() throws {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    let image = try #require(context?.makeImage())
    for art in [GameArtLayers(cover: image, logo: image), GameArtLayers(cover: image, logo: nil)] {
        let screen = CloudLayeredLoadingView(
            layers: art, title: "Death Stranding", status: "Connecting", leaving: false, cancel: {
            }
        )
        #expect(ImageRenderer(content: screen.frame(width: 1280, height: 720)).cgImage != nil)
    }
}

@MainActor @Test func layersArrivingAfterTheStreamIsReadyNeverSwitchTheScreen() async {
    let clock = TestClock()
    let store = loadingStore(known: nil, details: GameDetails(), fetched: nil, clock: clock)
    await store.send(.start(source()))
    await store.send(.event(session, .firstFrame))
    await store.send(.loadingArtArrived(session, layers()))
    #expect(store.state.loading == .leaving(.card))
    await clock.advance(by: .milliseconds(600))
    await store.receive(.loadingLeft(session))
    await store.send(.loadingArtArrived(session, layers()))
    #expect(store.state.loading == .hidden)
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func artAndExitsFromAnotherSessionAreIgnored() async {
    let store = loadingStore(known: nil, details: GameDetails(), fetched: nil)
    await store.send(.start(source()))
    let other = StreamSessionID(uuid: UUID(99))
    await store.send(.loadingArtArrived(other, layers()))
    await store.send(.loadingLeft(session))
    #expect(store.state.loading == .shown(.card))
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func aFailedAttemptHidesTheLoadingScreen() async {
    let store = loadingStore(known: layers(), details: GameDetails(), fetched: nil)
    await store.send(.start(source()))
    #expect(store.state.loading != .hidden)
    await store.send(.failed(session, .renderer))
    #expect(store.state.status == .failed)
    #expect(store.state.loading == .hidden)
}

@MainActor @Test func theDatacenterPickerKeepsTheLayeredStageAndWithdrawsTheStripAndLogo() async {
    let art = layers()
    let store = loadingStore(known: art, details: GameDetails(), fetched: nil)
    await store.send(.start(source()))
    await store.send(.event(session, .cloudStep(.findingServer)))
    #expect(chrome(store.state) == .status)
    await store.send(.event(session, .datacenterOffered(offer)))
    #expect(store.state.session.stage?.datacenterChoice == .offered(offer, remaining: 2))
    #expect(store.state.loading == .shown(.layered(art)))
    #expect(chrome(store.state) == .picker)
    #expect(CloudLoadingLayer.strip.isWithdrawn(for: .picker))
    #expect(CloudLoadingLayer.logo.isWithdrawn(for: .picker))
    for layer in [CloudLoadingLayer.backdrop, .hero, .shade] {
        #expect(!layer.isWithdrawn(for: .picker))
    }
    for layer in [CloudLoadingLayer.backdrop, .hero, .shade, .logo, .strip] {
        #expect(!layer.isWithdrawn(for: .status))
    }
    let selection = CloudDatacenterSelection(name: "fraa", rttMs: 1, automatic: false)
    await store.send(.event(session, .datacenterSelected(selection)))
    #expect(store.state.datacenter == selection)
    #expect(store.state.loading == .shown(.layered(art)))
    #expect(chrome(store.state) == .status)
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func anExpiredDatacenterCountdownReturnsTheStripWithoutEnteringAgain() async {
    let art = layers()
    let clock = TestClock()
    let store = loadingStore(known: art, details: GameDetails(), fetched: nil, clock: clock)
    await store.send(.start(source()))
    await store.send(.event(session, .cloudStep(.findingServer)))
    await store.send(.event(session, .datacenterOffered(offer)))
    await clock.advance(by: .seconds(1))
    await store.receive(.datacenterTick(session))
    #expect(store.state.session.stage?.datacenterChoice == .offered(offer, remaining: 1))
    #expect(chrome(store.state) == .picker)
    await clock.advance(by: .seconds(1))
    await store.receive(.datacenterTick(session))
    #expect(store.state.session.stage?.datacenterChoice == .expired)
    #expect(chrome(store.state) == .status)
    #expect(store.state.loading == .shown(.layered(art)))
    await store.send(.stop)
    await store.receive(.stopped(session, .left))
}

@MainActor @Test func layersArrivingBehindTheDatacenterPickerSwitchTheStageAndKeepThePicker() async {
    let art = layers()
    let store = loadingStore(known: nil, details: GameDetails(), fetched: nil)
    await store.send(.start(source()))
    await store.send(.event(session, .cloudStep(.findingServer)))
    await store.send(.event(session, .datacenterOffered(offer)))
    #expect(store.state.loading == .shown(.card))
    await store.send(.loadingArtArrived(session, art))
    #expect(store.state.loading == .shown(.layered(art)))
    #expect(chrome(store.state) == .picker)
    #expect(store.state.session.stage?.datacenterChoice?.offer == offer)
    await store.send(.stop)
    #expect(store.state.loading == .hidden)
    await store.receive(.stopped(session, .left))
    #expect(CloudLoadingLayer.chromeFade == 0.3)
}

@Test func theWaitLineKeepsTheCoresOrderOnOneLine() {
    var progress = OperationProgress(step: .launch(.migratingData))
    progress.migrationPercent = 0
    progress.wait = ProgressWait(
        reason: .dataMigration,
        nextTry: .milliseconds(11000)
    )
    progress.attempt = 2
    progress.elapsedMilliseconds = 15000
    let text = OperationProgressText(progress)
    let wait = CloudLoadingWait(text)
    #expect(wait.title == String(localized: text.title))
    #expect(wait.detail == text.details.map { String(localized: $0) }.joined(separator: ", "))
    #expect(!wait.detail.contains("\n"))
    #expect(text.details.count >= 3)
    #expect(wait.spoken == "\(String(localized: text.title)), \(wait.detail)")
    let bare =
        CloudLoadingWait(OperationProgressText(OperationProgress(step: .launch(.migratingData))))
    #expect(bare.detail.isEmpty)
    #expect(bare.spoken == bare.title)
}

@Test func theLayeredExitEndsWhenTheReducerLetsGo() {
    let layersOrder: [CloudLoadingLayer] = [.strip, .logo, .hero, .shade, .backdrop]
    #expect(layersOrder.map(\.exitDelay) == [0, 0.1, 0.3, 0.5, 0.6])
    #expect(abs((layersOrder.map(\.exitEnd).max() ?? 0) - 1.7) < 0.0001)
    #expect(StreamLoading.Screen.layered(layers()).exit == .milliseconds(1700))
    #expect(StreamLoading.Screen.card.exit == .milliseconds(600))
    #expect(CloudLoadingTiming.cardExit == 0.6)
    #expect(CloudLoadingLayer.strip.offset(.arriving) == 18)
    #expect(CloudLoadingLayer.backdrop.blur(.leaving) == 14)
    #expect(CloudLoadingLayer.hero.offset(.arriving) == 0)
}
