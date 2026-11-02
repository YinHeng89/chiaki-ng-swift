import CInput
import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import Foundation

/// The couch seats of one stream: the controllers, or the keyboard, that play as players two to four.
///
/// ``CouchSeatRouter`` decides who sits where; this applies its decisions to the input pipeline and the
/// controllers. It offers newly connected controllers a seat, seats a free controller whose options button is
/// pressed unless player one pressed it at the same moment, which marks the same controller seen over a
/// second link (``MirroredClaimFilter``), forwards each seat's touchpad, and keeps the seats' lanes and rumble
/// live only while the stream window has input.
@MainActor
final class CouchSeatInput {
    private let environment: InputEnvironment
    private let rumble: RumbleDriver
    private var router = CouchSeatRouter()
    private var mirror = MirroredClaimFilter()

    /// Creates the empty seats of a stream.
    ///
    /// - Parameters:
    ///   - environment: The pipeline and controllers the seats reach.
    ///   - rumble: The rumble driver shared with player one.
    init(environment: InputEnvironment, rumble: RumbleDriver) {
        self.environment = environment
        self.rumble = rumble
    }

    /// Every occupied seat, by pad.
    var seats: [UInt8: SeatedController] {
        router.seats
    }

    /// The pads with someone on them.
    var pads: [UInt8] {
        Array(router.seats.keys)
    }

    /// The controllers sitting on a seat.
    var seatedDevices: Set<UInt32> {
        router.seatedDevices
    }

    /// The pad the keyboard plays on, or `0` while it plays as player one.
    var keyboardPad: UInt8 {
        router.keyboardPad
    }

    /// What the keyboard's seat last sent to the console.
    var keyboardLast: ControllerState {
        get {
            router.keyboardLast
        }
        set {
            router.keyboardLast = newValue
        }
    }

    /// Whether the seats receive input.
    var isActive: Bool {
        router.isActive
    }

    /// Whether a controller sits on a seat.
    ///
    /// - Parameter instance: The controller's id.
    /// - Returns: `true` when it is seated.
    func holds(_ instance: UInt32) -> Bool {
        router.holds(instance)
    }

    /// Applies a changed controls configuration to every seat.
    ///
    /// - Parameter configuration: The configuration.
    func reload(_ configuration: ControlsConfiguration) {
        router.reload(configuration)
    }

    /// Puts a controller, the keyboard or nothing on a seat.
    ///
    /// - Parameters:
    ///   - pad: The seat's pad.
    ///   - device: The controller or keyboard, or `nil` to empty the seat.
    ///   - configuration: The controls configuration the seat plays with.
    ///   - surface: The console's touchpad surface.
    /// - Returns: Who left the seat and what sits on it now.
    func route(
        pad: UInt8,
        device: ControllerDevice?,
        configuration: ControlsConfiguration,
        surface: TouchpadSurface
    ) -> CouchSeatRouter.Routing {
        router.route(pad: pad, device: device, configuration: configuration, surface: surface)
    }

    /// Takes the keyboard off its seat.
    func releaseKeyboard() {
        router.releaseKeyboard()
    }

    /// Seats the keyboard.
    ///
    /// - Parameter pad: The seat's pad.
    func seatKeyboard(on pad: UInt8) {
        router.seatKeyboard(on: pad)
    }

    /// Silences a controller that left a seat and frees the seat's lane.
    ///
    /// - Parameters:
    ///   - vacated: The controller that left, if any.
    ///   - pad: The seat's pad.
    func release(_ vacated: SeatedController?, pad: UInt8) {
        guard let vacated else {
            return
        }
        quiet(vacated.device)
        environment.pipeline.release(pad: pad)
    }

    /// Stops the rumble of a seat that no controller plays on any more.
    ///
    /// - Parameter pad: The seat's pad.
    func vacate(_ pad: UInt8) {
        rumble.vacate(pad)
    }

    /// Starts the rumble of a seat a controller now plays on, and logs who plays there.
    ///
    /// - Parameters:
    ///   - seat: The seated controller.
    ///   - pad: The seat's pad.
    func seat(_ seat: SeatedController, on pad: UInt8) {
        rumble.seat(pad)
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(
            "\"\(seat.device.name)\" plays as player \(Int(pad) + 1)"
        ))
    }

    /// Turns the seats' input on or off, silencing every seated controller when it goes off.
    ///
    /// - Parameter active: Whether the stream window has input.
    /// - Returns: `true` when the seats' activity changed.
    func setActive(_ active: Bool) -> Bool {
        guard router.setActive(active) else {
            return false
        }
        for pad in pads {
            environment.pipeline.setLive(pad: pad, active)
            rumble.silenceSeat(pad)
            if !active, let seat = router.seats[pad] {
                quiet(seat.device)
            }
        }
        return true
    }

    /// Reads the fingers already on every seated controller's touchpad.
    func seedTouchpads() {
        for (pad, seat) in router.seats {
            for event in environment.backend.touchFingers(seat.device.id) {
                router.touch(event, pad: pad, avoiding: environment.pipeline.lastSent(pad: pad).touches.ids)
            }
        }
    }

    /// Handles the events of controllers other than player one's.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - playerOne: Player one's controller id.
    /// - Returns: The controllers that just connected, to be offered a seat once they settle.
    func process(_ events: [nx_input_event], playerOne: UInt32?) -> [UInt32] {
        var added: [UInt32] = []
        for input in events {
            if input.kind == ControllerInputEvent.added {
                added.append(input.instance)
            } else {
                process(input, playerOne: playerOne)
            }
        }
        return added
    }

    /// Notes one of player one's events, so a seat claim that only repeats player one's press is dropped.
    ///
    /// - Parameter event: The event.
    func notePlayerOne(_ event: nx_input_event) {
        mirror.notePlayerOne(event)
    }

    /// Hands on the seat claims whose short hold has passed without player one making the same press, so the
    /// same controller seen over a second link never takes a seat.
    ///
    /// - Parameter playerOne: Player one's controller id.
    func releaseClaims(playerOne: UInt32?) {
        let standing = mirror.release(now: nx_input_now_us())
        guard !standing.isEmpty else {
            return
        }
        let connected = environment.connectedDevices()
        for instance in standing where instance != playerOne && !router.holds(instance) {
            guard let claimed = connected.first(where: { $0.id == instance }) else {
                continue
            }
            let report = environment.report
            Task {
                await report(.couch(.controllerClaimed(claimed)))
            }
        }
    }

    /// Sends every seat's touchpad and drains the seats' rumble.
    func publish() {
        if router.isActive {
            for pad in pads {
                publishOverlay(pad)
            }
        }
        rumble.drainSeats(router.seats, active: router.isActive)
    }

    /// Offers a seat to the controllers that connected while a menu held the controllers.
    ///
    /// - Parameter playerOne: Player one's controller id.
    func announcePending(playerOne: UInt32?) {
        for instance in router.takePending(menuBlocked: environment.coordinator.menuInputBlocked) {
            announce(instance, playerOne: playerOne)
        }
    }

    /// Offers a seat to a connected controller that is neither player one nor seated.
    ///
    /// - Parameters:
    ///   - instance: The controller's id.
    ///   - playerOne: Player one's controller id.
    func announce(_ instance: UInt32, playerOne: UInt32?) {
        let announcement = router.announcement(
            for: instance,
            playerOne: playerOne,
            connected: environment.connectedDevices(),
            menuBlocked: environment.coordinator.menuInputBlocked
        )
        guard case .announced(let connected) = announcement else {
            return
        }
        let report = environment.report
        Task {
            await report(.couch(.controllerConnected(connected)))
        }
    }

    /// Gives a seat's lane the seated controller and the configuration.
    ///
    /// - Parameters:
    ///   - pad: The seat's pad.
    ///   - configuration: The controls configuration.
    ///   - surface: The console's touchpad surface.
    func assignLane(pad: UInt8, configuration: ControlsConfiguration, surface: TouchpadSurface) {
        guard let seat = router.seats[pad] else {
            return
        }
        environment.pipeline.assign(pad: pad, GameInputLane.Assignment(
            seat: seat,
            player: Int(pad),
            configuration: configuration,
            touchSurface: surface
        ), live: router.isActive)
    }

    private func process(_ input: nx_input_event, playerOne: UInt32?) {
        if input.kind == ControllerInputEvent.removed {
            mirror.forget(input.instance)
            if router.holds(input.instance) {
                let removed = input.instance
                let report = environment.report
                Task {
                    await report(.couch(.controllerRemoved(removed)))
                }
            }
            return
        }
        guard let pad = router.pad(of: input.instance) else {
            if router.claim(input, playerOne: playerOne, connected: environment.connectedDevices()) != nil {
                mirror.hold(input)
            }
            return
        }
        guard router.isActive, ControllerInputEvent.isTouch(input) else {
            return
        }
        router.touch(input, pad: pad, avoiding: environment.pipeline.lastSent(pad: pad).touches.ids)
        publishOverlay(pad)
    }

    private func publishOverlay(_ pad: UInt8) {
        guard let seat = router.seats[pad] else {
            return
        }
        environment.pipeline.setOverlay(
            pad: pad, GameInputLane.Overlay(touches: seat.physicalTouchpad.touches)
        )
    }

    private func quiet(_ device: ControllerDevice) {
        if device.adaptiveTriggers {
            environment.backend.resetFeedback(device.id)
        } else {
            environment.backend.rumble(device.id, level: .off)
        }
    }
}
