/// The controller button chord that opens the stream menu.
public struct StreamMenuShortcut: Codable, Equatable, Sendable {
    /// The default chord.
    public static let standard = StreamMenuShortcut(buttons: [7, 8])

    /// How many buttons a chord may have.
    public static let buttonLimit = 2...4

    /// The gamepad button codes, in the order chosen.
    public var buttons: [Int]

    /// Creates a shortcut.
    ///
    /// - Parameter buttons: The button codes.
    public init(buttons: [Int]) {
        self.buttons = buttons
    }

    /// The buttons as a set.
    public var chord: Set<Int> {
        Set(buttons)
    }

    /// Whether the chord has distinct, valid buttons within ``buttonLimit``.
    public var isValid: Bool {
        chord.count == buttons.count && Self.buttonLimit.contains(buttons.count)
            && buttons.allSatisfy { (0...25).contains($0) }
    }

    /// Whether one chord contains the other, so pressing one would trigger both.
    ///
    /// - Parameter touchpad: The touchpad shortcut.
    /// - Returns: `true` when either chord is a subset of the other.
    public func overlaps(_ touchpad: TouchpadShortcut) -> Bool {
        let other = Set(touchpad.buttons)
        guard !other.isEmpty else {
            return false
        }
        return chord.isSubset(of: other) || other.isSubset(of: chord)
    }
}
