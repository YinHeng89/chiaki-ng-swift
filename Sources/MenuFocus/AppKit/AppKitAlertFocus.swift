#if os(macOS)
    import AppKit
    import PlatformUI

    /// Drives the buttons of a system alert panel with the controller.
    ///
    /// System alerts are not part of the app's own menus, so their buttons are walked in reading order:
    /// directions move between them, confirm clicks the focused one, and the cancel button starts focused.
    @MainActor
    public enum AppKitAlertFocus {
        /// Whether a window is a system alert panel.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` for an `NSAlert` panel.
        public static func isAlert(_ window: PlatformWindow) -> Bool {
            NSStringFromClass(type(of: window)).contains("AlertPanel")
        }

        /// The enabled, visible buttons of an alert in reading order.
        ///
        /// - Parameter window: An alert panel.
        /// - Returns: The buttons, or an empty array when `window` is not an alert.
        public static func buttons(in window: PlatformWindow) -> [NSButton] {
            guard isAlert(window), let content = window.contentView else {
                return []
            }
            return buttons(inside: content)
                .filter { button in
                    !button.isHiddenOrHasHiddenAncestor && button.isEnabled
                }
                .sorted { first, second in
                    FocusGeometry.appKit.precedes(
                        first.convert(first.bounds, to: nil),
                        second.convert(second.bounds, to: nil)
                    )
                }
        }

        /// Focuses the alert's cancel button, else its default button, else its first button.
        ///
        /// - Parameter window: An alert panel.
        public static func focusPreferredButton(in window: PlatformWindow) {
            let buttons = buttons(in: window)
            let preferred = buttons.first { button in
                button.keyEquivalent == "\u{1b}"
            } ?? buttons.first { button in
                button.keyEquivalent == "\r"
            } ?? buttons.first
            if let preferred {
                window.makeFirstResponder(preferred)
            }
        }

        /// Performs a command on an alert's buttons.
        ///
        /// - Parameters:
        ///   - command: The controller command.
        ///   - window: The window it was performed in.
        /// - Returns: Whether the window is an alert and the command was used.
        public static func handle(_ command: MenuCommand, in window: PlatformWindow) -> Bool {
            let buttons = buttons(in: window)
            guard !buttons.isEmpty else {
                return false
            }
            let index = (window.firstResponder as? NSButton).flatMap { button in
                buttons.firstIndex(of: button)
            }
            switch command {
            case .confirm, .up, .down, .left, .right:
                guard let index else {
                    focusPreferredButton(in: window)
                    return true
                }
                move(command, from: index, buttons: buttons, in: window)
                return true
            case .back, .alternate, .previous, .next, .streamMenu, .focusToolbar, .settings, .commit, .shift:
                return false
            }
        }

        private static func move(
            _ command: MenuCommand,
            from index: Int,
            buttons: [NSButton],
            in window: PlatformWindow
        ) {
            guard command != .confirm else {
                buttons[index].performClick(nil)
                return
            }
            let next = command == .up || command == .left
                ? index - 1
                : index + 1
            if buttons.indices.contains(next) {
                window.makeFirstResponder(buttons[next])
            }
        }

        private static func buttons(inside view: NSView) -> [NSButton] {
            if let button = view as? NSButton {
                return [button]
            }
            return view.subviews.flatMap(buttons(inside:))
        }
    }
#endif
