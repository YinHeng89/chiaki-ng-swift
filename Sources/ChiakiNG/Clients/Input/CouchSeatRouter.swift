import ChiakiModels
import CInput

/// Which controller or keyboard plays on each couch seat, and which new controllers to offer a seat.
///
/// Pads 1 to 3 are players two to four. A seat holds a controller, or the keyboard plays on it instead; the
/// keyboard plays as player one while it holds no seat. The router only decides; the
/// ``StreamInputSession`` performs what each decision asks of the player and the controllers.
struct CouchSeatRouter {
    /// What a pad holds after a routing.
    enum Placement {
        /// The keyboard plays on the pad.
        case keyboard
        /// A controller plays on the pad.
        case controller(SeatedController)
        /// Nothing plays on the pad.
        case empty
    }

    /// The outcome of routing a pad.
    struct Routing {
        /// The seat the pad held before, whose controller must stop playing.
        let vacated: SeatedController?
        /// What the pad holds now.
        let placement: Placement
    }

    /// What to do about a controller that just connected.
    enum Announcement: Equatable {
        /// It is player one, already seated, or gone.
        case ignored
        /// A menu is open; it is offered once the menu closes.
        case deferred
        /// Offer it a seat.
        case announced(ControllerDevice)
    }

    /// The options button, which claims a seat for a free controller.
    static let optionsButton: Int32 = 6

    /// The seated controllers by pad.
    private(set) var seats: [UInt8: SeatedController] = [:]

    /// The pad the keyboard plays on; `0` while it plays as player one.
    private(set) var keyboardPad: UInt8 = 0

    /// The last state the keyboard sent on its seat.
    var keyboardLast = ControllerState()

    /// Whether the seats' controllers currently reach the stream.
    private(set) var isActive = false

    private var pending: [UInt32] = []

    /// The ids of every seated controller.
    var seatedDevices: Set<UInt32> {
        Set(seats.values.map(\.device.id))
    }

    /// Whether a controller sits on a seat.
    ///
    /// - Parameter instance: The controller's id.
    /// - Returns: `true` when a seat holds it.
    func holds(_ instance: UInt32) -> Bool {
        seats.values.contains { $0.device.id == instance }
    }

    /// The pad a controller plays on.
    ///
    /// - Parameter instance: The controller's id.
    /// - Returns: The pad, or `nil` when no seat holds it.
    func pad(of instance: UInt32) -> UInt8? {
        seats.first { $0.value.device.id == instance }?.key
    }

    /// Moves the keyboard back to player one.
    mutating func releaseKeyboard() {
        keyboardPad = 0
        keyboardLast = ControllerState()
    }

    /// Moves the keyboard onto a seat's pad, once ``route(pad:device:configuration:surface:)`` cleared it.
    ///
    /// - Parameter pad: The pad.
    mutating func seatKeyboard(on pad: UInt8) {
        keyboardPad = pad
        keyboardLast = ControllerState()
    }

    /// Puts a controller or nothing on a pad, or clears it for the keyboard.
    ///
    /// - Parameters:
    ///   - pad: The pad.
    ///   - device: The controller, the keyboard, or `nil` to empty the pad.
    ///   - configuration: Where a controller's preferences come from.
    ///   - surface: The console's touchpad surface.
    /// - Returns: The seat the pad gave up and what it holds now; for the keyboard, call
    ///   ``seatKeyboard(on:)`` once the keyboard's player one state is published.
    mutating func route(
        pad: UInt8,
        device: ControllerDevice?,
        configuration: ControlsConfiguration,
        surface: TouchpadSurface
    ) -> Routing {
        let vacated = seats.removeValue(forKey: pad)
        if let device, device.isKeyboard {
            return Routing(vacated: vacated, placement: .keyboard)
        }
        guard let device else {
            return Routing(vacated: vacated, placement: .empty)
        }
        let seat = SeatedController(
            device: device,
            preferences: configuration.controllers[device.preferenceKey] ?? .init(),
            physicalTouchpad: PhysicalTouchpad(surface: surface)
        )
        seats[pad] = seat
        return Routing(vacated: vacated, placement: .controller(seat))
    }

    /// Records whether the seats' controllers reach the stream, forgetting their touches when it changes.
    ///
    /// - Parameter active: Whether they reach it.
    /// - Returns: `true` when this changed.
    mutating func setActive(_ active: Bool) -> Bool {
        guard active != isActive else {
            return false
        }
        isActive = active
        for pad in Array(seats.keys) {
            seats[pad]?.physicalTouchpad.reset()
        }
        return true
    }

    /// Takes each seat's preferences from a new configuration.
    ///
    /// - Parameter configuration: The configuration.
    mutating func reload(_ configuration: ControlsConfiguration) {
        for pad in Array(seats.keys) {
            guard let seat = seats[pad] else {
                continue
            }
            seats[pad]?.preferences = configuration.controllers[seat.device.preferenceKey] ?? .init()
        }
    }

    /// Applies a touchpad event to a seat's touchpad.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - pad: The seat's pad.
    ///   - avoiding: Touch ids the console still holds for the pad.
    mutating func touch(_ event: nx_input_event, pad: UInt8, avoiding: Set<UInt8>) {
        guard var seat = seats[pad] else {
            return
        }
        TouchpadInput.apply(event, to: &seat.physicalTouchpad, avoiding: avoiding)
        seats[pad] = seat
    }

    /// Decides whether a controller that just connected is offered a seat.
    ///
    /// - Parameters:
    ///   - instance: The controller's id.
    ///   - playerOne: Player one's controller id.
    ///   - connected: The connected controllers, read only when needed.
    ///   - menuBlocked: Whether a menu holds the controllers.
    /// - Returns: The decision; a deferred controller is queued until ``takePending(menuBlocked:)``.
    mutating func announcement(
        for instance: UInt32,
        playerOne: UInt32?,
        connected: @autoclosure () -> [ControllerDevice],
        menuBlocked: Bool
    ) -> Announcement {
        guard instance != playerOne, !holds(instance),
              let device = connected().first(where: { $0.id == instance }) else {
            return .ignored
        }
        guard !menuBlocked else {
            if !pending.contains(instance) {
                pending.append(instance)
            }
            return .deferred
        }
        return .announced(device)
    }

    /// Takes the controllers whose offer waited for a menu to close.
    ///
    /// - Parameter menuBlocked: Whether a menu still holds the controllers.
    /// - Returns: The waiting controllers, or nothing while the menu stays open.
    mutating func takePending(menuBlocked: Bool) -> [UInt32] {
        guard !pending.isEmpty, !menuBlocked else {
            return []
        }
        let taken = pending
        pending = []
        return taken
    }

    /// The free controller whose options press claims a seat.
    ///
    /// - Parameters:
    ///   - input: A controller event no seat's controller sent.
    ///   - playerOne: Player one's controller id.
    ///   - connected: The connected controllers, read only when needed.
    /// - Returns: The controller, or `nil` when the event claims nothing.
    func claim(
        _ input: nx_input_event,
        playerOne: UInt32?,
        connected: @autoclosure () -> [ControllerDevice]
    ) -> ControllerDevice? {
        guard isActive, input.kind == ControllerInputEvent.button, input.value != 0,
              input.control == Self.optionsButton,
              input.instance != playerOne else {
            return nil
        }
        return connected().first { $0.id == input.instance }
    }
}
