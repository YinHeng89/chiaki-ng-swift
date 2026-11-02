import Foundation

/// The on-screen touchpad: when it is shown and the gesture under the pointer.
///
/// A pointer press becomes a drag once it moves past the slop, a tap click when released quickly, or a
/// held click after ``TouchpadTiming/longPress``. A touchpad shown by hovering hides itself after
/// ``TouchpadTiming/peek`` without use; one shown by the shortcut stays until toggled.
public struct VirtualTouchpad: Equatable, Sendable {
    /// What the pointer is doing on the touchpad.
    public enum Gesture: Equatable, Sendable {
        /// Nothing.
        case idle

        /// A press that began while the touchpad was hidden; ignored until released.
        case ignoring

        /// A contact not yet resolved into a drag, tap or hold, with where and when it started.
        case pending(ControllerTouch, origin: ControllerTouch, since: TimeInterval)

        /// A contact moving without a click.
        case dragging(ControllerTouch)

        /// A tap click held until the given time.
        case clicking(ControllerTouch, until: TimeInterval)

        /// A long press holding the click, with where it started.
        case holding(ControllerTouch, origin: ControllerTouch)

        /// A long press that moved, still holding the click.
        case holdDragging(ControllerTouch)
    }
    /// Why the touchpad is shown.
    public enum Presence: Equatable, Sendable {
        /// Shown by the shortcut until toggled off.
        case pinned

        /// Shown by hovering until the given time.
        case peeking(until: TimeInterval)
    }
    /// Whether the touchpad is shown.
    public enum Phase: Equatable, Sendable {
        /// Hidden.
        case hidden

        /// Shown, with the gesture and why it is shown.
        case shown(Gesture, Presence)
    }
    /// What the touchpad sends to the console.
    public struct Output: Equatable, Sendable {
        /// Nothing touched or clicked.
        public static let none = Output(touch: nil, clicked: false)

        /// The contact, if any.
        public var touch: ControllerTouch?

        /// Whether the touchpad is clicked.
        public var clicked: Bool
    }

    /// The console touchpad.
    public let surface: TouchpadSurface

    /// The gesture timings.
    public let timing: TouchpadTiming

    /// The current phase.
    public private(set) var phase = Phase.hidden

    private var nextID: UInt8 = 0

    /// Creates a hidden touchpad.
    ///
    /// - Parameters:
    ///   - surface: The console touchpad.
    ///   - timing: The gesture timings.
    public init(surface: TouchpadSurface = .ps5, timing: TouchpadTiming = .standard) {
        self.surface = surface
        self.timing = timing
    }

    /// Whether the touchpad is shown.
    public var isShown: Bool {
        phase != .hidden
    }

    /// The gesture, while shown.
    public var gesture: Gesture? {
        guard case .shown(let gesture, _) = phase else {
            return nil
        }
        return gesture
    }

    /// Why it is shown, while shown.
    public var presence: Presence? {
        guard case .shown(_, let presence) = phase else {
            return nil
        }
        return presence
    }

    /// What to send to the console.
    public var output: Output {
        switch gesture {
        case .none, .idle, .ignoring:
            return .none
        case .pending(let touch, _, _), .dragging(let touch):
            return Output(touch: touch, clicked: false)
        case .clicking(let touch, _), .holding(let touch, _), .holdDragging(let touch):
            return Output(touch: touch, clicked: true)
        }
    }

    /// The half the contact is in, if any.
    public var region: TouchpadRegion? {
        output.touch.map(surface.region(of:))
    }

    /// Shows the touchpad pinned, pins a peeking one, or hides a pinned one.
    public mutating func toggle() {
        switch phase {
        case .hidden:
            phase = .shown(.idle, .pinned)
        case .shown(let gesture, .peeking):
            phase = .shown(gesture, .pinned)
        case .shown(_, .pinned):
            hide()
        }
    }

    /// Shows a hidden touchpad as peeking.
    ///
    /// - Parameter time: The current time.
    public mutating func reveal(at time: TimeInterval) {
        guard phase == .hidden else {
            return
        }
        phase = .shown(.idle, .peeking(until: time + timing.peek))
    }

    /// Hides the touchpad.
    public mutating func hide() {
        phase = .hidden
    }

    /// Ends the gesture without hiding.
    public mutating func cancel() {
        guard isShown else {
            return
        }
        become(.idle)
    }

    /// Records a pointer press.
    ///
    /// - Parameters:
    ///   - x: The horizontal position, 0 to 1.
    ///   - y: The vertical position, 0 to 1.
    ///   - time: The current time.
    public mutating func pointerDown(x: Double, y: Double, at time: TimeInterval) {
        guard let gesture else {
            phase = .shown(.ignoring, .peeking(until: time + timing.peek))
            return
        }
        extendPeek(at: time)
        switch gesture {
        case .idle, .clicking:
            break
        case .ignoring, .pending, .dragging, .holding, .holdDragging:
            return
        }
        var touch = surface.point(normalizedX: x, normalizedY: y)
        touch.id = nextID
        nextID = (nextID + 1) & 0x7f
        become(.pending(touch, origin: touch, since: time))
    }

    /// Records pointer movement.
    ///
    /// - Parameters:
    ///   - x: The horizontal position, 0 to 1.
    ///   - y: The vertical position, 0 to 1.
    ///   - time: The current time.
    public mutating func pointerMoved(x: Double, y: Double, at time: TimeInterval) {
        guard let gesture else {
            return
        }
        extendPeek(at: time)
        let position = surface.point(normalizedX: x, normalizedY: y)
        switch gesture {
        case .idle, .ignoring, .clicking:
            return
        case .pending(let touch, let origin, let since):
            if time - since >= timing.longPress {
                become(.holding(touch, origin: origin))
                pointerMoved(x: x, y: y, at: time)
            } else if exceedsSlop(origin, position) {
                become(.dragging(moved(touch, to: position)))
            } else {
                become(.pending(touch, origin: origin, since: since))
            }
        case .dragging(let touch):
            become(.dragging(moved(touch, to: position)))
        case .holding(let touch, let origin):
            if exceedsSlop(origin, position) {
                become(.holdDragging(moved(touch, to: position)))
            } else {
                become(.holding(touch, origin: origin))
            }
        case .holdDragging(let touch):
            become(.holdDragging(moved(touch, to: position)))
        }
    }

    /// Records the pointer being released.
    ///
    /// - Parameter time: The current time.
    public mutating func pointerUp(at time: TimeInterval) {
        guard let gesture else {
            return
        }
        extendPeek(at: time)
        switch gesture {
        case .pending(let touch, _, _):
            become(.clicking(touch, until: time + timing.clickPulse))
        case .ignoring, .dragging, .holding, .holdDragging:
            become(.idle)
        case .idle, .clicking:
            return
        }
    }

    /// Advances timed transitions: long presses, tap clicks and peeking.
    ///
    /// - Parameter time: The current time.
    public mutating func tick(at time: TimeInterval) {
        switch gesture {
        case .pending(let touch, let origin, let since):
            if time - since >= timing.longPress {
                become(.holding(touch, origin: origin))
            }
        case .clicking(_, let until):
            if time >= until {
                become(.idle)
            }
        case .none, .idle, .ignoring, .dragging, .holding, .holdDragging:
            break
        }
        if case .shown(.idle, .peeking(let until)) = phase, time >= until {
            hide()
        }
    }

    private mutating func become(_ gesture: Gesture) {
        guard let presence else {
            return
        }
        phase = .shown(gesture, presence)
    }

    private mutating func extendPeek(at time: TimeInterval) {
        guard let gesture, case .peeking(let until) = presence else {
            return
        }
        phase = .shown(gesture, .peeking(until: max(until, time + timing.peek)))
    }

    private func moved(_ touch: ControllerTouch, to position: ControllerTouch) -> ControllerTouch {
        ControllerTouch(id: touch.id, x: position.x, y: position.y)
    }

    private func exceedsSlop(_ origin: ControllerTouch, _ position: ControllerTouch) -> Bool {
        let dx = Double(position.x) - Double(origin.x)
        let dy = Double(position.y) - Double(origin.y)
        return dx * dx + dy * dy > timing.slop * timing.slop
    }

    /// A log line for the change from a previous gesture to the current one.
    ///
    /// - Parameter previous: The gesture before the change, or `nil` when hidden.
    /// - Returns: The line, or `nil` when the change is not worth logging.
    public func describe(from previous: Gesture?) -> String? {
        guard let current = gesture else {
            return previous.map { _ in "hidden" }
        }
        switch (previous, current) {
        case (.none, .idle):
            return presence == .pinned
                ? "shown by the shortcut"
                : "shown by hovering"
        case (.none, .ignoring):
            return "shown by a touch"
        case (.some(let previous), .idle):
            return describeRelease(of: previous)
        case (.clicking(let previous, _), .pending(let touch, _, _)):
            return "contact \(previous.id) tap click released and lifted at \(place(previous)); "
                + "contact \(touch.id) down at \(place(touch))"
        case (_, .pending(let touch, _, _)):
            return "contact \(touch.id) down at \(place(touch))"
        case (.pending, _):
            return describeResolution(to: current)
        case (.holding, .holdDragging(let touch)):
            return "contact \(touch.id) long drag started, click held, now at \(place(touch))"
        default:
            return nil
        }
    }

    private func describeResolution(to current: Gesture) -> String? {
        switch current {
        case .dragging(let touch):
            "contact \(touch.id) drag started, now at \(place(touch))"
        case .clicking(let touch, _):
            "contact \(touch.id) tap, click at \(place(touch))"
        case .holding(let touch, _):
            "contact \(touch.id) long press, click held at \(place(touch))"
        default:
            nil
        }
    }

    private func describeRelease(of previous: Gesture) -> String? {
        switch previous {
        case .dragging(let touch):
            "contact \(touch.id) drag ended at \(place(touch))"
        case .holding(let touch, _), .holdDragging(let touch):
            "contact \(touch.id) click released and lifted at \(place(touch))"
        case .clicking(let touch, _):
            "contact \(touch.id) tap click released and lifted at \(place(touch))"
        case .pending(let touch, _, _):
            "contact \(touch.id) cancelled at \(place(touch))"
        default:
            nil
        }
    }

    private func place(_ touch: ControllerTouch) -> String {
        let half = surface.region(of: touch) == .left
            ? "left"
            : "right"
        return "x=\(touch.x) y=\(touch.y) (\(half) half)"
    }
}

/// The timings and distances the virtual touchpad's gestures use.
public struct TouchpadTiming: Equatable, Sendable {
    /// The timings used unless a caller chooses others.
    public static let standard = TouchpadTiming(longPress: 0.4, clickPulse: 0.2, slop: 48, peek: 5)

    /// How long a contact must stay still to become a held click.
    public var longPress: TimeInterval

    /// How long a tap's click is held.
    public var clickPulse: TimeInterval

    /// How far, in touchpad units, a contact may move and still count as still.
    public var slop: Double

    /// How long a touchpad shown by hovering stays visible after the last use.
    public var peek: TimeInterval

    /// Creates timings.
    ///
    /// - Parameters:
    ///   - longPress: The long-press time.
    ///   - clickPulse: The tap click time.
    ///   - slop: The movement tolerance.
    ///   - peek: The hover visibility time.
    public init(longPress: TimeInterval, clickPulse: TimeInterval, slop: Double, peek: TimeInterval) {
        self.longPress = longPress
        self.clickPulse = clickPulse
        self.slop = slop
        self.peek = peek
    }
}
