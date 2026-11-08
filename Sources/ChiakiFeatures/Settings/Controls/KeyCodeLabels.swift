import ChiakiModels
import Foundation

/// Names keys and bindings: the stable label a binding or shortcut saves, and the label shown for a saved one
/// in the current language.
public enum KeyCodeLabels {
    /// The saved names of keys whose characters are unprintable or ambiguous, such as arrows, function keys
    /// and keypad keys, keyed by virtual key code. They are stored in saved bindings and shortcuts, so they
    /// stay the same in every language.
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

    private static let keypadKeys: [Int: String] = [
        65: ".", 67: "*", 69: "+", 75: "/", 78: "-", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
        87: "5", 88: "6", 89: "7", 91: "8", 92: "9"
    ]

    /// Returns the label a binding or shortcut saves for a key, which is the same in every language.
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
            return numbered(keyCode).english
        }
        return characters.uppercased()
    }

    /// Returns the label shown for a saved binding in the current language.
    ///
    /// - Parameters:
    ///   - binding: The saved binding.
    ///   - family: The controller family whose markings name a gamepad button, or `nil` when it is not known
    ///     and the saved label is shown.
    ///   - layout: Whether gamepad buttons are named by position or by printed label.
    /// - Returns: The key's, mouse button's or controller button's name.
    public static func title(
        for binding: InputBinding,
        family: ControllerFamily? = nil,
        layout: ButtonLayout = .position
    ) -> LocalizedStringResource {
        switch binding.source {
        case .macKey:
            title(forKey: binding.code, label: binding.label)
        case .mouseButton:
            .settingsControlsMouseNumbered(number: binding.code + 1)
        case .gamepadButton:
            family.map { ControllerGlyphs.button(binding.code, family: $0, layout: layout).name }
                ?? .verbatim(binding.label)
        }
    }

    /// Returns the label shown for a saved key in the current language.
    ///
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code.
    ///   - label: The label saved for the key.
    /// - Returns: The key's name, or the saved label for a key named by its character.
    public static func title(forKey keyCode: Int, label: String) -> LocalizedStringResource {
        if let name = shownName(keyCode) {
            return name
        }
        return label == numbered(keyCode).english
            ? numbered(keyCode)
            : .verbatim(label)
    }

    /// Returns a saved keyboard shortcut as shown in the current language, such as `⇧⌘T`.
    ///
    /// - Parameter chord: The saved shortcut.
    /// - Returns: The modifier symbols followed by the key's name.
    public static func title(for chord: KeyChord) -> LocalizedStringResource {
        let key = String(localized: title(forKey: chord.keyCode, label: chord.label))
        return .verbatim(chord.modifiers.symbols + key)
    }

    private static func shownName(_ keyCode: Int) -> LocalizedStringResource? {
        if let key = keypadKeys[keyCode] {
            return .settingsControlsKeyKeypad(key: key)
        }
        switch keyCode {
        case 36:
            return .settingsControlsKeyReturn
        case 48:
            return .settingsControlsKeyTab
        case 49:
            return .settingsControlsKeySpace
        case 51:
            return .settingsControlsKeyDelete
        case 53:
            return .settingsControlsKeyEscape
        case 57:
            return .settingsControlsKeyCapsLock
        case 117:
            return .settingsControlsKeyForwardDelete
        case 114:
            return .settingsControlsKeyHelp
        case 115:
            return .settingsControlsKeyHome
        case 119:
            return .settingsControlsKeyEnd
        case 116:
            return .settingsControlsKeyPageUp
        case 121:
            return .settingsControlsKeyPageDown
        case 71:
            return .settingsControlsKeyKeypad(key: String(localized: .settingsControlsKeyClear))
        case 76:
            return .settingsControlsKeyKeypad(key: String(localized: .settingsControlsKeyEnter))
        default:
            return nil
        }
    }

    private static func numbered(_ keyCode: Int) -> LocalizedStringResource {
        .settingsControlsKeyNumbered(code: String(keyCode))
    }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        guard !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
            return false
        }
        return !(0xE000...0xF8FF).contains(scalar.value)
    }
}
