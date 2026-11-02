/// The on-screen gamepad's state, built from control presses and stick moves.
public struct VirtualGamepad: Equatable, Sendable {
    /// One of the two sticks.
    public enum Stick: Equatable, Sendable {
        /// The left stick.
        case left

        /// The right stick.
        case right
    }

    /// The state to send.
    public private(set) var state = ControllerState()

    private var held = Set<PlayStationControl>()

    /// Creates an idle gamepad.
    public init() {
    }

    /// Whether nothing is pressed or deflected.
    public var isIdle: Bool {
        state == ControllerState()
    }

    /// Whether a control is held.
    ///
    /// - Parameter control: The control.
    /// - Returns: `true` while it is pressed.
    public func holds(_ control: PlayStationControl) -> Bool {
        held.contains(control)
    }

    /// Presses or releases a control.
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - down: Whether it is pressed.
    public mutating func press(_ control: PlayStationControl, down: Bool) {
        if down {
            held.insert(control)
        } else {
            held.remove(control)
        }
        switch control {
        case .leftTrigger:
            state.leftTrigger = down
                ? .max
                : 0
        case .rightTrigger:
            state.rightTrigger = down
                ? .max
                : 0
        default:
            guard let bit = control.bit else {
                return
            }
            if down {
                state.buttons |= bit
            } else {
                state.buttons &= ~bit
            }
        }
    }

    /// Moves a stick, clamping the deflection to the unit circle.
    ///
    /// - Parameters:
    ///   - stick: The stick.
    ///   - x: The horizontal deflection, -1 to 1.
    ///   - y: The vertical deflection, -1 to 1.
    public mutating func move(_ stick: Stick, x: Double, y: Double) {
        let length = (x * x + y * y).squareRoot()
        let scale = length > 1
            ? 1 / length
            : 1
        let horizontal = Self.axis(x * scale)
        let vertical = Self.axis(y * scale)
        switch stick {
        case .left:
            state.leftX = horizontal
            state.leftY = vertical
        case .right:
            state.rightX = horizontal
            state.rightY = vertical
        }
    }

    /// Centres a stick.
    ///
    /// - Parameter stick: The stick.
    public mutating func release(_ stick: Stick) {
        move(stick, x: 0, y: 0)
    }

    /// Releases every control and centres both sticks.
    public mutating func releaseAll() {
        held.removeAll()
        state = ControllerState()
    }

    private static func axis(_ value: Double) -> Int16 {
        guard value.isFinite else {
            return 0
        }
        return Int16((max(-1, min(1, value)) * Double(Int16.max)).rounded())
    }
}

/// When the on-screen gamepad is shown over a touch stream: following controller connection, always or
/// never.
///
/// ``ControlsConfiguration/virtualGamepad`` saves the choice each stream starts with, and the stream's
/// own toggle can override it until the stream ends.
public enum VirtualGamepadPresence: String, Codable, Equatable, Sendable, CaseIterable {
    /// Shown only while no physical controller is connected.
    case automatic

    /// Always shown.
    case shown

    /// Never shown.
    case hidden

    /// Reports whether the gamepad should be visible.
    ///
    /// - Parameter controllerConnected: Whether a physical controller is connected.
    /// - Returns: `true` when the gamepad should be on screen.
    public func isVisible(controllerConnected: Bool) -> Bool {
        switch self {
        case .automatic:
            !controllerConnected
        case .shown:
            true
        case .hidden:
            false
        }
    }

    /// Returns the presence that flips the gamepad's current visibility.
    ///
    /// - Parameter controllerConnected: Whether a physical controller is connected.
    /// - Returns: ``hidden`` when the gamepad is visible, otherwise ``shown``.
    public func toggled(controllerConnected: Bool) -> Self {
        isVisible(controllerConnected: controllerConnected)
            ? .hidden
            : .shown
    }
}
