import ChiakiModels
import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
@testable import ChiakiFeatures
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private let account = UUID()
private let hardware = Data(repeating: 0xb2, count: 6)

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

private func art() -> GameArtLayers {
    GameArtLayers(background: pixel(), hero: pixel(), logo: pixel())
}

private func title(_ name: String, concept: String) -> RecentTitle {
    RecentTitle(
        titleID: "\(name)_00", launchID: name, name: name, imageURL: "", lastPlayedMs: 1, recent: true,
        conceptID: concept
    )
}

private func console(_ kind: RegistrationFlow.ConsoleKind, _ id: UUID) -> DisplayedConsole {
    DisplayedConsole(
        target: RegistrationFlow.ConsoleTarget(
            address: "192.168.1.\(abs(id.hashValue) % 200)",
            kind: kind,
            id: id
        ),
        preview: false
    )
}

private func played(_ rails: [(UUID, [RecentTitle])]) -> RecentlyPlayedReducer.State {
    var state = RecentlyPlayedReducer.State()
    state.selection = .init(profileID: account, eligible: true)
    state.phase = .loaded
    state.rails = rails.map { id, titles in
        RecentlyPlayedRail(consoleID: id, hardwareID: hardware, titles: titles)
    }
    return state
}

private func request(_ concept: String) -> ConsoleArtRequest {
    ConsoleArtRequest(accountID: account, conceptID: concept)
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var concepts: [String] = []

    func note(_ concept: String) {
        lock.withLock {
            concepts.append(concept)
        }
    }

    var all: [String] {
        lock.withLock {
            concepts
        }
    }
}

@MainActor @Test func theCardIsLayeredOnlyOnceAllThreeLayersArrived() {
    let id = UUID()
    let item = console(.ps5, id)
    let plan = ConsoleContinuePlan(
        consoles: [item], recentlyPlayed: played([(id, [title("Game", concept: "10000237")])]),
        gridWidth: 1400
    )
    var state = ConsoleArtReducer.State()
    #expect(plan.face(for: item, art: nil, samples: SampleArtStudio()) == .tile)
    #expect(plan.face(for: item, art: state, samples: SampleArtStudio()) == .tile)
    state.phase = .asking(request("10000237"))
    #expect(plan.face(for: item, art: state, samples: SampleArtStudio()) == .tile)
    state.games["10000237"] = .plain
    #expect(plan.face(for: item, art: state, samples: SampleArtStudio()) == .tile)
    let layers = art()
    state.games["10000237"] = .layered(layers)
    #expect(plan.face(for: item, art: state, samples: SampleArtStudio()) == .art(layers))
    #expect(plan.face(for: item, art: state, samples: SampleArtStudio()).layers === layers)
    let narrow = ConsoleContinuePlan(
        consoles: [item], recentlyPlayed: played([(id, [title("Game", concept: "10000237")])]), gridWidth: 600
    )
    #expect(narrow.face(for: item, art: state, samples: SampleArtStudio()) == .none)
}

@MainActor @Test func theLayeredFormAppearsWhenTheImagesArrive() async {
    let layers = art()
    let store = TestStore(initialState: ConsoleArtReducer.State()) {
        ConsoleArtReducer()
    } withDependencies: {
        $0.consoles.artLayers = { _, _ in layers }
    }
    await store.send(.show([request("10000237")])) {
        $0.phase = .asking(request("10000237"))
    }
    #expect(store.state.layers(for: "10000237") == nil)
    await store.receive(.answered("10000237", layers)) {
        $0.phase = .idle
        $0.games["10000237"] = .layered(layers)
    }
    #expect(store.state.layers(for: "10000237") === layers)
}

@MainActor @Test func aGameIsAskedOncePerSessionEvenWhenItFails() async {
    let asked = Asked()
    let store = TestStore(initialState: ConsoleArtReducer.State()) {
        ConsoleArtReducer()
    } withDependencies: {
        $0.consoles.artLayers = { _, concept in
            asked.note(concept)
            return nil
        }
    }
    await store.send(.show([request("10000237"), request("10000237"), request("")])) {
        $0.phase = .asking(request("10000237"))
    }
    await store.receive(.answered("10000237", nil)) {
        $0.phase = .idle
        $0.games["10000237"] = .plain
    }
    await store.send(.show([request("10000237")]))
    await store.send(.show([]))
    await store.send(.show([request("10000237")]))
    #expect(asked.all == ["10000237"])
}

@MainActor @Test func consolesAreAskedOneAtATimeInTheOrderShown() async {
    let asked = Asked()
    let clock = TestClock()
    let first = art()
    let store = TestStore(initialState: ConsoleArtReducer.State()) {
        ConsoleArtReducer()
    } withDependencies: {
        $0.consoles.artLayers = { _, concept in
            asked.note(concept)
            try? await clock.sleep(for: .seconds(1))
            return concept == "1"
                ? first
                : nil
        }
    }
    await store.send(.show([request("1"), request("2"), request("3")])) {
        $0.phase = .asking(request("1"))
        $0.waiting = [request("2"), request("3")]
    }
    #expect(asked.all == ["1"])
    await store.send(.show([request("3"), request("1"), request("2")])) {
        $0.waiting = [request("3"), request("2")]
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.answered("1", first)) {
        $0.games["1"] = .layered(first)
        $0.phase = .asking(request("3"))
        $0.waiting = [request("2")]
    }
    await store.send(.show([])) {
        $0.waiting = []
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.answered("3", nil)) {
        $0.games["3"] = .plain
        $0.phase = .idle
    }
    #expect(asked.all == ["1", "3"])
}

@MainActor @Test func detailsAreAskedOnlyForCardsShowingContinueVisibleFirst() {
    let ids = (0..<5).map { _ in UUID() }
    let consoles = [
        console(.ps5, ids[0]), console(.ps4, ids[1]), console(.ps5, ids[2]), console(.ps5, ids[3]),
        console(.ps5, ids[4])
    ]
    let state = played([
        (ids[0], [title("One", concept: "1")]),
        (ids[1], [title("Old", concept: "9")]),
        (ids[2], []),
        (ids[3], [title("Three", concept: "3")]),
        (ids[4], [title("Bare", concept: "")])
    ])
    let plan = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 1400)
    #expect(plan.artRequests(account: account, visible: []) == [request("1"), request("3")])
    #expect(plan.artRequests(account: account, visible: [ids[3]]) == [request("3"), request("1")])
    #expect(plan.artRequests(account: account, visible: [ids[1], ids[2], ids[4]]) == [
        request("1"),
        request("3")
    ])
    #expect(plan.artRequests(account: nil, visible: [ids[0]]).isEmpty)
    let narrow = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 600)
    #expect(narrow.artRequests(account: account, visible: Set(ids)).isEmpty)
    let unloaded = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: nil, gridWidth: 1400)
    #expect(unloaded.artRequests(account: account, visible: Set(ids)).isEmpty)
}

@MainActor @Test func theLayeredSampleIsLayeredWithoutAskingAndThePlainSampleIsPlain() {
    let shown = SampleConsoleList([
        SampleConsole(model: .ps5, recentlyPlayed: .withLayeredArt),
        SampleConsole(model: .ps5, recentlyPlayed: .withoutLayeredArt),
        SampleConsole(model: .ps4, recentlyPlayed: .withLayeredArt),
        SampleConsole(model: .ps5, recentlyPlayed: .none)
    ]).displayed()
    let plan = ConsoleContinuePlan(consoles: shown, recentlyPlayed: nil, gridWidth: 2000)
    let studio = SampleArtStudio()
    let layered = plan.face(for: shown[0], art: nil, samples: studio)
    #expect(layered.layers != nil)
    #expect(plan.face(for: shown[0], art: nil, samples: studio) == layered)
    #expect(plan.face(for: shown[1], art: nil, samples: SampleArtStudio()) == .tile)
    #expect(plan.face(for: shown[2], art: nil, samples: SampleArtStudio()) == .none)
    #expect(plan.face(for: shown[3], art: nil, samples: SampleArtStudio()) == .none)
    #expect(plan.artRequests(account: account, visible: []).isEmpty)
    #expect(plan.continuing.isEmpty)
}

@Test func sampleLayersAreDrawnInCodeAndKeptPerTitle() throws {
    let studio = SampleArtStudio()
    let first = try #require(studio.layers(named: "Starfall Run"))
    #expect(studio.layers(named: "Starfall Run") === first)
    #expect(studio.layers(named: "Harbor Lights") !== first)
    #expect(SampleArtStudio().layers(named: "Starfall Run") !== first)
    let layered = try #require(first.layered)
    #expect(layered.background.width == 960 && layered.background.height == 540)
    #expect(layered.hero.height > layered.hero.width)
    #expect(layered.logo.width > layered.logo.height)
}

@Test func theArtFillsTheCardWithTheHeroOnItsTrailingSide() {
    #expect(ConsoleContinueForm.wide.artFraction == 1)
    #expect(ConsoleContinueForm.compact.artFraction == 1)
    #expect(ConsoleContinueForm.hidden.artFraction == 0)
    let figure = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.5)
    let hero = ConsoleContinueLayout.heroFrame(
        block(200, 400), figure: figure, in: CGSize(width: 400, height: 200)
    )
    #expect(abs(hero.height - 360) < 0.001 && abs(hero.width - 180) < 0.001)
    #expect(abs(hero.minY + hero.height * 0.1 - 18) < 0.001)
    #expect(abs(hero.minX + hero.width * figure.midX - 256) < 0.001)
    #expect(ConsoleContinueLayout.titleInset(700) == 26 && ConsoleContinueLayout.titleInset(900) == 26)
    #expect(abs(ConsoleContinueLayout.titleInset(1400) - 61) < 0.001)
    let roomy = ConsoleContinueLayout.heroFrame(
        block(200, 400), figure: ArtContentBounds.whole, in: CGSize(width: 1400, height: 200)
    )
    #expect(abs(roomy.midX - 796) < 0.001)
}

@MainActor @Test func theLayeredCardKeepsTheContinueFocusStop() {
    let ids = [UUID(), UUID()]
    let consoles = [console(.ps5, ids[0]), console(.ps5, ids[1])]
    let state = played([(ids[0], [title("One", concept: "1")]), (ids[1], [title("Two", concept: "2")])])
    let plan = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 1400)
    var art = ConsoleArtReducer.State()
    art.games["1"] = .layered(GameArtLayers(background: pixel(), hero: pixel(), logo: pixel()))
    #expect(plan.face(for: consoles[0], art: art, samples: SampleArtStudio()).layers != nil)
    #expect(plan.face(for: consoles[1], art: art, samples: SampleArtStudio()) == .tile)
    #expect(plan.columns == 2)
    let entering = ConsoleGridNavigation.stop(
        from: ConsoleGridOrigin(index: 1, onContinue: false), count: 2, columns: plan.columns, .left,
        continues: { plan.shows(consoles[$0]) }
    )
    #expect(entering == .resume(0))
    #expect(entering.focus(in: consoles) == .action(consoles[0], .resume))
    let leaving = ConsoleGridNavigation.stop(
        from: ConsoleGridOrigin(index: 0, onContinue: true), count: 2, columns: plan.columns, .right,
        continues: { plan.shows(consoles[$0]) }
    )
    #expect(leaving == .play(1))
    #expect(plan.continuing == Set(ids))
}

@Test func aPlanWithLayeredArtOffKeepsThePlainTileAndAsksForNothing() {
    let layered = DisplayedConsole(
        target: RegistrationFlow.ConsoleTarget(
            address: "Developer preview", kind: .ps5, remoteDeviceID: Data([9]), name: "Sample PS5"
        ),
        preview: true,
        sampleTitle: RecentTitle(titleID: "SAMPLE_00", launchID: "", name: "Sample", imageURL: ""),
        sampleRecentlyPlayed: .withLayeredArt
    )
    let layeredOn = ConsoleContinuePlan(consoles: [layered], recentlyPlayed: nil, gridWidth: 1400)
    let layeredOff = ConsoleContinuePlan(
        consoles: [layered],
        recentlyPlayed: nil,
        gridWidth: 1400,
        layeredArt: false
    )
    #expect(layeredOn.face(for: layered, art: nil, samples: SampleArtStudio()).layers != nil)
    #expect(layeredOff.face(for: layered, art: nil, samples: SampleArtStudio()).layers == nil)
    #expect(layeredOff.artRequests(account: UUID(), visible: []).isEmpty)
}

private func block(_ width: Int, _ height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let image = context?.makeImage() else {
        fatalError("no bitmap context")
    }
    return image
}

@Test func artDrawnSmallIsResampledToTheSizeItIsShownAt() {
    let logo = block(1600, 400)
    let fitted = ScaledArtCache.fitted(logo, in: CGSize(width: 230, height: 76))
    #expect(abs(fitted.width - 230) < 0.001 && abs(fitted.height - 57.5) < 0.001)
    let small = ScaledArtCache.downsampled(logo, width: 460, height: 115)
    #expect(small.width == 460 && small.height == 115)
    #expect(ScaledArtCache.downsampled(logo, width: 3200, height: 800) === logo)
    let cache = ScaledArtCache()
    #expect(cache.image(logo, width: 460, height: 115) === cache.image(logo, width: 460, height: 115))
    #expect(cache.image(logo, width: 230, height: 58).width == 230)
}

@Test func aTitleLaunchLoadsOnItsArtOnlyWhenAllThreeLayersAreKnown() {
    let layers = art()
    let chosen = title("One", concept: "1")
    var state = RootFeature.State()
    #expect(state.titleLoadingArt == nil)
    state.consoleArt.games["1"] = .layered(layers)
    #expect(state.titleLoadingArt == nil)
    state.recentlyPlayed.launch = .awaitingStream(TitleLaunch(
        accountID: UUID(), consoleID: UUID(), hardwareID: Data([1]), title: chosen
    ))
    #expect(state.titleLoadingArt === layers)
    state.consoleArt.games["1"] = .plain
    #expect(state.titleLoadingArt == nil)
}

@MainActor @Test func aLaunchedTitleIsAskedForItsArtAheadOfTheCards() async {
    let layers = art()
    let clock = TestClock()
    let store = TestStore(initialState: ConsoleArtReducer.State()) {
        ConsoleArtReducer()
    } withDependencies: {
        $0.consoles.artLayers = { _, concept in
            try? await clock.sleep(for: .seconds(1))
            return concept == "9"
                ? layers
                : nil
        }
    }
    await store.send(.show([request("1"), request("2")])) {
        $0.phase = .asking(request("1"))
        $0.waiting = [request("2")]
    }
    await store.send(.want(request("9"))) {
        $0.waiting = [request("9"), request("2")]
    }
    await store.send(.want(request("9")))
    await store.send(.want(request("1")))
    await store.send(.want(request("")))
    await clock.advance(by: .seconds(1))
    await store.receive(.answered("1", nil)) {
        $0.games["1"] = .plain
        $0.phase = .asking(request("9"))
        $0.waiting = [request("2")]
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.answered("9", layers)) {
        $0.games["9"] = .layered(layers)
        $0.phase = .asking(request("2"))
        $0.waiting = []
    }
    await store.send(.want(request("9")))
    await clock.advance(by: .seconds(1))
    await store.receive(.answered("2", nil)) {
        $0.games["2"] = .plain
        $0.phase = .idle
    }
}

@Test func theFigureInsideAHeroIsMeasuredFromItsOpaquePixels() throws {
    let context = try #require(CGContext(
        data: nil, width: 400, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 100, y: 320, width: 200, height: 400))
    let hero = try #require(context.makeImage())
    let box = ArtContentBounds.measured(hero)
    #expect(abs(box.midX - 0.5) < 0.03 && box.width > 0.4 && box.width <= 0.52)
    #expect(abs(box.midY - 0.35) < 0.03 && box.height > 0.4 && box.height <= 0.52)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(4)
    context.move(to: CGPoint(x: 300, y: 320))
    context.addLine(to: CGPoint(x: 390, y: 10))
    context.strokePath()
    let trailing = ArtContentBounds.measured(try #require(context.makeImage()))
    #expect(abs(trailing.midY - box.midY) < 0.03 && abs(trailing.height - box.height) < 0.05)
    #expect(ArtContentBounds.bulk([0, 0, 0]) == nil)
    #expect(ArtContentBounds.bulk([0, 100, 100, 0]) == 1 ..< 3)
    #expect(ArtContentBounds.measured(block(40, 40)) == ArtContentBounds.whole)
    let held = ArtContentBounds()
    #expect(held.box(of: hero) == box && held.box(of: hero) == box)
}

@Test func aTitleLaunchKeepsOneLoadingScreenFromTheLaunchToTheFirstFrame() {
    let chosen = title("One", concept: "1")
    let launch = TitleLaunch(accountID: UUID(), consoleID: UUID(), hardwareID: Data([1]), title: chosen)
    let session = UUID()
    var state = RootFeature.State()
    #expect(state.loadingStage == nil)
    state.recentlyPlayed.launch = .launching(OperationID(uuid: UUID()), launch)
    #expect(state.loadingStage == .startingTitle("One"))
    state.recentlyPlayed.launch = .awaitingStream(launch)
    #expect(state.loadingStage == .startingTitle("One"))
    state.stream.session = .starting(StreamSessionID(uuid: session), .connecting(attempt: 1))
    state.recentlyPlayed.launch = .streaming(session, launch, .none)
    #expect(state.loadingStage == .waitingForVideo)
    state.stream.session = .playing(StreamSessionID(uuid: session))
    #expect(state.loadingStage == nil)
    state.stream.session = .failed(StreamSessionID(uuid: session), .renderer)
    #expect(state.loadingStage == nil)
    #expect(String(localized: ConsoleLoadingStage.startingTitle("One").status) == "Starting One")
    #expect(ConsoleLoadingStage.waitingForVideo.step == 2)
}
