/// A key with modifiers, used as a keyboard shortcut.
public struct KeyChord: Codable, Equatable, Sendable {
    /// System and app shortcuts a chord may not take over.
    public static let reserved: [KeyChord] = [
        KeyChord(keyCode: 12, modifiers: .command, label: "Q"),
        KeyChord(keyCode: 13, modifiers: .command, label: "W"),
        KeyChord(keyCode: 4, modifiers: .command, label: "H"),
        KeyChord(keyCode: 46, modifiers: .command, label: "M"),
        KeyChord(keyCode: 43, modifiers: .command, label: ","),
        KeyChord(keyCode: 46, modifiers: [.command, .shift], label: "M"),
        KeyChord(keyCode: 2, modifiers: [.command, .shift], label: "D"),
        KeyChord(keyCode: 5, modifiers: [.command, .shift], label: "G"),
        KeyChord(keyCode: 3, modifiers: [.command, .control], label: "F"),
        KeyChord(keyCode: 18, modifiers: [.command, .option], label: "1")
    ]

    /// The virtual key code.
    public var keyCode: Int

    /// The modifiers.
    public var modifiers: ShortcutModifiers

    /// The key's label.
    public var label: String

    /// Creates a chord.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code.
    ///   - modifiers: The modifiers.
    ///   - label: The key's label.
    public init(keyCode: Int, modifiers: ShortcutModifiers, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    /// The chord in its saved, untranslated text, such as `⇧⌘T`.
    public var title: String {
        modifiers.symbols + label
    }

    /// Whether a key press is this chord.
    ///
    /// - Parameters:
    ///   - keyCode: The pressed key.
    ///   - modifiers: The held modifiers.
    /// - Returns: `true` for the same key with exactly these modifiers.
    public func matches(keyCode: Int, modifiers: ShortcutModifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers.intersection(.all)
    }

    /// Whether the chord may be used: a valid key and label, an anchoring modifier and not reserved.
    public var isAllowed: Bool {
        (0...127).contains(keyCode) && !label.isEmpty && label.count <= 40
            && modifiers.isSubset(of: .all) && !modifiers.isDisjoint(with: .anchors)
            && !Self.reserved.contains { $0.keyCode == keyCode && $0.modifiers == modifiers }
    }
}

/// The modifier keys of a keyboard shortcut.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    /// Control.
    public static let control = ShortcutModifiers(rawValue: 1)

    /// Option.
    public static let option = ShortcutModifiers(rawValue: 2)

    /// Shift.
    public static let shift = ShortcutModifiers(rawValue: 4)

    /// Command.
    public static let command = ShortcutModifiers(rawValue: 8)

    /// Every modifier.
    public static let all: ShortcutModifiers = [.control, .option, .shift, .command]

    /// The modifiers of which a shortcut must use at least one, so plain typing never triggers it.
    public static let anchors: ShortcutModifiers = [.control, .option, .command]

    /// The bit mask.
    public let rawValue: Int

    /// Creates modifiers from a bit mask.
    ///
    /// - Parameter rawValue: The mask.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The modifier symbols in the standard macOS order.
    public var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }
            .map(\.1)
            .joined()
    }
}
