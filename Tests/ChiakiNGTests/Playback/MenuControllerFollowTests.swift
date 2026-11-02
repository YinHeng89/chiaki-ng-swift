import ChiakiModels
import CInput
import Testing
@testable import ChiakiNG

private func input(_ instance: UInt32, kind: Int32, control: Int32 = 0, value: Int32) -> nx_input_event {
    nx_input_event(
        instance: instance, kind: kind, control: control, value: value, data: (0, 0, 0), timestamp_us: 0
    )
}

private func pad(_ id: UInt32) -> ControllerDevice {
    ControllerDevice(
        id: id, preferenceKey: "unit:\(id)", name: "Pad \(id)", transport: "USB", individual: true,
        rumble: true, lights: false, motion: false, touchpad: false
    )
}

private let button = Int32(NX_INPUT_EVENT_BUTTON)
private let axis = Int32(NX_INPUT_EVENT_AXIS)

@Test func menusFollowTheControllerThatWasLastPressed() {
    var follow = MenuControllerFollow()
    let available = [pad(1), pad(2)]
    #expect(follow.choose(from: available, preferred: pad(1), menusOnly: true) == pad(1))
    let adopted = follow.adopt(input(2, kind: button, value: 1), current: 1, menusOnly: true)
    #expect(adopted)
    #expect(follow.choose(from: available, preferred: pad(1), menusOnly: true) == pad(2))
    let again = follow.adopt(input(2, kind: button, value: 1), current: 2, menusOnly: true)
    #expect(!again)
}

@Test func menusIgnoreReleasesDriftAndTheRightStick() {
    var follow = MenuControllerFollow()
    let release = follow.adopt(input(2, kind: button, value: 0), current: 1, menusOnly: true)
    let drift = follow.adopt(input(2, kind: axis, control: 0, value: 12000), current: 1, menusOnly: true)
    let rightStick = follow.adopt(input(2, kind: axis, control: 2, value: 32767), current: 1, menusOnly: true)
    #expect(!release)
    #expect(!drift)
    #expect(!rightStick)
    #expect(follow.state == .preferred)
    let stick = follow.adopt(input(2, kind: axis, control: 1, value: -30000), current: 1, menusOnly: true)
    let trigger = follow.adopt(input(3, kind: axis, control: 5, value: 32767), current: 2, menusOnly: true)
    #expect(stick)
    #expect(trigger)
    #expect(follow.state == .adopted(3))
}

@Test func gameplayKeepsPlayerOnesControllerUntilFollowingIsReset() {
    var follow = MenuControllerFollow()
    _ = follow.adopt(input(2, kind: button, value: 1), current: 1, menusOnly: true)
    #expect(follow.choose(from: [pad(1), pad(2)], preferred: pad(1), menusOnly: false) == pad(1))
    let duringGameplay = follow.adopt(input(3, kind: button, value: 1), current: 1, menusOnly: false)
    #expect(!duringGameplay)
    follow.reset()
    #expect(follow.choose(from: [pad(1), pad(2)], preferred: pad(1), menusOnly: true) == pad(1))
}

@Test func anAdoptedControllerThatDisconnectsHandsMenusBack() {
    var follow = MenuControllerFollow()
    _ = follow.adopt(input(2, kind: button, value: 1), current: 1, menusOnly: true)
    #expect(follow.choose(from: [pad(1)], preferred: pad(1), menusOnly: true) == pad(1))
    #expect(follow.state == .preferred)
}
