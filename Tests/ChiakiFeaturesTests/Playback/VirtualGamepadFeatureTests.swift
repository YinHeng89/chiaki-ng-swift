import ChiakiModels
import ComposableArchitecture
import Testing
@testable import ChiakiFeatures

@MainActor private final class LinkClock {
    var instant = ContinuousClock.Instant.now

    func link() -> VirtualGamepadLink {
        VirtualGamepadLink { [unowned self] in self.instant }
    }

    func advance(by duration: Duration) {
        instant = instant.advanced(by: duration)
    }
}

@MainActor private func gamepad(
    _ clock: TestClock<Duration> = TestClock(),
    link: VirtualGamepadLink = VirtualGamepadLink()
) -> TestStoreOf<VirtualGamepadFeature> {
    let store = TestStore(initialState: VirtualGamepadFeature.State()) {
        VirtualGamepadFeature()
    } withDependencies: {
        $0.continuousClock = clock
        $0.virtualGamepadLink = link
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
}

@MainActor @Test func aStreamStartsWithTheSavedVirtualGamepadPresence() async {
    let store = gamepad()
    #expect(store.state.presence == .automatic)
    await store.send(.preferred(.hidden))
    #expect(store.state.presence == .hidden)
}

@MainActor @Test func reloadingAnUnchangedSavedPresenceKeepsTheStreamToggle() async {
    let store = gamepad()
    await store.send(.preferred(.hidden))
    await store.send(.presenceToggled(controllerConnected: false))
    #expect(store.state.presence == .shown)
    await store.send(.preferred(.hidden))
    #expect(store.state.presence == .shown)
    await store.skipInFlightEffects()
}

@MainActor @Test func changingTheSavedPresenceDuringAStreamReplacesTheToggle() async {
    let store = gamepad()
    await store.send(.presenceToggled(controllerConnected: false))
    #expect(store.state.presence == .hidden)
    await store.send(.preferred(.shown))
    #expect(store.state.presence == .shown)
    await store.skipInFlightEffects()
}

@MainActor @Test func hidingThroughTheSavedPresenceReleasesHeldControls() async {
    let store = gamepad()
    await store.send(.pressed(.cross, down: true))
    await store.send(.preferred(.hidden))
    #expect(store.state.pad.isIdle)
    await store.skipInFlightEffects()
}

@MainActor @Test func endingAStreamReturnsTheGamepadToTheSavedPresence() async {
    let store = gamepad()
    await store.send(.preferred(.hidden))
    await store.send(.touchpadAttached)
    await store.send(.presenceToggled(controllerConnected: false))
    #expect(store.state.presence == .shown)
    await store.send(.touchpadDetached)
    #expect(store.state.presence == .hidden)
    #expect(!store.state.touchpadAttached)
    await store.skipInFlightEffects()
}

@MainActor @Test func theLinkLendsOnlyTheTouchpadItHolds() {
    let link = VirtualGamepadLink()
    let lent = VirtualTouchpadModel(surface: .ps5, logger: .disabled)
    let other = VirtualTouchpadModel(surface: .ps5, logger: .disabled)
    link.attach(lent)
    #expect(!link.detach(other))
    #expect(link.touchpad === lent)
    #expect(link.detach(lent))
    #expect(link.touchpad == nil)
}

@MainActor @Test func aGamepadUsedJustNowStaysAwake() async {
    let clock = TestClock()
    let store = gamepad(clock)
    await store.send(.touched)
    await clock.advance(by: .seconds(5))
    #expect(store.state.attention == .awake)
    await store.skipInFlightEffects()
}

@MainActor @Test func anUntouchedGamepadRestsAndATouchWakesIt() async {
    let clock = TestClock()
    let store = gamepad(clock)
    await store.send(.appeared)
    await clock.advance(by: VirtualGamepadFeature.restDelay)
    await store.receive(\.restElapsed)
    #expect(store.state.attention == .resting)
    await store.send(.pressed(.cross, down: true))
    #expect(store.state.attention == .awake)
    await store.skipInFlightEffects()
}

@MainActor @Test func aHeldControlKeepsTheGamepadAwakePastItsRest() async {
    let clock = TestClock()
    let store = gamepad(clock)
    await store.send(.pressed(.cross, down: true))
    await clock.advance(by: VirtualGamepadFeature.restDelay)
    await store.receive(\.restElapsed)
    #expect(store.state.attention == .awake)
    await store.send(.releasedAll)
    await clock.advance(by: VirtualGamepadFeature.restDelay)
    await store.receive(\.restElapsed)
    #expect(store.state.attention == .resting)
}

@MainActor @Test func movingAStickWakesARestingGamepad() async {
    let clock = TestClock()
    let store = gamepad(clock)
    await store.send(.appeared)
    await clock.advance(by: VirtualGamepadFeature.restDelay)
    await store.receive(\.restElapsed)
    await store.send(.moved(.left, x: 0.5, y: 0))
    #expect(store.state.attention == .awake)
    await store.skipInFlightEffects()
}

@MainActor @Test func pressingTheTouchpadLightsTheSecondaryControlsUntilTheyLinger() async {
    let clock = TestClock()
    let store = gamepad(clock)
    #expect(store.state.secondary == .hidden)
    await store.send(.pressed(.touchpad, down: true))
    #expect(store.state.secondary == .lit)
    await clock.advance(by: VirtualGamepadFeature.secondaryLinger)
    await store.receive(\.lingerElapsed)
    #expect(store.state.secondary == .lit)
    await store.send(.pressed(.touchpad, down: false))
    await clock.advance(by: VirtualGamepadFeature.secondaryLinger)
    await store.receive(\.lingerElapsed)
    #expect(store.state.secondary == .hidden)
    await store.skipInFlightEffects()
}

@MainActor @Test func pressingAFaceButtonLeavesTheSecondaryControlsFaded() async {
    let store = gamepad()
    await store.send(.pressed(.cross, down: true))
    #expect(store.state.secondary == .hidden)
    await store.skipInFlightEffects()
}

@MainActor @Test func aBlockingOverlayReleasesTheGamepadAndTakesItsTouches() async {
    let store = gamepad()
    await store.send(.pressed(.cross, down: true))
    await store.send(.overlayBlockingChanged(true))
    #expect(store.state.yieldsToOverlay)
    #expect(store.state.pad.isIdle)
    await store.send(.overlayBlockingChanged(false))
    await store.send(.streamMenuChanged(.panel))
    #expect(store.state.yieldsToOverlay)
    await store.skipInFlightEffects()
}

@MainActor @Test func everyPadChangeIsPublishedIntoTheLinkAsItIsReduced() async {
    let link = VirtualGamepadLink()
    let store = gamepad(link: link)
    await store.send(.pressed(.cross, down: true))
    #expect(link.pad == store.state.pad.state)
    await store.send(.releasedAll)
    #expect(link.pad == ControllerState())
    await store.skipInFlightEffects()
}

@MainActor @Test func aPressReleasedBeforeTheNextReadIsStillPublished() async {
    let clock = LinkClock()
    let link = clock.link()
    let store = gamepad(link: link)
    await store.send(.pressed(.cross, down: true))
    await store.send(.pressed(.cross, down: false))
    #expect(link.pad == ControllerState())
    let seen = link.take()
    #expect(seen.buttons == PlayStationControl.cross.bit)
    clock.advance(by: VirtualGamepadLink.minimumHold)
    #expect(link.take() == ControllerState())
    await store.skipInFlightEffects()
}

@MainActor @Test func theLinkLatchesAPressThatComesAndGoesBetweenTwoReads() {
    let clock = LinkClock()
    let link = clock.link()
    #expect(link.take() == ControllerState())
    var pressed = ControllerState()
    pressed.buttons = PlayStationControl.circle.bit ?? 0
    pressed.rightTrigger = .max
    link.publish(pressed)
    link.publish(ControllerState())
    let first = link.take()
    #expect(first.buttons == pressed.buttons)
    #expect(first.rightTrigger == .max)
    clock.advance(by: VirtualGamepadLink.minimumHold)
    #expect(link.take() == ControllerState())
}

@MainActor @Test func theLinkKeepsAHeldPressAcrossReads() {
    let clock = LinkClock()
    let link = clock.link()
    var pressed = ControllerState()
    pressed.buttons = PlayStationControl.square.bit ?? 0
    link.publish(pressed)
    #expect(link.take() == pressed)
    clock.advance(by: VirtualGamepadLink.minimumHold)
    #expect(link.take() == pressed)
    link.publish(ControllerState())
    #expect(link.take() == pressed)
    #expect(link.take() == ControllerState())
}

@MainActor @Test func theLinkHoldsATapUntilTheConsoleHasHadTimeToSampleIt() {
    let clock = LinkClock()
    let link = clock.link()
    var pressed = ControllerState()
    pressed.buttons = PlayStationControl.cross.bit ?? 0
    pressed.leftTrigger = 200
    link.publish(pressed)
    link.publish(ControllerState())
    #expect(link.take() == pressed)
    clock.advance(by: .milliseconds(4))
    #expect(link.take() == pressed)
    clock.advance(by: VirtualGamepadLink.minimumHold - .milliseconds(8))
    #expect(link.take() == pressed)
    clock.advance(by: .milliseconds(4))
    #expect(link.take() == ControllerState())
    #expect(link.take() == ControllerState())
}

@MainActor @Test func theLinkHoldsEachButtonOfATapFromItsOwnFirstRead() {
    let clock = LinkClock()
    let link = clock.link()
    var cross = ControllerState()
    cross.buttons = PlayStationControl.cross.bit ?? 0
    var both = cross
    both.buttons |= PlayStationControl.circle.bit ?? 0
    link.publish(cross)
    #expect(link.take() == cross)
    clock.advance(by: .milliseconds(40))
    link.publish(both)
    link.publish(ControllerState())
    #expect(link.take() == both)
    clock.advance(by: .milliseconds(30))
    var circle = ControllerState()
    circle.buttons = PlayStationControl.circle.bit ?? 0
    #expect(link.take() == circle)
    clock.advance(by: .milliseconds(30))
    #expect(link.take() == ControllerState())
}
