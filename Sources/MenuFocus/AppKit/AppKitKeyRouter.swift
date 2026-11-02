#if os(macOS)
    import AppKit
    import PlatformUI

    /// Decides what happens to each key event before the app sees it.
    ///
    /// Real keys switch the input mode and may only bring the focus back; keys in a presentation that owns
    /// input drive its text fields, activation and focus moves; keys bound to tab commands perform them; and
    /// the navigator's own synthesised keys are dropped when menus do not take input or the window changed.
    /// Repeated arrow keys are delivered as fresh presses so SwiftUI moves focus once per repeat.
    @MainActor
    final class AppKitKeyRouter {
        private unowned let navigator: AppKitMenuNavigator
        private let policy: MenuInputPolicy

        /// Creates the router of a navigator.
        ///
        /// - Parameters:
        ///   - navigator: The navigator whose handlers and commands keys reach.
        ///   - policy: The app's answers about streams, menu input and key bindings.
        init(navigator: AppKitMenuNavigator, policy: MenuInputPolicy) {
            self.navigator = navigator
            self.policy = policy
        }

        /// What happens to a key event.
        enum Decision: Sendable {
            /// The event is delivered as it is.
            case deliver
            /// The event is swallowed.
            case discard
            /// A fresh copy of the repeated arrow key is delivered instead.
            case renew
        }

        /// Decides what happens to a key event.
        ///
        /// - Parameter event: A key event.
        /// - Returns: Whether to deliver, swallow or renew it.
        func decide(_ event: NSEvent) -> Decision {
            if discards(event) {
                return .discard
            }
            return renewsArrowPress(event)
                ? .renew
                : .deliver
        }

        /// Whether a held arrow key's repeat should be delivered as a fresh press.
        ///
        /// - Parameter event: A key event.
        /// - Returns: `true` for a repeated arrow key outside text entry and outside a stream window.
        func renewsArrowPress(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown,
                  event.isARepeat,
                  MenuArrowKey.keyCodes.contains(event.keyCode),
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]),
                  let window = event.window,
                  !policy.hostsStream(window) else {
                return false
            }
            return !AppKitMenuNavigator.acceptsTextInput(window.firstResponder)
        }

        /// A copy of a repeated key event that is not marked as a repeat.
        ///
        /// - Parameter event: A repeated key event.
        /// - Returns: The same key press as a fresh event.
        nonisolated static func freshArrowPress(_ event: NSEvent) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: false,
                keyCode: event.keyCode
            ) ?? event
        }

        /// The tab command a real key press is bound to in menus.
        ///
        /// - Parameter event: A key event.
        /// - Returns: The bound command, or `nil` for synthesised events, modified keys and unbound keys.
        func keyboardTabShortcut(for event: NSEvent) -> MenuCommand? {
            guard !navigator.isControllerEvent(event),
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) else {
                return nil
            }
            return policy.tabCommand(forKeyCode: Int(event.keyCode))
        }

        private func discards(_ event: NSEvent) -> Bool {
            if let window = event.window, navigator.keyCaptureWindows.contains(ObjectIdentifier(window)),
               !navigator.isControllerEvent(event) {
                return false
            }
            if !navigator.isControllerEvent(event) {
                if navigator.keyboardEvent(event) {
                    return true
                }
                revealAfterNavigationKey(event)
            }
            if navigator.inputGate.isBlocking,
               let window = navigator.activeWindow,
               window.sheetParent == nil,
               event.windowNumber == window.windowNumber,
               handlePresentationKey(event, in: window) {
                return true
            }
            if let command = keyboardTabShortcut(for: event),
               navigator.activeWindow?.sheetParent == nil,
               !AppKitMenuNavigator.acceptsTextInput(navigator.activeWindow?.firstResponder) {
                if event.type == .keyDown, !event.isARepeat {
                    navigator.perform(command)
                }
                return true
            }
            guard navigator.isControllerEvent(event) else {
                return false
            }
            return !policy.acceptsMenuInput || navigator.activeWindow?.windowNumber != event.windowNumber
        }

        private func handlePresentationKey(_ event: NSEvent, in window: PlatformWindow) -> Bool {
            if navigator.handleTextFieldKey(event, in: window) {
                return true
            }
            let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift])
            let editing = navigator.isTrackingMenu || window.firstResponder is NSTextView
            if [36, 49, 76].contains(event.keyCode), !editing, plain, navigator.handlers.hasModalActivation {
                if event.type == .keyDown, !event.isARepeat {
                    _ = navigator.handlers.activateModal(in: window)
                }
                return true
            }
            guard event.type == .keyDown, !editing, plain,
                  let arrow = MenuArrowKey(keyCode: event.keyCode) else {
                return false
            }
            return navigator.performFocusMove(arrow.direction, in: window)
        }

        private func revealAfterNavigationKey(_ event: NSEvent) {
            guard event.type == .keyDown,
                  [48, 123, 124, 125, 126, 116, 121, 115, 119].contains(event.keyCode),
                  let window = navigator.activeWindow,
                  event.windowNumber == window.windowNumber else {
                return
            }
            navigator.scheduleFocusReveal(in: window)
        }
    }
#endif
