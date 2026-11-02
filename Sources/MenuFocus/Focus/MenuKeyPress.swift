import SwiftUI

#if os(macOS)
    /// A key press delivered to ``SwiftUICore/View/onMenuKeyPress(keys:phases:action:)``: SwiftUI's `KeyPress`
    /// on macOS.
    public typealias MenuKeyPress = KeyPress
#else
    /// A key press delivered to ``SwiftUI/View/onMenuKeyPress(keys:phases:action:)``.
    ///
    /// iOS has no hardware-independent key handling for focus stops, so the touch navigator synthesises
    /// these presses itself and routes them up the focused control's node chain.
    public struct MenuKeyPress: Sendable {
        /// The phases of a key press a handler can ask for.
        public struct Phases: OptionSet, Sendable {
            /// The phase's bit.
            public let rawValue: Int

            /// Creates a phase set.
            ///
            /// - Parameter rawValue: The phase bits.
            public init(rawValue: Int) {
                self.rawValue = rawValue
            }

            /// The key went down.
            public static let down = Phases(rawValue: 1)
            /// The key repeated while held.
            public static let `repeat` = Phases(rawValue: 2)
            /// The key went up.
            public static let up = Phases(rawValue: 4)
            /// Every phase.
            public static let all: Phases = [.down, .repeat, .up]
        }

        /// Whether a handler used a key press.
        public enum Result: Sendable {
            /// The press was used and goes no further.
            case handled
            /// The press passes on to the next handler.
            case ignored
        }

        /// The key pressed.
        public let key: KeyEquivalent

        /// The characters the press produces.
        public let characters: String

        /// The modifier keys held.
        public let modifiers: EventModifiers

        /// The phase of the press.
        public let phase: Phases

        /// Creates a key press.
        ///
        /// - Parameters:
        ///   - key: The key pressed.
        ///   - characters: The characters it produces.
        ///   - modifiers: The modifier keys held.
        ///   - phase: The phase of the press.
        public init(key: KeyEquivalent, characters: String, modifiers: EventModifiers, phase: Phases) {
            self.key = key
            self.characters = characters
            self.modifiers = modifiers
            self.phase = phase
        }
    }
#endif
