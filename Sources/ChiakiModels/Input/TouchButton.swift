/// The state machine for a button that turns the right stick into a touchpad finger while held.
///
/// A short press without moving the stick is passed on as a touchpad click; moving the stick past
/// ``touchThreshold`` while held places a finger that follows the stick.
public struct TouchButton: Equatable, Sendable {
    /// Where the button is.
    public enum Phase: Equatable, Sendable {
        /// Not pressed.
        case idle

        /// Pressed, stick not moved enough yet.
        case held

        /// A finger follows the stick.
        case touching(ControllerTouch)

        /// A click is being passed on until the given microsecond time.
        case clicking(until: UInt64)
    }

    /// How long a passed-on click lasts, in microseconds.
    public static let clickMicroseconds: UInt64 = 100_000

    /// The stick deflection that places a finger.
    public static let touchThreshold = 0.25

    /// How far from the centre full deflection reaches, as a fraction of the touchpad.
    public static let reach = 0.45

    /// The console touchpad.
    public let surface: TouchpadSurface

    /// The current phase.
    public private(set) var phase = Phase.idle

    private var nextID: UInt8 = 0

    /// Creates an idle button.
    ///
    /// - Parameter surface: The console touchpad.
    public init(surface: TouchpadSurface) {
        self.surface = surface
    }

    /// Whether the right stick is withheld from the console.
    public var capturesRightStick: Bool {
        switch phase {
        case .held, .touching:
            true
        case .idle, .clicking:
            false
        }
    }

    /// Whether a click is being passed on.
    public var clicking: Bool {
        if case .clicking = phase {
            return true
        }
        return false
    }

    /// The finger, while touching.
    public var touch: ControllerTouch? {
        if case .touching(let touch) = phase {
            return touch
        }
        return nil
    }

    /// Records the button going down or up.
    ///
    /// - Parameters:
    ///   - down: Whether it was pressed.
    ///   - now: The time in microseconds.
    public mutating func press(down: Bool, at now: UInt64) {
        switch (phase, down) {
        case (.idle, true), (.clicking, true):
            phase = .held
        case (.held, false):
            phase = .clicking(until: now + Self.clickMicroseconds)
        case (.touching, false):
            phase = .idle
        case (.held, true), (.touching, true), (.idle, false), (.clicking, false):
            break
        }
    }

    /// Records the stick position, placing or moving the finger.
    ///
    /// - Parameters:
    ///   - x: The horizontal deflection, -1 to 1.
    ///   - y: The vertical deflection, -1 to 1.
    public mutating func stick(x: Double, y: Double) {
        let magnitude = (x * x + y * y).squareRoot()
        switch phase {
        case .held where magnitude > Self.touchThreshold:
            var touch = point(x: x, y: y)
            touch.id = nextID
            nextID = (nextID + 1) & 0x7f
            phase = .touching(touch)
        case .touching(let current):
            var touch = point(x: x, y: y)
            touch.id = current.id
            phase = .touching(touch)
        case .idle, .held, .clicking:
            break
        }
    }

    /// Ends a passed-on click once its time is up.
    ///
    /// - Parameter now: The time in microseconds.
    /// - Returns: `true` when a click just ended.
    public mutating func tick(at now: UInt64) -> Bool {
        guard case .clicking(let until) = phase, now >= until else {
            return false
        }
        phase = .idle
        return true
    }

    /// Returns to idle.
    public mutating func reset() {
        phase = .idle
    }

    private func point(x: Double, y: Double) -> ControllerTouch {
        surface.point(normalizedX: 0.5 + max(-1, min(1, x)) * Self.reach,
                      normalizedY: 0.5 + max(-1, min(1, y)) * Self.reach)
    }
}
