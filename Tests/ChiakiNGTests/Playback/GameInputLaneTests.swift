@testable import ChiakiFeatures
import ChiakiModels
import CInput
import Testing
@testable import ChiakiNG

private func button(_ code: Int32, down: Bool) -> nx_input_event {
    nx_input_event(
        instance: 1, kind: ControllerInputEvent.button, control: code, value: down
            ? 1
            : 0,
        data: (0, 0, 0), timestamp_us: 0
    )
}

private func axis(_ code: Int32, _ value: Int32) -> nx_input_event {
    nx_input_event(
        instance: 1, kind: ControllerInputEvent.axis, control: code, value: value, data: (0, 0, 0),
        timestamp_us: 0
    )
}

private func lane(playerOne: Bool = true, microphone: Bool = false) -> GameInputLane {
    GameInputLane(GameInputLane.Assignment(
        device: 1,
        name: "Pad",
        preset: .standard,
        preferences: ControllerPreferences(),
        chord: playerOne
            ? [4, 6]
            : nil,
        ownsMicrophone: microphone,
        blocksStreamMenuChord: playerOne
    ))
}

private let cross = PlayStationControl.cross.bit ?? 0
private let circle = PlayStationControl.circle.bit ?? 0
private let touchpad = PlayStationControl.touchpad.bit ?? 0

@Test func aLaneIgnoresInputUntilItIsLive() {
    var subject = lane()
    let outcome = subject.apply(button(0, down: true))
    #expect(!outcome.changed)
    #expect(subject.state().buttons == 0)
}

@Test func buttonsHeldWhenALaneGoesLiveStayOutUntilReleased() {
    var subject = lane()
    _ = subject.apply(button(0, down: true))
    _ = subject.apply(axis(0, 30000))
    _ = subject.setLive(true)
    _ = subject.apply(button(0, down: true))
    _ = subject.apply(axis(0, 30000))
    #expect(subject.state().buttons & cross == 0)
    #expect(subject.state().leftX == 0)
    _ = subject.apply(button(0, down: false))
    _ = subject.apply(axis(0, 0))
    _ = subject.apply(button(0, down: true))
    _ = subject.apply(axis(0, 30000))
    #expect(subject.state().buttons & cross == cross)
    #expect(subject.state().leftX > 0)
}

@Test func theTouchpadChordTogglesInsteadOfPressingItsButtons() {
    var subject = lane()
    _ = subject.setLive(true)
    _ = subject.apply(button(4, down: true))
    let fired = subject.apply(button(6, down: true))
    #expect(fired.actions == [.toggleTouchpad])
    #expect(subject.state().buttons == 0)
}

@Test func theMicrophoneButtonTogglesTheMicrophoneOnlyWhenOwned() {
    var owned = lane(microphone: true)
    _ = owned.setLive(true)
    let pressed = owned.apply(button(15, down: true))
    let released = owned.apply(button(15, down: false))
    #expect(pressed.actions == [.toggleMicrophone])
    #expect(released.actions.isEmpty)
    var seat = lane(playerOne: false)
    _ = seat.setLive(true)
    let seated = seat.apply(button(15, down: true))
    #expect(seated.actions.isEmpty)
}

@Test func theStreamMenuChordNeverReachesTheConsole() {
    var subject = lane()
    _ = subject.setLive(true)
    _ = subject.apply(button(7, down: true))
    _ = subject.apply(button(8, down: true))
    let leftStick = PlayStationControl.leftStickButton.bit ?? 0
    let rightStick = PlayStationControl.rightStickButton.bit ?? 0
    #expect(subject.state().buttons & (leftStick | rightStick) == 0)
    var seat = lane(playerOne: false)
    _ = seat.setLive(true)
    _ = seat.apply(button(7, down: true))
    _ = seat.apply(button(8, down: true))
    #expect(seat.state().buttons & (leftStick | rightStick) == leftStick | rightStick)
}

@Test func theOverlayAddsKeysAndCanSuppressThePhysicalTouchpadClick() {
    var subject = lane()
    _ = subject.setLive(true)
    _ = subject.apply(button(0, down: true))
    _ = subject.apply(button(20, down: true))
    var keys = ControllerState()
    keys.buttons = circle
    keys.rightTrigger = 200
    subject.overlay = GameInputLane.Overlay(keys: keys, suppressTouchpadClick: true)
    let state = subject.state()
    #expect(state.buttons & (cross | circle) == cross | circle)
    #expect(state.buttons & touchpad == 0)
    #expect(state.rightTrigger == 200)
}

@Test func goingOfflineForgetsHeldInput() {
    var subject = lane()
    _ = subject.setLive(true)
    _ = subject.apply(button(0, down: true))
    let first = subject.setLive(false)
    let again = subject.setLive(false)
    #expect(first)
    #expect(!again)
    #expect(subject.state().buttons == 0)
}

@Test func nintendoLabelsMakeAConfirmAsCross() {
    var subject = GameInputLane(GameInputLane.Assignment(
        device: 1,
        name: "Switch Pro",
        preset: .standard,
        preferences: ControllerPreferences(),
        chord: nil,
        ownsMicrophone: false,
        blocksStreamMenuChord: false,
        family: .nintendo,
        buttonLayout: .label
    ))
    _ = subject.setLive(true)
    _ = subject.apply(button(1, down: true))
    #expect(subject.state().buttons & cross == cross)
    #expect(subject.state().buttons & circle == 0)
}

@MainActor @Test func promptsShowTheLabelledButtonForNintendoLayouts() {
    #expect(ControllerGlyphs.button(0, family: .nintendo).name == "B")
    #expect(ControllerGlyphs.button(0, family: .nintendo, layout: .label).name == "A")
    #expect(ControllerGlyphs.button(0, family: .playStation, layout: .label).name
        == ControllerGlyphs.button(0, family: .playStation).name)
}

private func nintendo(_ layout: ButtonLayout, chord: [Int]? = nil) -> GameInputLane.Assignment {
    GameInputLane.Assignment(
        device: 1, name: "Switch Pro", preset: .standard, preferences: ControllerPreferences(), chord: chord,
        ownsMicrophone: false, blocksStreamMenuChord: false, family: .nintendo, buttonLayout: layout
    )
}

@Test func changingTheLayoutWhileAButtonIsHeldDoesNotEatItsNextPress() {
    var subject = GameInputLane(nintendo(.position))
    _ = subject.setLive(true)
    _ = subject.apply(button(0, down: true))
    subject.update(nintendo(.label))
    _ = subject.setLive(false)
    _ = subject.setLive(true)
    _ = subject.apply(button(1, down: true))
    #expect(subject.state().buttons & cross == cross)
}

@Test func theTouchpadShortcutWorksWithADpadButton() {
    var subject = GameInputLane(nintendo(.position, chord: [9, 11]))
    _ = subject.setLive(true)
    _ = subject.apply(button(9, down: true))
    let fired = subject.apply(button(11, down: true))
    #expect(fired.actions == [.toggleTouchpad])
}

private func axis(_ code: Int32, _ value: Int32, at time: UInt64) -> nx_input_event {
    nx_input_event(
        instance: 1, kind: ControllerInputEvent.axis, control: code, value: value, data: (0, 0, 0),
        timestamp_us: time
    )
}

private func pressed(_ code: Int32, _ down: Bool, at time: UInt64) -> nx_input_event {
    nx_input_event(
        instance: 1, kind: ControllerInputEvent.button, control: code, value: down
            ? 1
            : 0,
        data: (0, 0, 0), timestamp_us: time
    )
}

private func xbox(touchButton: Int32?) -> GameInputLane {
    GameInputLane(GameInputLane.Assignment(
        device: 1, name: "Xbox", preset: .standard, preferences: ControllerPreferences(), chord: nil,
        ownsMicrophone: false, blocksStreamMenuChord: false, family: .xbox, touchButton: touchButton
    ))
}

@Test func theTouchButtonClicksOnATapAndTouchesWithTheRightStick() {
    var subject = xbox(touchButton: 4)
    _ = subject.setLive(true)
    _ = subject.apply(pressed(4, true, at: 0))
    #expect(subject.state().buttons & touchpad == 0)
    _ = subject.apply(pressed(4, false, at: 1_000))
    #expect(subject.state().buttons & touchpad == touchpad)
    let cleared = subject.tick(at: 1_000 + TouchButton.clickMicroseconds)
    #expect(cleared)
    #expect(subject.state().buttons & touchpad == 0)
    _ = subject.apply(pressed(4, true, at: 200_000))
    _ = subject.apply(axis(2, 32000, at: 200_100))
    let touching = subject.state()
    #expect(touching.touches.first != nil)
    #expect(touching.rightX == 0)
    #expect(touching.buttons & touchpad == 0)
    _ = subject.apply(pressed(4, false, at: 300_000))
    let released = subject.state()
    #expect(released.touches.first == nil)
    #expect(released.rightX == 0)
    #expect(released.buttons & touchpad == 0)
    _ = subject.apply(axis(2, 0, at: 300_100))
    _ = subject.apply(axis(2, 20000, at: 300_200))
    #expect(subject.state().rightX > 0)
}

@Test func controllersWithoutATouchButtonKeepTheirButtonsAndStick() {
    var subject = xbox(touchButton: nil)
    _ = subject.setLive(true)
    _ = subject.apply(pressed(4, true, at: 0))
    _ = subject.apply(axis(2, 32000, at: 10))
    let state = subject.state()
    let share = PlayStationControl.share.bit ?? 0
    #expect(state.buttons & share == share)
    #expect(state.rightX > 0)
    #expect(state.touches.first == nil)
}

@Test func aTouchpadHalfBindingTouchesThatHalfThroughTheLane() {
    var preset = InputPreset.standard
    preset.bindings.append(InputBinding(source: .gamepadButton, code: 21, label: "", target: .touchpadRight))
    var subject = GameInputLane(GameInputLane.Assignment(
        device: 1,
        name: "Pad",
        preset: preset,
        preferences: ControllerPreferences(),
        chord: nil,
        ownsMicrophone: false,
        blocksStreamMenuChord: false
    ))
    _ = subject.setLive(true)
    _ = subject.apply(button(21, down: true))
    let state = subject.state()
    #expect(state.buttons & touchpad == touchpad)
    #expect(state.touches.first.map { TouchpadSurface.ps5.region(of: $0) } == .right)
    _ = subject.apply(button(21, down: false))
    #expect(subject.state().buttons & touchpad == 0)
    #expect(subject.state().touches.isEmpty)
}

@Test func reportedTriggerStatesReachTheConsoleOnlyWithAdaptiveTriggersOn() {
    var subject = lane()
    _ = subject.setLive(true)
    let event = nx_input_event(
        instance: 1, kind: ControllerInputEvent.triggerState, control: 0,
        value: ControllerTriggerStates.reportedFlag | 5 | (3 << 8), data: (0, 0, 0), timestamp_us: 0
    )
    #expect(subject.apply(event).changed)
    #expect(subject.state().triggerStates == ControllerTriggerStates(left: 5, right: 3))
    var off = ControllerPreferences()
    off.adaptiveTriggersEnabled = false
    var assignment = subject.assignment
    assignment.preferences = off
    subject.update(assignment)
    #expect(subject.state().triggerStates == nil)
    let cleared = nx_input_event(
        instance: 1, kind: ControllerInputEvent.triggerState, control: 0, value: 0, data: (0, 0, 0),
        timestamp_us: 0
    )
    subject.update(GameInputLane.Assignment(
        device: 1, name: "Pad", preset: .standard, preferences: ControllerPreferences(),
        chord: nil, ownsMicrophone: false, blocksStreamMenuChord: false
    ))
    _ = subject.apply(cleared)
    #expect(subject.state().triggerStates == nil)
}

@Test func consoleMotionSettingsDecodeFromThePlayer() {
    #expect(ControllerMotionProcessing(taken: -1) == nil)
    #expect(ControllerMotionProcessing(taken: 3) == .standard)
    #expect(ControllerMotionProcessing(taken: 1)
        == ControllerMotionProcessing(tiltCorrection: false, angularVelocityDeadband: true))
    #expect(ControllerMotionProcessing(taken: 2)
        == ControllerMotionProcessing(tiltCorrection: true, angularVelocityDeadband: false))
}

private func gyroPad(_ mode: StickGyroMode, button: Int32? = nil,
                     tap: PlayStationControl? = nil) -> GameInputLane {
    var subject = GameInputLane(GameInputLane.Assignment(
        device: 1, name: "Pad", preset: .standard, preferences: ControllerPreferences(), chord: nil,
        ownsMicrophone: false, blocksStreamMenuChord: false, gyroButton: button, gyroTapTarget: tap,
        stickGyroMode: mode
    ))
    _ = subject.setLive(true)
    return subject
}

private func turn(_ subject: inout GameInputLane, from start: UInt64) {
    for step in 0..<20 {
        _ = subject.tick(at: start + UInt64(step) * 4000)
    }
}

private func press(_ code: Int32, down: Bool, at time: UInt64) -> nx_input_event {
    nx_input_event(
        instance: 1, kind: ControllerInputEvent.button, control: code, value: down
            ? 1
            : 0,
        data: (0, 0, 0), timestamp_us: time
    )
}

private let rightStickButton = PlayStationControl.rightStickButton.bit ?? 0

@Test func alwaysStickGyroTurnsTheControllerInsteadOfMovingTheCamera() {
    var subject = gyroPad(.always)
    _ = subject.apply(axis(2, 32767))
    turn(&subject, from: 1_000_000)
    let state = subject.state()
    #expect(state.rightX == 0)
    #expect((state.motion?.gyro.y ?? 0) < 0)
}

@Test func stickGyroWhileHeldLeavesTheCameraAloneUntilTheButtonIsHeld() {
    var subject = gyroPad(.whileHeld, button: 8, tap: .rightStickButton)
    _ = subject.apply(axis(2, 32767))
    turn(&subject, from: 1_000_000)
    #expect(subject.state().rightX > 0)
    #expect(subject.state().motion == nil)
    _ = subject.apply(press(8, down: true, at: 1_100_000))
    turn(&subject, from: 2_000_000)
    #expect(subject.state().rightX == 0)
    #expect((subject.state().motion?.gyro.y ?? 0) < 0)
    #expect(subject.state().buttons & rightStickButton == 0)
}

@Test func holdingTheGyroButtonCapturesTheStickBeforeItTurns() {
    var subject = gyroPad(.whileHeld, button: 8, tap: .rightStickButton)
    _ = subject.apply(press(8, down: true, at: 1_000_000))
    _ = subject.apply(axis(2, 4000))
    turn(&subject, from: 1_000_000)
    #expect(subject.state().rightX == 0)
    #expect(subject.state().motion == nil)
    _ = subject.apply(axis(2, 30000))
    turn(&subject, from: 2_000_000)
    #expect((subject.state().motion?.gyro.y ?? 0) < 0)
}

@Test func releasingTheGyroButtonStopsTheTurnStraightAway() {
    var subject = gyroPad(.whileHeld, button: 8, tap: .rightStickButton)
    _ = subject.apply(axis(2, 32767))
    _ = subject.apply(press(8, down: true, at: 1_000_000))
    turn(&subject, from: 1_000_000)
    _ = subject.apply(press(8, down: false, at: 1_100_000))
    #expect(subject.state().motion?.gyro == SIMD3<Float>())
    #expect(subject.state().rightX > 0)
    #expect(subject.state().buttons & rightStickButton == 0)
}

@Test func aQuickPressOfTheGyroButtonStillClicksR3() {
    var subject = gyroPad(.whileHeld, button: 8, tap: .rightStickButton)
    _ = subject.apply(press(8, down: true, at: 1_000_000))
    #expect(subject.state().buttons & rightStickButton == 0)
    _ = subject.apply(press(8, down: false, at: 1_050_000))
    #expect(subject.state().buttons & rightStickButton == rightStickButton)
    _ = subject.tick(at: 1_200_000)
    #expect(subject.state().buttons & rightStickButton == 0)
}

@Test func withStickGyroOffTheGyroButtonActsNormally() {
    var subject = gyroPad(.off, button: 8, tap: .rightStickButton)
    _ = subject.apply(press(8, down: true, at: 1_000_000))
    #expect(subject.state().buttons & rightStickButton == rightStickButton)
}

@Test func stickGyroIgnoresTheControllersOwnGyroWhileTurning() {
    var subject = gyroPad(.always)
    let sensor = nx_input_event(
        instance: 1, kind: ControllerInputEvent.sensor, control: Int32(NX_INPUT_SENSOR_GYRO), value: 0,
        data: (5, 5, 5), timestamp_us: 1_000_000
    )
    #expect(!subject.apply(sensor).changed)
}

@Test func anXboxPadWithTheDefaultGyroButtonStillPlays() {
    let preset = InputPreset.standard.withoutTouchpad.withoutGyro
    var subject = GameInputLane(GameInputLane.Assignment(
        device: 1, name: "Xbox", preset: preset, preferences: ControllerPreferences(), chord: [4, 6],
        ownsMicrophone: false, blocksStreamMenuChord: true, family: .xbox, touchButton: 4, gyroButton: 8,
        gyroTapTarget: .rightStickButton, stickGyroMode: StickGyroMode.automatic.resolved(sensors: false)
    ))
    _ = subject.setLive(true)
    _ = subject.apply(button(0, down: true))
    _ = subject.apply(axis(0, 30000))
    _ = subject.apply(axis(2, 30000))
    #expect(subject.state().buttons & cross == cross)
    #expect(subject.state().leftX > 0)
    #expect(subject.state().rightX > 0)
}
