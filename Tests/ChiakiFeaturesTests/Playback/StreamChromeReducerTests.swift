import CoreGraphics
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures
import MenuFocus

@MainActor private func makeStore(_ clock: TestClock<Duration>) -> TestStoreOf<StreamChromeReducer> {
    TestStore(initialState: StreamChromeReducer.State()) {
        StreamChromeReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
    }
}

@MainActor private func settle(
    _ store: TestStoreOf<StreamChromeReducer>,
    _ clock: TestClock<Duration>
) async {
    store.exhaustivity = .off
    await clock.advance(by: StreamChromeReducer.introduction)
    await store.skipReceivedActions()
    store.exhaustivity = .on
}

@MainActor @Test func streamChromeStaysVisibleBeforeFirstFrame() async {
    let store = makeStore(TestClock())
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
    await store.send(.hovered([.topLeading])) {
        $0.hovered = [.topLeading]
        $0[.topLeading] = .held([.hover])
    }
    await store.send(.hovered([])) {
        $0.hovered = []
        $0[.topLeading] = .idle
    }
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
}

@MainActor @Test func streamChromeFadesAfterFirstFrameAndRevealsEveryCornerTogether() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.streaming(true)) {
        $0.mode = .streaming
        $0.hover = .suspended
        $0[.topLeading] = .lingering(UUID(0))
        $0[.topTrailing] = .lingering(UUID(1))
        $0[.bottomTrailing] = .lingering(UUID(2))
        $0[.bottom] = .lingering(UUID(3))
        $0.pointer = .resting(UUID(4))
        $0.dock = .introduced
    }
    await settle(store, clock)
    #expect(store.state.dock == .collapsed)
    #expect(store.state[.topLeading] == .idle)
    #expect(store.state[.topTrailing] == .idle)
    #expect(store.state[.bottomTrailing] == .idle)
    #expect(store.state.visibleCorners.isEmpty)

    await store.send(.hovered([.topLeading])) {
        $0.hovered = [.topLeading]
        $0.hover = .following
        $0[.topLeading] = .held([.hover])
    }
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))

    await store.send(.hovered([])) {
        $0.hovered = []
        $0[.topLeading] = .lingering(UUID(5))
    }
    await clock.advance(by: .milliseconds(1400))
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
    await clock.advance(by: .milliseconds(100))
    await store.receive(.lingerElapsed(.topLeading, UUID(5))) {
        $0[.topLeading] = .idle
    }
    #expect(store.state.visibleCorners.isEmpty)
}

@MainActor @Test func streamChromeReturningPointerCancelsTheFade() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    await settle(store, clock)

    await store.send(.hovered([.bottomTrailing])) {
        $0.hovered = [.bottomTrailing]
        $0.hover = .following
        $0[.bottomTrailing] = .held([.hover])
    }
    await store.send(.hovered([])) {
        $0.hovered = []
        $0[.bottomTrailing] = .lingering(UUID(5))
    }
    await clock.advance(by: .milliseconds(1000))
    await store.send(.hovered([.bottomTrailing])) {
        $0.hovered = [.bottomTrailing]
        $0[.bottomTrailing] = .held([.hover])
    }
    await clock.advance(by: .seconds(5))
    await store.send(.lingerElapsed(.bottomTrailing, UUID(5)))
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
}

@MainActor @Test func streamChromeMenuPinsCornerUntilClosed() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    await settle(store, clock)

    await store.send(.hovered([.topTrailing])) {
        $0.hovered = [.topTrailing]
        $0.hover = .following
        $0[.topTrailing] = .held([.hover])
    }
    await store.send(.pinned([.topTrailing])) {
        $0[.topTrailing] = .held([.hover, .pinned])
    }
    await store.send(.hovered([])) {
        $0.hovered = []
        $0[.topTrailing] = .held([.pinned])
    }
    await clock.advance(by: .seconds(10))
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))

    await store.send(.pinned([])) {
        $0[.topTrailing] = .lingering(UUID(5))
    }
    await clock.advance(by: StreamChromeReducer.linger)
    await store.receive(.lingerElapsed(.topTrailing, UUID(5))) {
        $0[.topTrailing] = .idle
    }
    #expect(store.state.visibleCorners.isEmpty)
}

@MainActor @Test func streamChromeKeyboardFocusRevealsEveryCorner() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    await settle(store, clock)

    await store.send(.focused([.topLeading])) {
        $0[.topLeading] = .held([.focus])
    }
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
    await store.send(.focused([])) {
        $0[.topLeading] = .lingering(UUID(5))
    }
    await clock.advance(by: StreamChromeReducer.linger)
    await store.receive(.lingerElapsed(.topLeading, UUID(5))) {
        $0[.topLeading] = .idle
    }
}

@MainActor @Test func streamChromeShowsEverythingWhenStreamEnds() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.streaming(true)) {
        $0.mode = .streaming
        $0.hover = .suspended
        $0[.topLeading] = .lingering(UUID(0))
        $0[.topTrailing] = .lingering(UUID(1))
        $0[.bottomTrailing] = .lingering(UUID(2))
        $0[.bottom] = .lingering(UUID(3))
        $0.pointer = .resting(UUID(4))
        $0.dock = .introduced
    }
    await store.send(.streaming(false)) {
        $0.mode = .attended
        $0.hover = .following
        $0[.topLeading] = .idle
        $0[.topTrailing] = .idle
        $0[.bottomTrailing] = .idle
        $0[.bottom] = .idle
        $0.pointer = .shown
        $0.dock = .collapsed
    }
    await clock.advance(by: .seconds(5))
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
    await store.send(.lingerElapsed(.topLeading, UUID(0)))
}

@MainActor @Test func aPointerLeftInACornerLetsTheChromeHideUntilItMoves() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.hovered([.bottom])) {
        $0.hovered = [.bottom]
        $0[.bottom] = .held([.hover])
    }
    await store.send(.streaming(true)) {
        $0.mode = .streaming
        $0.hover = .suspended
        $0[.topLeading] = .lingering(UUID(0))
        $0[.topTrailing] = .lingering(UUID(1))
        $0[.bottomTrailing] = .lingering(UUID(2))
        $0[.bottom] = .lingering(UUID(3))
        $0.pointer = .resting(UUID(4))
        $0.dock = .introduced
    }
    await settle(store, clock)
    #expect(store.state.visibleCorners.isEmpty)
    #expect(store.state.dock == .collapsed)
    #expect(store.state.pointer == .hidden)
    await store.send(.pointerMoved) {
        $0.hover = .following
        $0[.bottom] = .held([.hover])
        $0.pointer = .resting(UUID(5))
    }
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
    await clock.advance(by: StreamChromeReducer.pointerRest)
    await store.receive(.pointerRestElapsed(UUID(5))) {
        $0.pointer = .shown
    }
}

@MainActor @Test func aPointerCrossingIntoACornerAfterTheStreamStartsHoldsTheChrome() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.hovered([.bottom]))
    await store.send(.streaming(true))
    await settle(store, clock)
    store.exhaustivity = .on
    await store.send(.hovered([.topTrailing])) {
        $0.hovered = [.topTrailing]
        $0.hover = .following
        $0[.topTrailing] = .held([.hover])
    }
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
}

@MainActor @Test func theChromeFollowsTheHoveredCornersAgainWhenTheStreamEnds() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.hovered([.topTrailing]))
    await store.send(.streaming(true))
    await settle(store, clock)
    store.exhaustivity = .off
    await store.send(.streaming(false))
    #expect(store.state.hover == .following)
    #expect(store.state[.topTrailing] == .held([.hover]))
}

@Test func streamChromeHoverZonesCoverEachCornerOnly() {
    let size = CGSize(width: 1280, height: 720)
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 10, y: 10), in: size) == [.topLeading])
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 119, y: 119), in: size) == [.topLeading])
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 121, y: 10), in: size).isEmpty)
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 1100, y: 40), in: size) == [.topTrailing])
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 1200, y: 700), in: size) == [.bottomTrailing])
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 640, y: 700), in: size) == [.bottom])
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 640, y: 590), in: size).isEmpty)
    #expect(StreamChromeCorner.corners(at: CGPoint(x: 640, y: 360), in: size).isEmpty)
    #expect(StreamChromeCorner.corners(at: nil, in: size).isEmpty)
}

@MainActor @Test func streamChromeHidesTheRestingPointerAndShowsItWhenItMoves() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    await settle(store, clock)
    store.exhaustivity = .on
    #expect(store.state.pointer == .hidden)
    await store.send(.pointerMoved) {
        $0.hover = .following
        $0.pointer = .resting(UUID(5))
    }
    await clock.advance(by: .milliseconds(1900))
    await store.send(.pointerMoved) {
        $0.pointer = .resting(UUID(6))
    }
    await clock.advance(by: .milliseconds(1900))
    #expect(store.state.pointer == .resting(UUID(6)))
    await clock.advance(by: .milliseconds(100))
    await store.receive(.pointerRestElapsed(UUID(6))) {
        $0.pointer = .hidden
    }
    await store.send(.pointerMoved) {
        $0.pointer = .resting(UUID(7))
    }
    await store.send(.pointerLeft) {
        $0.pointer = .shown
    }
    await clock.advance(by: .seconds(5))
    await store.send(.pointerRestElapsed(UUID(7)))
}

@MainActor @Test func streamChromeKeepsThePointerWhileTheStreamMenuIsOpen() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    await settle(store, clock)
    store.exhaustivity = .on
    await store.send(.pinned([.bottom])) {
        $0[.bottom] = .held([.pinned])
    }
    await store.send(.pointerMoved) {
        $0.hover = .following
        $0.pointer = .resting(UUID(5))
    }
    await clock.advance(by: StreamChromeReducer.pointerRest)
    await store.receive(.pointerRestElapsed(UUID(5))) {
        $0.pointer = .shown
    }
}

@MainActor @Test func streamChromeKeepsThePointerBeforeTheFirstFrame() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.pointerMoved)
    await clock.advance(by: .seconds(5))
    #expect(store.state.pointer == .shown)
}

@MainActor @Test func theDockShowsWithItsHintWhenAStreamStartsAndCollapsesWhenTheChromeHides() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    #expect(store.state.dock == .introduced)
    await clock.advance(by: StreamChromeReducer.linger)
    await store.skipReceivedActions()
    #expect(store.state.dock == .introduced)
    #expect(store.state.visibleCorners == Set(StreamChromeCorner.allCases))
    await clock.advance(by: StreamChromeReducer.introduction - StreamChromeReducer.linger)
    await store.skipReceivedActions()
    #expect(store.state.dock == .collapsed)
    #expect(store.state.visibleCorners.isEmpty)
}

@MainActor @Test func theHandleExpandsTheDockOnlyWhileTheChromeShows() async {
    let clock = TestClock()
    let store = makeStore(clock)
    store.exhaustivity = .off
    await store.send(.streaming(true))
    await settle(store, clock)
    store.exhaustivity = .off
    await store.send(.dockExpanded)
    #expect(store.state.dock == .collapsed)
    await store.send(.hovered([.bottom]))
    await store.send(.dockExpanded)
    #expect(store.state.dock == .expanded)
    await store.send(.hovered([]))
    await clock.advance(by: StreamChromeReducer.linger)
    await store.skipReceivedActions()
    #expect(store.state.dock == .collapsed)
}

@MainActor @Test func theControllerTakingOverHidesThePointerAndReleasesTheHoveredCorner() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.streaming(true)) {
        $0.mode = .streaming
        $0.hover = .suspended
        $0[.topLeading] = .lingering(UUID(0))
        $0[.topTrailing] = .lingering(UUID(1))
        $0[.bottomTrailing] = .lingering(UUID(2))
        $0[.bottom] = .lingering(UUID(3))
        $0.pointer = .resting(UUID(4))
        $0.dock = .introduced
    }
    await settle(store, clock)
    store.exhaustivity = .off
    await store.send(.pointerMoved)
    await store.send(.hovered([.topLeading]))
    store.exhaustivity = .on
    #expect(store.state[.topLeading] == .held([.hover]))
    await store.send(.inputModeChanged(.controller)) {
        $0.input = .controller
        $0.hover = .suspended
        $0.pointer = .hidden
        $0[.topLeading] = .lingering(UUID(6))
    }
    await clock.advance(by: StreamChromeReducer.linger)
    await store.receive(.lingerElapsed(.topLeading, UUID(6))) {
        $0[.topLeading] = .idle
    }
    #expect(store.state.visibleCorners.isEmpty)
}

@MainActor @Test func aRestingPointerHidesOverHeldChromeWhileTheControllerDrives() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.streaming(true)) {
        $0.mode = .streaming
        $0.hover = .suspended
        $0[.topLeading] = .lingering(UUID(0))
        $0[.topTrailing] = .lingering(UUID(1))
        $0[.bottomTrailing] = .lingering(UUID(2))
        $0[.bottom] = .lingering(UUID(3))
        $0.pointer = .resting(UUID(4))
        $0.dock = .introduced
    }
    await settle(store, clock)
    store.exhaustivity = .off
    await store.send(.inputModeChanged(.controller))
    await store.send(.pinned([.bottom]))
    await store.send(.pointerMoved)
    store.exhaustivity = .on
    #expect(store.state.isAnyCornerHeld)
    guard case .resting(let id) = store.state.pointer else {
        Issue.record("pointer \(store.state.pointer)")
        return
    }
    await clock.advance(by: StreamChromeReducer.pointerRest)
    await store.receive(.pointerRestElapsed(id)) {
        $0.pointer = .hidden
    }
}

@MainActor @Test func theControllerTakingOverOutsideAStreamOnlyRecordsTheInput() async {
    let store = makeStore(TestClock())
    await store.send(.inputModeChanged(.controller)) {
        $0.input = .controller
    }
    #expect(store.state.pointer == .shown)
}

@MainActor @Test func goingLiveWhileTheControllerDrivesKeepsThePointerHidden() async {
    let clock = TestClock()
    let store = makeStore(clock)
    await store.send(.inputModeChanged(.controller)) {
        $0.input = .controller
    }
    await store.send(.streaming(true)) {
        $0.mode = .streaming
        $0.hover = .suspended
        $0[.topLeading] = .lingering(UUID(0))
        $0[.topTrailing] = .lingering(UUID(1))
        $0[.bottomTrailing] = .lingering(UUID(2))
        $0[.bottom] = .lingering(UUID(3))
        $0.pointer = .hidden
        $0.dock = .introduced
    }
    await settle(store, clock)
    #expect(store.state.pointer == .hidden)
}
