import ChiakiModels
import CInput
import Testing
@testable import ChiakiNG

@Suite struct CouchSeatRouterTests {
    private func pad(_ id: UInt32, key: String) -> ControllerDevice {
        ControllerDevice(
            id: id, preferenceKey: key, name: "Pad \(id)", transport: "Wireless",
            individual: true, rumble: true, lights: true, motion: true, touchpad: true
        )
    }

    private func button(_ instance: UInt32, control: Int32, value: Int32 = 1) -> nx_input_event {
        nx_input_event(
            instance: instance, kind: ControllerInputEvent.button, control: control, value: value,
            data: (0, 0, 0), timestamp_us: 0
        )
    }

    @Test func aControllerTakesASeatWithItsSavedPreferences() {
        var configuration = ControlsConfiguration()
        var preferences = ControllerPreferences()
        preferences.rumbleStrength = 0.25
        configuration.controllers["two"] = preferences
        var router = CouchSeatRouter()
        let routing = router.route(
            pad: 1,
            device: pad(2, key: "two"),
            configuration: configuration,
            surface: .ps4
        )
        #expect(routing.vacated == nil)
        guard case .controller(let seat) = routing.placement else {
            Issue.record("expected a seated controller")
            return
        }
        #expect(seat.device.id == 2)
        #expect(seat.preferences.rumbleStrength == 0.25)
        #expect(seat.physicalTouchpad.surface == .ps4)
        #expect(router.pad(of: 2) == 1)
        #expect(router.seatedDevices == [2])
    }

    @Test func reroutingAPadVacatesItsController() {
        var router = CouchSeatRouter()
        _ = router.route(
            pad: 1,
            device: pad(2, key: "two"),
            configuration: ControlsConfiguration(),
            surface: .ps5
        )
        let routing = router.route(
            pad: 1,
            device: pad(3, key: "three"),
            configuration: ControlsConfiguration(),
            surface: .ps5
        )
        #expect(routing.vacated?.device.id == 2)
        #expect(router.pad(of: 3) == 1)
        #expect(!router.holds(2))
        let emptied = router.route(pad: 1, device: nil, configuration: ControlsConfiguration(), surface: .ps5)
        #expect(emptied.vacated?.device.id == 3)
        guard case .empty = emptied.placement else {
            Issue.record("expected an empty pad")
            return
        }
        #expect(router.seats.isEmpty)
    }

    @Test func theKeyboardTakesASeatOnlyOnceSeated() {
        var router = CouchSeatRouter()
        _ = router.route(
            pad: 2,
            device: pad(2, key: "two"),
            configuration: ControlsConfiguration(),
            surface: .ps5
        )
        let routing = router.route(
            pad: 2,
            device: .keyboard,
            configuration: ControlsConfiguration(),
            surface: .ps5
        )
        #expect(routing.vacated?.device.id == 2)
        guard case .keyboard = routing.placement else {
            Issue.record("expected the keyboard")
            return
        }
        #expect(router.keyboardPad == 0)
        router.seatKeyboard(on: 2)
        #expect(router.keyboardPad == 2)
        #expect(router.seats.isEmpty)
        router.keyboardLast.buttons = 1
        router.releaseKeyboard()
        #expect(router.keyboardPad == 0)
        #expect(router.keyboardLast == ControllerState())
    }

    @Test func aNewControllerWaitsForAnOpenMenuBeforeItIsOffered() {
        var router = CouchSeatRouter()
        let connected = [pad(1, key: "one"), pad(4, key: "four")]
        let playerOne = router.announcement(for: 1, playerOne: 1, connected: connected, menuBlocked: false)
        #expect(playerOne == .ignored)
        let gone = router.announcement(for: 9, playerOne: 1, connected: connected, menuBlocked: false)
        #expect(gone == .ignored)
        let first = router.announcement(for: 4, playerOne: 1, connected: connected, menuBlocked: true)
        #expect(first == .deferred)
        let again = router.announcement(for: 4, playerOne: 1, connected: connected, menuBlocked: true)
        #expect(again == .deferred)
        let blocked = router.takePending(menuBlocked: true)
        #expect(blocked.isEmpty)
        let released = router.takePending(menuBlocked: false)
        #expect(released == [4])
        let drained = router.takePending(menuBlocked: false)
        #expect(drained.isEmpty)
        let offered = router.announcement(for: 4, playerOne: 1, connected: connected, menuBlocked: false)
        #expect(offered == .announced(pad(4, key: "four")))
    }

    @Test func onlyAnOptionsPressFromAFreeControllerClaimsASeatWhileSeatsAreLive() {
        var router = CouchSeatRouter()
        let connected = [pad(1, key: "one"), pad(4, key: "four")]
        let options = CouchSeatRouter.optionsButton
        #expect(router.claim(button(4, control: options), playerOne: 1, connected: connected) == nil)
        let activated = router.setActive(true)
        #expect(activated)
        let repeated = router.setActive(true)
        #expect(!repeated)
        #expect(router.claim(button(4, control: options), playerOne: 1, connected: connected)?.id == 4)
        #expect(router
            .claim(button(4, control: options, value: 0), playerOne: 1, connected: connected) == nil)
        #expect(router.claim(button(4, control: 0), playerOne: 1, connected: connected) == nil)
        #expect(router.claim(button(1, control: options), playerOne: 1, connected: connected) == nil)
    }
}
