import ChiakiModels
import CInput

/// Lets menu navigation follow whichever connected controller the user last picked up, instead of staying on
/// the preferred controller.
struct MenuControllerFollow: Equatable {
    /// Which controller drives menu navigation.
    enum State: Equatable {
        /// Menus use the preferred controller chosen by the caller.
        case preferred
        /// Menus follow an adopted controller, identified by its input instance id.
        case adopted(UInt32)
    }

    /// The absolute axis value a navigation stick or trigger must exceed before its movement adopts the
    /// controller.
    static let adoptionThreshold = 20000
    private static let navigationAxes: Set<Int32> = [0, 1, 4, 5]

    /// The controller currently driving menus.
    private(set) var state = State.preferred

    /// Drops any adopted controller so menus return to the preferred one.
    mutating func reset() {
        state = .preferred
    }

    /// Adopts the controller that produced an event when menus are following use and the event is a
    /// deliberate press or stick movement.
    /// - Parameters:
    ///   - event: The raw input event from a controller.
    ///   - current: The instance id of the controller currently driving menus, if any.
    ///   - menusOnly: Whether menus are allowed to follow the controller in use.
    /// - Returns: `true` when the event's controller was newly adopted.
    mutating func adopt(_ event: nx_input_event, current: UInt32?, menusOnly: Bool) -> Bool {
        guard menusOnly, event.instance != current, Self.isAdoptable(event) else {
            return false
        }
        state = .adopted(event.instance)
        return true
    }

    /// Picks the controller that should drive menus, falling back to the preferred one when nothing is
    /// adopted or the adopted controller has disconnected.
    /// - Parameters:
    ///   - available: The controllers currently connected.
    ///   - preferred: The controller to use when none is adopted.
    ///   - menusOnly: Whether menus are allowed to follow the controller in use.
    /// - Returns: The adopted controller when it is still connected, otherwise `preferred`.
    mutating func choose(from available: [ControllerDevice], preferred: ControllerDevice?,
                         menusOnly: Bool) -> ControllerDevice? {
        guard menusOnly, case .adopted(let id) = state else {
            return preferred
        }
        guard let adopted = available.first(where: { $0.id == id }) else {
            state = .preferred
            return preferred
        }
        return adopted
    }

    /// Whether an event is strong enough to adopt its controller: any button press, or a navigation stick or
    /// trigger pushed past `adoptionThreshold`.
    static func isAdoptable(_ event: nx_input_event) -> Bool {
        switch event.kind {
        case ControllerInputEvent.button:
            event.value != 0
        case ControllerInputEvent.axis:
            navigationAxes.contains(event.control) && abs(Int(event.value)) > adoptionThreshold
        default:
            false
        }
    }
}
