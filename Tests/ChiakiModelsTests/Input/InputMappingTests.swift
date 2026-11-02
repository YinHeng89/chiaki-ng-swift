import ChiakiModels
import Foundation
import Testing

@Test func defaultInputsMatchChiakiButtonBits() throws {
    _ = try ControlsConfiguration().validated()
    #expect(PlayStationControl.cross.bit == 1)
    #expect(PlayStationControl.system.bit == 1 << 15)
    #expect(PlayStationControl.dpadUp.bit == 1 << 6)
    #expect(PlayStationControl.leftTrigger.bit == nil)
}
@Test func inputSourcesReleaseIndependentlyAndOppositeKeysCancel() {
    var mapper = InputMapper()
    mapper.press(source: .macKey, code: 36, down: true, preset: .standard)
    mapper.press(source: .gamepadButton, code: 0, down: true, preset: .standard)
    mapper.press(source: .macKey, code: 36, down: false, preset: .standard)
    #expect(mapper.state.buttons == 1)
    mapper.press(source: .macKey, code: 0, down: true, preset: .standard)
    mapper.press(source: .macKey, code: 2, down: true, preset: .standard)
    #expect(mapper.state.leftX == 0)
    mapper.press(source: .macKey, code: 2, down: false, preset: .standard)
    #expect(mapper.state.leftX == -32767)
    mapper.reset()
    #expect(mapper.state == ControllerState())
}
@Test func shortTapProducesPressThenReleaseSnapshots() {
    var mapper = InputMapper()
    mapper.press(source: .macKey, code: 36, down: true, preset: .standard)
    let pressed = mapper.state
    mapper.press(source: .macKey, code: 36, down: false, preset: .standard)
    #expect(pressed.buttons == 1)
    #expect(mapper.state.buttons == 0)
}
@Test func calibrationClampsAndPreservesFullTravel() {
    #expect(InputMapper.calibrated(2000, deadZone: 0.12) == 0)
    #expect(InputMapper.calibrated(32767, deadZone: 0.12) == 32767)
    #expect(InputMapper.calibrated(-32768, deadZone: 0.12, inverted: true) == 32767)
}
@Test func conflictingBindingsAndInvalidCalibrationCannotBeSaved() {
    var configuration = ControlsConfiguration()
    configuration.presets[0].bindings.append(.init(
        source: .macKey,
        code: 36,
        label: "Return",
        target: .circle
    ))
    #expect(throws: InputFailure.duplicateBinding) { try configuration.validated() }
    configuration = .init()
    var preferences = ControllerPreferences()
    preferences.deadZone = .nan
    configuration.controllers["test"] = preferences
    #expect(throws: InputFailure.invalidConfiguration) { try configuration.validated() }
}

@Test func legacyControllerPreferencesEnableSupportedExtendedFeedback() throws {
    let json = Data("""
    {"nickname":"Original","deadZone":0.15,"invertRightY":false,"swapSticks":false,"rumbleStrength":0.8}
    """.utf8)
    var preferences = try JSONDecoder().decode(ControllerPreferences.self, from: json)
    #expect(preferences.hapticFeedback == .automatic)
    #expect(preferences.adaptiveTriggersEnabled)
    #expect(preferences.rumbleStrength == 0.8)
    #expect(preferences.hapticStrength == 1.0)
    preferences.hapticFeedback = .rumble
    preferences.adaptiveTriggersEnabled = true
    preferences.hapticStrength = 0.35
    let decoded = try JSONDecoder().decode(
        ControllerPreferences.self,
        from: JSONEncoder().encode(preferences)
    )
    #expect(decoded == preferences)
    let oldDefault = Data("""
    {"nickname":"Original","deadZone":0.15,"invertRightY":false,"swapSticks":false,\
    "rumbleStrength":0.8,"hapticStrength":0.7}
    """.utf8)
    #expect(try JSONDecoder().decode(ControllerPreferences.self, from: oldDefault).hapticStrength == 0.7)
    let nativeOff = Data("""
    {"nickname":"Original","deadZone":0.15,"invertRightY":false,"swapSticks":false,\
    "rumbleStrength":0.8,"nativeHapticsEnabled":false}
    """.utf8)
    #expect(try JSONDecoder().decode(ControllerPreferences.self, from: nativeOff).hapticFeedback == .off)
    let nativeOn = Data("""
    {"nickname":"Original","deadZone":0.15,"invertRightY":false,"swapSticks":false,\
    "rumbleStrength":0.8,"nativeHapticsEnabled":true}
    """.utf8)
    #expect(try JSONDecoder().decode(ControllerPreferences.self, from: nativeOn).hapticFeedback == .automatic)
    #expect(ControllerPreferences().rumbleStrength == 1.0)
    let future = Data("""
    {"nickname":"Original","deadZone":0.15,"invertRightY":false,"swapSticks":false,\
    "rumbleStrength":0.8,"hapticFeedback":"somethingNew"}
    """.utf8)
    #expect(try JSONDecoder().decode(ControllerPreferences.self, from: future).hapticFeedback == .automatic)
    var configuration = ControlsConfiguration()
    preferences.hapticStrength = .nan
    configuration.controllers["unit:fixture"] = preferences
    #expect(throws: InputFailure.invalidConfiguration) { try configuration.validated() }
}

@Test func keyboardOnlyPlayerOneIsAValidSelection() throws {
    var configuration = ControlsConfiguration()
    #expect(!configuration.keyboardOnly)
    configuration.selectedControllerKey = ControlsConfiguration.keyboardOnlyKey
    #expect(configuration.keyboardOnly)
    #expect(try configuration.validated() == configuration)
}

@Test func tappedStickKeysNudgeAndHeldKeysRampToFullTilt() {
    var mapper = InputMapper()
    mapper.press(source: .macKey, code: 2, down: true, preset: .standard, at: 10)
    #expect(mapper.state(at: 10, ramp: .keyboard).leftX == 11468)
    #expect(mapper.state(at: 10.125, ramp: .keyboard).leftX == 22118)
    #expect(mapper.state(at: 10.25, ramp: .keyboard).leftX == 32767)
    #expect(mapper.state(at: 99, ramp: .keyboard).leftX == 32767)
    mapper.press(source: .macKey, code: 2, down: false, preset: .standard, at: 99)
    #expect(mapper.state(at: 99, ramp: .keyboard).leftX == 0)
}

@Test func diagonalStickKeysStayOnTheStickCircle() {
    var mapper = InputMapper()
    mapper.press(source: .macKey, code: 13, down: true, preset: .standard, at: 0)
    mapper.press(source: .macKey, code: 2, down: true, preset: .standard, at: 0)
    let full = mapper.state(at: 1, ramp: .keyboard)
    #expect(full.leftX == 23170)
    #expect(full.leftY == -23170)
    let tap = mapper.state(at: 0, ramp: .keyboard)
    #expect(tap.leftX == 11468)
    #expect(tap.leftY == -11468)
}

@Test func laterStickKeyRampsOnItsOwnClock() {
    var mapper = InputMapper()
    mapper.press(source: .macKey, code: 13, down: true, preset: .standard, at: 0)
    mapper.press(source: .macKey, code: 2, down: true, preset: .standard, at: 1)
    let turning = mapper.state(at: 1, ramp: .keyboard)
    #expect(turning.leftY < -30000)
    #expect(turning.leftX == 10825)
    mapper.press(source: .macKey, code: 0, down: true, preset: .standard, at: 1)
    #expect(mapper.state(at: 2, ramp: .keyboard).leftX == 0)
    mapper.press(source: .macKey, code: 2, down: false, preset: .standard, at: 2)
    let diagonal = mapper.state(at: 2, ramp: .keyboard)
    #expect(diagonal.leftX == -23170)
    #expect(diagonal.leftY == -23170)
}
@Test func touchpadHalfTargetsTouchTheirHalfAndClick() {
    var preset = InputPreset.standard
    preset.bindings.append(InputBinding(source: .gamepadButton, code: 21, label: "", target: .touchpadLeft))
    preset.bindings.append(InputBinding(source: .gamepadButton, code: 22, label: "", target: .touchpadRight))
    var mapper = InputMapper()
    mapper.press(source: .gamepadButton, code: 21, down: true, preset: preset)
    let left = mapper.state
    #expect(left.buttons & (PlayStationControl.touchpad.bit ?? 0) != 0)
    #expect(left.touches.first.map { TouchpadSurface.ps5.region(of: $0) } == .left)
    #expect(left.touches.second == nil)
    mapper.press(source: .gamepadButton, code: 22, down: true, preset: preset)
    let both = mapper.state
    #expect(both.touches.first.map { TouchpadSurface.ps5.region(of: $0) } == .left)
    #expect(both.touches.second.map { TouchpadSurface.ps5.region(of: $0) } == .right)
    #expect(both.touches.first?.id != both.touches.second?.id)
    mapper.press(source: .gamepadButton, code: 21, down: false, preset: preset)
    mapper.press(source: .gamepadButton, code: 22, down: false, preset: preset)
    #expect(mapper.state == ControllerState())
}
@Test func touchpadHalfTargetsUseTheConsoleTouchSurface() {
    var preset = InputPreset.standard
    preset.bindings.append(InputBinding(source: .macKey, code: 32, label: "U", target: .touchpadRight))
    var mapper = InputMapper(touchSurface: .ps4)
    mapper.press(source: .macKey, code: 32, down: true, preset: preset)
    let touch = mapper.state(at: 0, ramp: .keyboard).touches.first
    #expect(touch?.x == 1440)
    #expect(touch?.y == 471)
}
@Test func triggerStatesDecodeOnlyWhenReported() {
    #expect(ControllerTriggerStates(reported: 0) == nil)
    #expect(ControllerTriggerStates(reported: 0x0305) == nil)
    #expect(ControllerTriggerStates(reported: ControllerTriggerStates.reportedFlag | 0xff05)
        == ControllerTriggerStates(left: 5, right: 0xff))
}

@Test func triggerStatesGroupIntoTheirEffectKind() {
    #expect(ControllerTriggerStates.kind(0) == 0)
    #expect(ControllerTriggerStates.kind(1) == ControllerTriggerStates.kind(2))
    #expect(ControllerTriggerStates.kind(3) == ControllerTriggerStates.kind(5))
    #expect(ControllerTriggerStates.kind(6) == ControllerTriggerStates.kind(7))
    #expect(ControllerTriggerStates.kind(2) != ControllerTriggerStates.kind(3))
    #expect(ControllerTriggerStates.kind(0xff) == 4)
}
