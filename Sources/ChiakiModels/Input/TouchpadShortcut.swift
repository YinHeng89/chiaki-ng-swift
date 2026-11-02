/// The keyboard chord and controller buttons that open the touchpad.
public struct TouchpadShortcut: Codable, Equatable, Sendable {
    /// The default shortcut.
    public static let standard = TouchpadShortcut(
        key: KeyChord(keyCode: 17, modifiers: [.command, .shift], label: "T"),
        buttons: [4, 8]
    )

    /// The keyboard chord, or `nil` for none.
    public var key: KeyChord?

    /// The controller button codes, or empty for none.
    public var buttons: [Int]

    /// Creates a shortcut.
    ///
    /// - Parameters:
    ///   - key: The keyboard chord.
    ///   - buttons: The button codes.
    public init(key: KeyChord?, buttons: [Int]) {
        self.key = key
        self.buttons = buttons
    }

    /// Whether the buttons are none or two or three distinct valid codes, and the chord is allowed.
    public var isValid: Bool {
        let unique = Set(buttons)
        let buttonsValid = buttons.isEmpty
            || (unique.count == buttons.count && (2...3).contains(buttons.count)
                && buttons.allSatisfy { (0...25).contains($0) })
        return buttonsValid && (key?.isAllowed ?? true)
    }
}
