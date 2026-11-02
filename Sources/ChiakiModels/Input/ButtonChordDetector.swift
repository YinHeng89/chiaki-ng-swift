/// Detects a controller button chord once per press and hides its buttons until they are released.
public struct ButtonChordDetector: Equatable, Sendable {
    /// Whether the chord can fire.
    public enum Phase: Equatable, Sendable {
        /// Waiting for the chord.
        case armed

        /// Fired; waiting for its buttons to be released.
        case fired
    }

    /// The chord's buttons.
    public private(set) var chord: Set<Int>

    /// The current phase.
    public private(set) var phase = Phase.armed

    private var held = Set<Int>()

    /// Creates an armed detector.
    ///
    /// - Parameter buttons: The chord's button codes.
    public init(buttons: [Int]) {
        chord = Set(buttons)
    }

    /// Changes the chord and re-arms.
    ///
    /// - Parameter buttons: The new button codes.
    public mutating func configure(buttons: [Int]) {
        chord = Set(buttons)
        phase = .armed
    }

    /// Forgets held buttons and re-arms.
    public mutating func reset() {
        held.removeAll()
        phase = .armed
    }

    /// Records a button change.
    ///
    /// - Parameters:
    ///   - code: The button code.
    ///   - down: Whether it was pressed.
    /// - Returns: `true` when this press completed the chord.
    public mutating func button(_ code: Int, down: Bool) -> Bool {
        if down {
            held.insert(code)
        } else {
            held.remove(code)
        }
        switch phase {
        case .armed:
            guard down, chord.count >= 2, chord.contains(code), chord.isSubset(of: held) else {
                return false
            }
            phase = .fired
            return true
        case .fired:
            if held.isDisjoint(with: chord) {
                phase = .armed
            }
            return false
        }
    }

    /// Whether a button is held back from the console because it belongs to a fired chord.
    ///
    /// - Parameter code: The button code.
    /// - Returns: `true` while the chord has fired.
    public func suppresses(_ code: Int) -> Bool {
        phase == .fired && chord.contains(code)
    }
}
