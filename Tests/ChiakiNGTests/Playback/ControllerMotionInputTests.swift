import ChiakiModels
import CInput
import Foundation
import Testing
@testable import ChiakiNG

private func event(
    _ kind: Int32, control: Int32 = 0, value: Int32 = 0, data: SIMD3<Float> = .zero, at time: UInt64 = 0
) -> nx_input_event {
    nx_input_event(
        instance: 7, kind: kind, control: control, value: value, data: (data.x, data.y, data.z),
        timestamp_us: time
    )
}

@Test func motionTrackerStaysSilentUntilTheFirstSample() {
    let tracker = ControllerMotionTracker()
    #expect(tracker.motion == nil)
    tracker.accept(event(
        Int32(NX_INPUT_EVENT_AXIS),
        control: Int32(NX_INPUT_SENSOR_GYRO),
        data: SIMD3(1, 1, 1)
    ))
    #expect(tracker.motion == nil)
}

@Test func motionTrackerFeedsGyroAndAccelerometerSamples() throws {
    let tracker = ControllerMotionTracker()
    let sensor = Int32(NX_INPUT_EVENT_SENSOR)
    var time: UInt64 = 1000
    for _ in 0..<100 {
        tracker.accept(event(sensor, control: Int32(NX_INPUT_SENSOR_ACCEL), data: SIMD3(0, 1, 0), at: time))
        tracker.accept(event(sensor, control: Int32(NX_INPUT_SENSOR_GYRO), data: SIMD3(0.5, 0, 0), at: time))
        time += 4000
    }
    let motion = try #require(tracker.motion)
    #expect(motion.gyro == SIMD3(0.5, 0, 0))
    #expect(abs(motion.accel.y - 1) < 0.01)
    let length = (motion.orientation * motion.orientation).sum().squareRoot()
    #expect(abs(length - 1) < 0.01)
    tracker.reset()
    #expect(tracker.motion != nil)
}

@Test func touchpadEventsDrivePhysicalFingers() {
    var pad = PhysicalTouchpad(surface: .ps5)
    TouchpadInput.apply(
        event(Int32(NX_INPUT_EVENT_TOUCH_DOWN), control: 1, data: SIMD3(0.5, 0.5, 1)),
        to: &pad,
        avoiding: [0]
    )
    #expect(pad.touches.first == ControllerTouch(id: 1, x: 960, y: 540))
    TouchpadInput.apply(
        event(Int32(NX_INPUT_EVENT_TOUCH_MOTION), control: 1, data: SIMD3(0, 0, 1)),
        to: &pad,
        avoiding: []
    )
    #expect(pad.touches.first == ControllerTouch(id: 1, x: 0, y: 0))
    TouchpadInput.apply(
        event(Int32(NX_INPUT_EVENT_TOUCH_MOTION), control: 0, value: 1, data: SIMD3(1, 1, 1)),
        to: &pad,
        avoiding: []
    )
    #expect(pad.touches.first?.x == 0)
    TouchpadInput.apply(event(Int32(NX_INPUT_EVENT_TOUCH_UP), control: 1), to: &pad, avoiding: [])
    #expect(!pad.isActive)
}

@MainActor @Test func onlyDeliberateControllerInputCounts() {
    #expect(SDLInputCoordinator.isDeliberate(event(1, value: 1)))
    #expect(!SDLInputCoordinator.isDeliberate(event(1, value: 0)))
    #expect(!SDLInputCoordinator.isDeliberate(event(2, value: 4000)))
    #expect(!SDLInputCoordinator.isDeliberate(event(2, value: -8000)))
    #expect(SDLInputCoordinator.isDeliberate(event(2, value: -9000)))
    #expect(!SDLInputCoordinator.isDeliberate(event(3, value: 1)))
}

@MainActor @Test func sensorAndTouchEventsAreNotDeliberateNavigation() {
    #expect(ControllerInputEvent.isSensor(event(Int32(NX_INPUT_EVENT_SENSOR))))
    #expect(ControllerInputEvent.isTouch(event(Int32(NX_INPUT_EVENT_TOUCH_MOTION))))
    #expect(!ControllerInputEvent.isTouch(event(Int32(NX_INPUT_EVENT_BUTTON), value: 1)))
    #expect(!SDLInputCoordinator.isDeliberate(event(Int32(NX_INPUT_EVENT_SENSOR), value: 1)))
    #expect(!SDLInputCoordinator.isDeliberate(event(Int32(NX_INPUT_EVENT_TOUCH_DOWN), value: 1)))
}
