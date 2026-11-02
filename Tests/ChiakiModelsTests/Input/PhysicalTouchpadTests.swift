import ChiakiModels
import Foundation
import Testing

private let first = PhysicalTouchpad.Finger(touchpad: 0, finger: 0)
private let second = PhysicalTouchpad.Finger(touchpad: 0, finger: 1)
private let third = PhysicalTouchpad.Finger(touchpad: 0, finger: 2)

@Test func physicalFingerScalesOntoTheConsoleSurface() {
    var pad = PhysicalTouchpad(surface: .ps5)
    pad.down(first, x: 0.25, y: 0.5)
    #expect(pad.isActive)
    #expect(pad.touches == ControllerTouchSlots(first: ControllerTouch(id: 0, x: 480, y: 540)))
    pad.moved(first, x: 1, y: 1)
    #expect(pad.touches.first == ControllerTouch(id: 0, x: 1919, y: 1079))
    pad.up(first)
    #expect(!pad.isActive)
    #expect(pad.touches == .empty)
}

@Test func physicalFingersKeepTheirSlotsAndIdentities() {
    var pad = PhysicalTouchpad(surface: .ps4)
    pad.down(first, x: 0, y: 0)
    pad.down(second, x: 1, y: 1)
    #expect(pad.touches.first?.id == 0)
    #expect(pad.touches.second == ControllerTouch(id: 1, x: 1920, y: 942))
    pad.down(third, x: 0.5, y: 0.5)
    #expect(pad.touches.ids == [0, 1])
    pad.up(first)
    #expect(pad.touches.first == nil)
    #expect(pad.touches.second?.id == 1)
    pad.down(third, x: 0.5, y: 0.5)
    #expect(pad.touches.first?.id == 2)
    #expect(pad.touches.second?.id == 1)
}

@Test func physicalTouchpadIgnoresUnknownAndRepeatedFingers() {
    var pad = PhysicalTouchpad()
    pad.moved(first, x: 0.5, y: 0.5)
    pad.up(first)
    #expect(!pad.isActive)
    pad.down(first, x: 0.1, y: 0.1)
    pad.down(first, x: 0.9, y: 0.9)
    #expect(pad.touches.ids == [0])
    #expect(pad.touches.first?.x == 192)
    pad.reset()
    #expect(pad.touches == .empty)
}

@Test func physicalTouchIdentitiesAvoidTheOnesTheConsoleLastSaw() {
    var pad = PhysicalTouchpad()
    pad.down(first, x: 0.5, y: 0.5, avoiding: [0, 1])
    #expect(pad.touches.first?.id == 2)
    pad.up(first)
    pad.down(first, x: 0.5, y: 0.5, avoiding: [3])
    #expect(pad.touches.first?.id == 4)
}

@Test func physicalTouchIdentitiesWrapAtSevenBits() {
    var pad = PhysicalTouchpad()
    for _ in 0..<127 {
        pad.down(first, x: 0, y: 0)
        pad.up(first)
    }
    pad.down(first, x: 0, y: 0)
    #expect(pad.touches.first?.id == 127)
    pad.up(first)
    pad.down(first, x: 0, y: 0)
    #expect(pad.touches.first?.id == 0)
}
