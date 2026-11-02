import Foundation

/// Turns macOS virtual key codes into the names shown for keyboard bindings.
public enum KeyCodeLabels {
    /// Names for keys whose characters are unprintable or ambiguous, such as arrows, function keys and keypad
    /// keys, keyed by virtual key code.
    public static let names: [Int: String] = [
        27: "-", 36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape", 57: "Caps Lock",
        117: "Forward Delete", 114: "Help", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear", 75: "Keypad /",
        76: "Keypad Enter", 78: "Keypad -", 81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1",
        84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6",
        89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9"
    ]

    /// Returns the display name of a key.
    ///
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code.
    ///   - characters: The characters the key produced, if any.
    /// - Returns: A fixed name for special keys, otherwise the uppercased printable characters, or "Key N"
    ///   when there are none.
    public static func label(for keyCode: Int, characters: String?) -> String {
        if let name = names[keyCode] {
            return name
        }
        guard let characters, !characters.isEmpty, characters.unicodeScalars.allSatisfy(isPrintable) else {
            return "Key \(keyCode)"
        }
        return characters.uppercased()
    }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        guard !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
            return false
        }
        return !(0xE000...0xF8FF).contains(scalar.value)
    }
}
