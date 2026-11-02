#if os(macOS)
    import AppKit
    import PlatformUI

    /// Hides the controller focus when the pointer takes over and shows it again when a key is pressed.
    ///
    /// Hiding remembers the focused control so showing can return to it; when it is gone the app's fallback
    /// runs and the window's first control is focused if nothing took focus.
    @MainActor
    final class AppKitFocusVisibility {
        /// Called when focus must be restored in a window and no remembered control is left.
        var focusFallback: (PlatformWindow) -> Void = { _ in
        }

        private let inputMode: InputModeCenter
        private let policy: MenuInputPolicy
        private let diagnostics: MenuFocusDiagnostics
        private weak var releasedWindow: PlatformWindow?
        private weak var releasedView: NSView?

        /// Creates the visibility of the controller focus.
        ///
        /// - Parameters:
        ///   - inputMode: The input mode that pointer and key events switch.
        ///   - policy: The app's answers about streams.
        ///   - diagnostics: Where to report focus decisions.
        init(inputMode: InputModeCenter, policy: MenuInputPolicy, diagnostics: MenuFocusDiagnostics) {
            self.inputMode = inputMode
            self.policy = policy
            self.diagnostics = diagnostics
        }

        /// Whether a control-sized view in the window has focus.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` when the focused view is not the content view and is smaller than a container.
        static func hasControlFocus(in window: PlatformWindow) -> Bool {
            guard let view = AppKitKeyViews.focusView(in: window),
                  view !== window.contentView,
                  view.window === window,
                  let frame = AppKitKeyViews.focusFrame(view) else {
                return false
            }
            return frame.height < FocusGeometry.maximumStopHeight
        }

        /// Forgets the remembered control.
        func forget() {
            releasedWindow = nil
            releasedView = nil
        }

        /// Switches the input mode for a pointer event and hides the controller focus when it does.
        ///
        /// - Parameters:
        ///   - event: A mouse, drag or scroll event.
        ///   - windows: The windows whose focus to release; every app window when `nil`.
        func pointerEvent(_ event: NSEvent, windows: [PlatformWindow]?) {
            let entered: Bool
            switch event.type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                entered = inputMode.pointerMoved(dx: event.deltaX, dy: event.deltaY, at: event.timestamp)
            case .scrollWheel:
                guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else {
                    return
                }
                entered = inputMode.pointerAction()
            default:
                entered = inputMode.pointerAction()
            }
            if entered {
                let movement = event.type == .scrollWheel
                    ? ""
                    : ", moved \(Int(event.deltaX)), \(Int(event.deltaY))"
                diagnostics
                    .log(
                        "Pointer input (event type \(event.type.rawValue)\(movement)) hides the controller focus"
                    )
                releaseFocus(in: windows ?? NSApp.windows)
            }
        }

        /// Removes focus from the focused control of each visible window, remembering it.
        ///
        /// - Parameter windows: The windows to release.
        func releaseFocus(in windows: [PlatformWindow]) {
            for window in windows where window.isVisible {
                guard Self.hasControlFocus(in: window),
                      !AppKitMenuNavigator.acceptsTextInput(window.firstResponder),
                      let view = AppKitKeyViews.focusView(in: window) else {
                    continue
                }
                releasedWindow = window
                releasedView = view
                window.makeFirstResponder(nil)
            }
        }

        /// Switches the input mode for a real key press in a window and shows the controller focus when it
        /// does.
        ///
        /// - Parameters:
        ///   - event: A key down typed by the user.
        ///   - window: The active window the key belongs to.
        /// - Returns: Whether the key should be swallowed because it only brought the focus back.
        func keyPressed(_ event: NSEvent, in window: PlatformWindow) -> Bool {
            let editing = AppKitMenuNavigator.acceptsTextInput(window.firstResponder)
            guard inputMode.keyPressed(event.keyCode, modifiers: event.modifierFlags, editingText: editing)
            else {
                return false
            }
            let restored = restoreFocus(in: window)
            return restored && InputModeCenter.focusMoveKeyCodes.contains(event.keyCode)
        }

        /// Shows the controller focus again in a window.
        ///
        /// - Parameter window: The window to restore focus in.
        /// - Returns: `false` when the window hosts a stream and focus stays with the game.
        func restoreFocus(in window: PlatformWindow) -> Bool {
            guard !Self.hasControlFocus(in: window) else {
                AppKitScrollReveal.scheduleReveal(in: window)
                return true
            }
            if releasedWindow === window, let view = releasedView, view.window === window,
               !view.isHiddenOrHasHiddenAncestor, window.makeFirstResponder(view),
               Self.hasControlFocus(in: window) {
                AppKitScrollReveal.scheduleReveal(in: window)
                return true
            }
            if policy.hostsStream(window) {
                return false
            }
            focusFallback(window)
            Task { @MainActor in
                await Task.yield()
                if !Self.hasControlFocus(in: window) {
                    window.recalculateKeyViewLoop()
                    window.selectNextKeyView(nil)
                }
                AppKitScrollReveal.scheduleReveal(in: window)
            }
            return true
        }
    }
#endif
