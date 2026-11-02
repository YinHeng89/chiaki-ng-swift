#if os(macOS)
    import AppKit
    import PlatformUI
    import SwiftUI

    /// Tracks whether the focused text field is being edited, so arrows move focus until Return starts
    /// editing and Return or Escape ends it.
    @MainActor
    final class AppKitTextEditing {
        private var owner: ObjectIdentifier?
        private var observer: NSObjectProtocol?

        /// Starts ending the editing session whenever AppKit ends text editing.
        func start() {
            guard observer == nil else {
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSControl.textDidEndEditingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.end()
                }
            }
        }

        /// Stops observing and forgets the editing session.
        func stop() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            owner = nil
        }

        /// Removes focus from every control in the key window without animating, ending text entry.
        static func clearKeyWindowFocus() {
            guard let window = NSApp.keyWindow else {
                return
            }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    window.makeFirstResponder(nil)
                }
            }
        }

        /// Forgets the editing session, as when focus moves elsewhere.
        func end() {
            owner = nil
        }

        /// Whether the focused text field in a window is being edited.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` while the focused field is in editing mode.
        func isEditing(in window: PlatformWindow) -> Bool {
            guard let textView = window.firstResponder as? NSTextView else {
                return false
            }
            return owner == Self.owner(of: textView)
        }

        /// Handles a key on a focused text field.
        ///
        /// - Parameters:
        ///   - event: A key event.
        ///   - window: The window it belongs to.
        ///   - moveFocus: Moves focus in a direction while the field is not being edited.
        /// - Returns: Whether the key was consumed.
        func handleKey(
            _ event: NSEvent,
            in window: PlatformWindow,
            moveFocus: (MenuMoveDirection) -> Void
        ) -> Bool {
            guard event.type == .keyDown,
                  let textView = window.firstResponder as? NSTextView,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) else {
                return false
            }
            let fieldOwner = Self.owner(of: textView)
            let editing = owner == fieldOwner
            switch event.keyCode {
            case 36, 76:
                return handleReturn(in: textView, owner: fieldOwner, editing: editing)
            case 53:
                guard editing else {
                    return false
                }
                owner = nil
                return true
            default:
                guard !editing, let arrow = MenuArrowKey(keyCode: event.keyCode) else {
                    return false
                }
                owner = nil
                moveFocus(arrow.direction)
                return true
            }
        }

        private func handleReturn(in textView: NSTextView, owner fieldOwner: ObjectIdentifier,
                                  editing: Bool) -> Bool {
            guard editing else {
                owner = fieldOwner
                return true
            }
            if textView.isFieldEditor {
                owner = nil
            }
            return false
        }

        private static func owner(of textView: NSTextView) -> ObjectIdentifier {
            ObjectIdentifier((textView.delegate as AnyObject?) ?? textView)
        }
    }
#endif
