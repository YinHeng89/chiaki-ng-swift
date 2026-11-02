import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import Testing

@Test func controllerSamplesCarryBothTouchesAndMotion() throws {
    var state = ControllerState()
    state.buttons = 0x4000
    state.touches = ControllerTouchSlots(
        first: ControllerTouch(id: 3, x: 100, y: 200), second: ControllerTouch(id: 0x85, x: 1, y: 2)
    )
    state.motion = ControllerMotion(
        gyro: SIMD3(1, 2, 3), accel: SIMD3(4, 5, 6), orientation: SIMD4(0.1, 0.2, 0.3, 0.9)
    )
    let sample = ControllerSampleWriter.sample(of: state)
    #expect(sample.buttons == 0x4000)
    let first = try #require(sample.first_touch.value)
    #expect(first.id == 3)
    #expect(first.x == 100)
    let second = try #require(sample.second_touch.value)
    #expect(second.id == 5)
    let motion = try #require(sample.motion.value)
    #expect(motion.gyro_z == 3)
    #expect(motion.accel_x == 4)
    #expect(motion.orient_w == 0.9)
}

@Test func controllerSamplesLeaveMotionToTheCoreWhenUnavailable() {
    let sample = ControllerSampleWriter.sample(of: ControllerState())
    #expect(sample.motion.value == nil)
    #expect(sample.first_touch.value == nil)
    #expect(sample.second_touch.value == nil)
    #expect(sample.trigger_states.value == nil)
}
