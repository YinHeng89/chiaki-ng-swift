#if os(macOS)
    import AppKit
    import PlatformUI

    /// Synthesises key presses for controller commands and remembers the recent ones, so keyboard
    /// customisation can tell them apart from keys the user typed.
    @MainActor
    final class AppKitKeySynthesizer {
        private let capacity = 64
        private var recent = [NSEvent]()

        /// Whether an event is one this synthesiser posted recently.
        ///
        /// - Parameter event: A key event.
        /// - Returns: `true` for a synthesised event.
        func synthesised(_ event: NSEvent) -> Bool {
            recent.contains { candidate in
                candidate === event
            }
        }

        /// Forgets every remembered event.
        func reset() {
            recent.removeAll()
        }

        /// Delivers an arrow key press.
        ///
        /// - Parameters:
        ///   - arrow: The arrow key.
        ///   - window: The window that receives the events.
        ///   - deliver: Delivers each event.
        func press(_ arrow: MenuArrowKey, in window: PlatformWindow, deliver: (NSEvent) -> Void) {
            press(code: arrow.keyCode, characters: arrow.characters, in: window, deliver: deliver)
        }

        /// Delivers the key that confirms the focused control: Return for text and native menus, Space for
        /// every other control.
        ///
        /// - Parameters:
        ///   - returnKey: Whether Return confirms rather than Space.
        ///   - window: The window that receives the events.
        ///   - deliver: Delivers each event.
        func pressConfirm(returnKey: Bool, in window: PlatformWindow, deliver: (NSEvent) -> Void) {
            if returnKey {
                press(code: 36, characters: "\r", in: window, deliver: deliver)
            } else {
                press(code: 49, characters: " ", in: window, deliver: deliver)
            }
        }

        /// Delivers an Escape press.
        ///
        /// - Parameters:
        ///   - window: The window that receives the events.
        ///   - deliver: Delivers each event.
        func pressEscape(in window: PlatformWindow, deliver: (NSEvent) -> Void) {
            press(code: 53, characters: "\u{1b}", in: window, deliver: deliver)
        }

        /// Delivers a key down and key up for a key.
        ///
        /// - Parameters:
        ///   - code: The virtual key code.
        ///   - characters: The characters the key produces.
        ///   - window: The window that receives the events.
        ///   - deliver: Delivers each event.
        func press(code: UInt16, characters: String, in window: PlatformWindow, deliver: (NSEvent) -> Void) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(
                    with: type,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: code
                ) else {
                    continue
                }
                recent.append(event)
                if recent.count > capacity {
                    recent.removeFirst(recent.count - capacity)
                }
                deliver(event)
            }
        }
    }
#endif
