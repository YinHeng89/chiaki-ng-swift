import ChiakiModels
import Foundation
import Testing

private let level = ControllerMotion(gyro: .zero, accel: SIMD3(0, 1, 0), orientation: SIMD4(0, 0, 0, 1))

private func state(_ motion: ControllerMotion?, buttons: UInt32 = 0) -> ControllerState {
    var value = ControllerState()
    value.buttons = buttons
    value.motion = motion
    return value
}

@Test func motionNoiseInsideTheDeadbandIsNotANewSample() {
    var jitter = level
    jitter.gyro.x = 0.004
    jitter.accel.y = 0.995
    jitter.orientation.w = 0.999
    #expect(jitter.isWithin(.standard, of: level))
    #expect(!state(jitter).differsForConsole(from: state(level)))
}

@Test func motionBeyondTheDeadbandIsANewSample() {
    var turned = level
    turned.gyro.z = -0.2
    #expect(!turned.isWithin(.standard, of: level))
    #expect(state(turned).differsForConsole(from: state(level)))
    var tilted = level
    tilted.orientation.x = 0.01
    #expect(state(tilted).differsForConsole(from: state(level)))
}

@Test func nonMotionChangesAlwaysCountEvenWithMatchingMotion() {
    #expect(state(level, buttons: 1).differsForConsole(from: state(level)))
    #expect(state(level).differsForConsole(from: state(nil)))
    #expect(state(nil).differsForConsole(from: state(level)))
    #expect(!state(nil).differsForConsole(from: state(nil)))
}

@Test func stickGyroWhileHeldTurnsOnceTheStickMovesWithTheButtonDown() {
    var control = StickGyroControl(mode: .whileHeld)
    #expect(control.phase == .waiting)
    control.hold(down: true, at: 0)
    #expect(control.phase == .pressed)
    #expect(control.capturesRightStick)
    #expect(!control.turning)
    control.stick(magnitude: 0.1)
    #expect(!control.turning)
    control.stick(magnitude: 0.6)
    #expect(control.turning)
    control.hold(down: false, at: 10)
    #expect(control.phase == .waiting)
}

@Test func aQuickPressWithoutMovingTheStickIsATap() {
    var control = StickGyroControl(mode: .whileHeld)
    control.hold(down: true, at: 0)
    control.hold(down: false, at: 50_000)
    #expect(control.tapping)
    let early = control.tick(at: 100_000)
    let due = control.tick(at: 150_000)
    #expect(!early)
    #expect(due)
    #expect(control.phase == .waiting)
}

@Test func stickGyroAlwaysAndOffIgnoreTheHoldButton() {
    var always = StickGyroControl(mode: .always)
    always.hold(down: true, at: 0)
    always.hold(down: false, at: 10)
    #expect(always.turning)
    var off = StickGyroControl(mode: .off)
    off.hold(down: true, at: 0)
    #expect(off.phase == .off)
}

@Test func releasingStickGyroDropsAHeldTurnButKeepsAlways() {
    var held = StickGyroControl(mode: .whileHeld)
    held.hold(down: true, at: 0)
    held.stick(magnitude: 1)
    held.release()
    #expect(held.phase == .waiting)
    var always = StickGyroControl(mode: .always)
    always.release()
    #expect(always.turning)
}

@Test func changingTheStickGyroModeRestartsFromItsRestingPhase() {
    var control = StickGyroControl(mode: .whileHeld)
    control.hold(down: true, at: 0)
    control.stick(magnitude: 1)
    control.configure(.whileHeld)
    #expect(control.turning)
    control.configure(.off)
    #expect(control.phase == .off)
    control.configure(.always)
    #expect(control.turning)
}

@Test func automaticStickGyroIsHeldOnlyForControllersWithoutAGyro() {
    #expect(StickGyroMode.automatic.resolved(sensors: false) == .whileHeld)
    #expect(StickGyroMode.automatic.resolved(sensors: true) == .off)
    #expect(StickGyroMode.always.resolved(sensors: true) == .always)
}

@Test func controllersWithoutAGyroHoldR3ForGyroAndKeepR3() {
    let configuration = ControlsConfiguration()
    let xbox = configuration.preset(for: nil, touchpad: false, gyro: false)
    let rightStickButton = xbox.bindings.filter {
        $0.source == .gamepadButton && $0.code == InputPreset.gyroHoldButton
    }.map(\.target)
    #expect(rightStickButton.contains(.gyroHold))
    #expect(rightStickButton.first == .rightStickButton)
    #expect(!configuration.preset(for: nil, touchpad: true).bindings.contains { $0.target == .gyroHold })
}

@Test func theRightStickTurnsLikeAControllerYawingAndPitching() {
    let right = StickGyro.rates(x: 32767, y: 0, inverted: false)
    #expect(right.y < 0)
    #expect(right.x == 0)
    let up = StickGyro.rates(x: 0, y: -32767, inverted: false)
    #expect(up.x > 0)
    #expect(abs(up.x - StickGyro.fullTurnRate) < 0.0001)
    let invertedUp = StickGyro.rates(x: 0, y: -32767, inverted: true)
    #expect(invertedUp.x < 0)
    let halfway = StickGyro.rates(x: 16384, y: 0, inverted: false)
    #expect(abs(halfway.y) < StickGyro.fullTurnRate / 2)
    #expect(StickGyro.rates(x: 0, y: 0, inverted: false) == SIMD3<Float>())
}

@Test func deviceMotionIsUsedOnlyWhenThePadHasNoGyroAndTheSettingIsOn() {
    #expect(MotionSource(sensors: true, deviceMotion: true) == .controller)
    #expect(MotionSource(sensors: false, deviceMotion: false) == .controller)
    #expect(MotionSource(sensors: false, deviceMotion: true) == .device)
}

@Test func deviceAxesFollowTheScreenOrientation() {
    let topOfDevice = SIMD3<Float>(0, 1, 0)
    #expect(DeviceOrientation.portrait.controllerAxes(topOfDevice) == SIMD3(0, 1, 0))
    #expect(DeviceOrientation.portraitUpsideDown.controllerAxes(topOfDevice) == SIMD3(0, -1, 0))
    #expect(DeviceOrientation.landscapeLeft.controllerAxes(topOfDevice) == SIMD3(1, 0, 0))
    #expect(DeviceOrientation.landscapeRight.controllerAxes(topOfDevice) == SIMD3(-1, 0, 0))
    let rightOfDevice = SIMD3<Float>(1, 0, 0)
    #expect(DeviceOrientation.landscapeLeft.controllerAxes(rightOfDevice) == SIMD3(0, -1, 0))
    #expect(DeviceOrientation.landscapeRight.controllerAxes(rightOfDevice) == SIMD3(0, 1, 0))
}

@Test func anUprightDeviceReadsLikeAControllerResting() {
    let landscape = DeviceOrientation.landscapeLeft.controllerAcceleration(
        gravity: SIMD3(1, 0, 0), user: SIMD3()
    )
    #expect(landscape == SIMD3(0, 1, 0))
    let portrait = DeviceOrientation.portrait.controllerAcceleration(gravity: SIMD3(0, -1, 0), user: SIMD3())
    #expect(portrait == SIMD3(0, 1, 0))
}

@Test func savedPreferencesWithoutStickGyroUseAutomatic() throws {
    let saved = Data(#"{"nickname":"","deadZone":0.1,"invertRightY":false,"swapSticks":false,"rumbleStrength":1}"#
        .utf8)
    let preferences = try JSONDecoder().decode(ControllerPreferences.self, from: saved)
    #expect(preferences.stickGyro == .automatic)
    var held = preferences
    held.stickGyro = .whileHeld
    let decoded = try JSONDecoder().decode(ControllerPreferences.self, from: JSONEncoder().encode(held))
    #expect(decoded.stickGyro == .whileHeld)
}

@Test func deviceMotionStaysOffUntilChosen() throws {
    let configuration = ControlsConfiguration()
    #expect(!configuration.deviceMotion)
    var chosen = configuration
    chosen.deviceMotion = true
    let decoded = try JSONDecoder().decode(ControlsConfiguration.self, from: JSONEncoder().encode(chosen))
    #expect(decoded.deviceMotion)
}

@Test func aSimulatedTiltUpReadsLikeARealDualSenseTiltingUp() {
    var pose = StickGyroPose()
    _ = pose.turn(SIMD3(1.5, 0, 0), at: 0)
    let sample = pose.turn(SIMD3(1.5, 0, 0), at: 100_000)
    let gravity = sample.gravity
    #expect(sample.gyro.x > 0)
    #expect(gravity.z < 0)
    #expect(gravity.y > 0.9)
    #expect(pose.pitch > 0)
}

@Test func theSimulatedTiltStopsShortOfVerticalButTurningDoesNot() {
    var pose = StickGyroPose()
    let up = StickGyro.rates(x: 32767, y: -32767, inverted: false)
    for step in 0...200 {
        _ = pose.turn(up, at: UInt64(step) * 10000)
    }
    #expect(pose.pitch <= StickGyro.pitchLimit + 0.1)
    #expect(pose.pitch > StickGyro.pitchLimit - 0.2)
    #expect(pose.limited(up).x == 0)
    #expect(pose.limited(up).y == up.y)
    #expect(pose.limited(-up).x < 0)
}

@Test func recentringTheSimulatedPoseLevelsIt() {
    var pose = StickGyroPose()
    _ = pose.turn(SIMD3(2, 0, 0), at: 0)
    _ = pose.turn(SIMD3(2, 0, 0), at: 100_000)
    pose.recentre()
    #expect(pose.gravity == StickGyro.up)
}

@Test func turningWhileTiltedDoesNotLeanTheSimulatedPad() {
    var pose = StickGyroPose()
    for step in 0...30 {
        _ = pose.turn(SIMD3(1, 0, 0), at: UInt64(step) * 10000)
    }
    let tilted = pose.pitch
    for step in 31...300 {
        _ = pose.turn(SIMD3(0, 3, 0), at: UInt64(step) * 10000)
    }
    #expect(abs(pose.pitch - tilted) < 0.01)
    #expect(abs(pose.gravity.x) < 0.01)
}
