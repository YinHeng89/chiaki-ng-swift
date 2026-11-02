#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
#if os(macOS)
    import AppKit
#else
    import GameController
#endif

/// Tracks keyboard state as a USB HID boot keyboard report, with modifier bits, the Caps Lock light and held
/// key usages, for passing a physical keyboard straight to the console.
struct StreamRawKeyboard {
    /// One HID keyboard report.
    struct Report: Equatable {
        /// The bitmask of held modifier keys in HID order.
        var modifiers: UInt8
        /// The keyboard LED bitmask, where ``StreamRawKeyboard/capsLockLight`` marks Caps Lock.
        var leds: UInt8
        /// The HID usages of held non-modifier keys in the order they were pressed.
        var keys: [UInt16]
    }

    /// The HID usage of Caps Lock.
    static let capsLock: UInt16 = 0x39
    /// The HID usages of the eight modifier keys.
    static let modifierUsages: ClosedRange<UInt16> = 0xE0...0xE7
    /// The LED bit for Caps Lock.
    static let capsLockLight: UInt8 = 0x02
    /// The most held keys a report carries.
    static let maxKeys = 16

    private var held: [UInt16] = []
    private var modifiers: UInt8 = 0
    private var leds: UInt8 = 0

    /// The report describing the current state, limited to ``StreamRawKeyboard/maxKeys`` held keys.
    var report: Report {
        Report(modifiers: modifiers, leds: leds, keys: Array(held.prefix(Self.maxKeys)))
    }

    /// Applies a key press or release by HID usage, updating modifier bits, toggling the Caps Lock light on
    /// press, or adding or removing a held key.
    /// - Parameters:
    ///   - usage: The HID usage of the key.
    ///   - down: Whether the key went down.
    /// - Returns: `true` when the report changed.
    mutating func press(usage: UInt16, down: Bool) -> Bool {
        let before = report
        if Self.modifierUsages.contains(usage) {
            let bit = UInt8(1) << UInt8(usage - Self.modifierUsages.lowerBound)
            modifiers = down
                ? modifiers | bit
                : modifiers & ~bit
        } else if usage == Self.capsLock {
            if down {
                leds ^= Self.capsLockLight
            }
        } else if down {
            if !held.contains(usage) {
                held.append(usage)
            }
        } else {
            held.removeAll {
                $0 == usage
            }
        }
        return report != before
    }

    /// Releases every held key and modifier while keeping the LED state.
    /// - Returns: `true` when the report changed.
    mutating func releaseAll() -> Bool {
        let before = report
        held.removeAll()
        modifiers = 0
        return report != before
    }

    #if os(macOS)
        private static let usages: [UInt16: UInt16] = [
            0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A, 6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19,
            10: 0x64, 11: 0x05, 12: 0x14, 13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C, 17: 0x17, 18: 0x1E,
            19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22, 24: 0x2E, 25: 0x26, 26: 0x24, 27: 0x2D,
            28: 0x25, 29: 0x27, 30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2F, 34: 0x0C, 35: 0x13, 36: 0x28,
            37: 0x0F, 38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33, 42: 0x31, 43: 0x36, 44: 0x38, 45: 0x11,
            46: 0x10, 47: 0x37, 48: 0x2B, 49: 0x2C, 50: 0x35, 51: 0x2A, 53: 0x29, 65: 0x63, 67: 0x55,
            69: 0x57, 71: 0x53, 75: 0x54, 76: 0x58, 78: 0x56, 81: 0x67, 82: 0x62, 83: 0x59, 84: 0x5A,
            85: 0x5B, 86: 0x5C, 87: 0x5D, 88: 0x5E, 89: 0x5F, 91: 0x60, 92: 0x61, 93: 0x89, 94: 0x87,
            96: 0x3E, 97: 0x3F, 98: 0x40, 99: 0x3C, 100: 0x41, 101: 0x42, 102: 0x91, 103: 0x44,
            104: 0x90, 105: 0x68, 107: 0x69, 109: 0x43, 111: 0x45, 113: 0x6A, 114: 0x49, 115: 0x4A,
            116: 0x4B, 117: 0x4C, 118: 0x3D, 119: 0x4D, 120: 0x3B, 121: 0x4E, 122: 0x3A, 123: 0x50,
            124: 0x4F, 125: 0x51, 126: 0x52
        ]

        private static let modifierMasks: [(device: UInt, bit: UInt8)] = [
            (0x0001, 0x01),
            (0x0002, 0x02),
            (0x0020, 0x04),
            (0x0008, 0x08),
            (0x2000, 0x10),
            (0x0004, 0x20),
            (0x0040, 0x40),
            (0x0010, 0x80)
        ]

        /// Applies an AppKit key or modifier event, mapping Mac key codes to HID usages.
        /// - Parameter event: A `keyDown`, `keyUp` or `flagsChanged` event.
        /// - Returns: `true` when the report changed.
        mutating func apply(_ event: NSEvent) -> Bool {
            let before = report
            switch event.type {
            case .flagsChanged:
                let raw = event.modifierFlags.rawValue
                modifiers = Self.modifierMasks.reduce(0) { result, entry in
                    raw & entry.device != 0
                        ? result | entry.bit
                        : result
                }
                leds = event.modifierFlags.contains(.capsLock)
                    ? Self.capsLockLight
                    : 0
                return report != before
            case .keyDown, .keyUp:
                guard let usage = Self.usages[event.keyCode] else {
                    return false
                }
                return press(usage: usage, down: event.type == .keyDown)
            default:
                return false
            }
        }

        /// Reports whether an AppKit event can be expressed as a HID keyboard report.
        /// - Parameter event: The event to test.
        /// - Returns: `true` for modifier changes and keys with a known HID usage.
        static func handles(_ event: NSEvent) -> Bool {
            switch event.type {
            case .flagsChanged:
                true
            case .keyDown, .keyUp:
                usages[event.keyCode] != nil
            default:
                false
            }
        }
    #else
        /// Converts a Game Controller key code to its HID usage.
        /// - Parameter code: The key code from a `GCKeyboard`.
        /// - Returns: The HID usage, or `nil` when the code is outside the usage range.
        static func usage(_ code: GCKeyCode) -> UInt16? {
            let value = code.rawValue
            guard value > 0, value <= Int(UInt16.max) else {
                return nil
            }
            return UInt16(value)
        }
    #endif
}
