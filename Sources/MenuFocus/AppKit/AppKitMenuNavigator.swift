#if os(macOS)
    import AppKit
    import PlatformUI
    import SwiftUI

    /// The macOS focus engine, built on AppKit's first responder and key view loop.
    ///
    /// Directions that no handler takes become synthesised arrow keys or geometric moves between the
    /// window's key views; confirm and back become Space, Return or Escape for the focused control. Events
    /// the navigator synthesises are remembered so keyboard customisation can tell them apart from real key
    /// presses (``isControllerEvent(_:)``). Once started it also watches the hardware keyboard and pointer to
    /// switch ``inputMode``, returns focus after native menus close, and keeps the focused control scrolled
    /// into view.
    @MainActor
    public final class AppKitMenuNavigator: MenuNavigator {
        /// The handlers views register to take part in navigation.
        public let handlers = MenuHandlerStack()

        /// The router that delivers non-navigation commands to views.
        public let commands = MenuCommandRouter()

        /// The router that reports every command performed, navigation included, to views that only watch input.
        public let performed = MenuCommandRouter()

        /// The record of presentations that own input.
        public let inputGate = MenuInputGate()

        /// Whether the user is driving the app with a controller or a pointer.
        public let inputMode: InputModeCenter

        /// The windows whose own views capture the keyboard, such as a key binding recorder; real key events
        /// in them bypass navigation.
        public var keyCaptureWindows = Set<ObjectIdentifier>()

        /// Called when focus must be restored in a window and no remembered control is left, so the app can
        /// move focus to its main content.
        public var focusFallback: (PlatformWindow) -> Void {
            get {
                visibility.focusFallback
            }
            set {
                visibility.focusFallback = newValue
            }
        }

        private let policy: MenuInputPolicy
        private let mover = AppKitFocusMover()
        private let keys = AppKitKeySynthesizer()
        private let textEditing = AppKitTextEditing()
        private let monitors = AppKitInputMonitors()
        private let visibility: AppKitFocusVisibility
        private var menus: AppKitMenuTracking?
        private lazy var router = AppKitKeyRouter(navigator: self, policy: policy)

        /// Creates a navigator.
        ///
        /// - Parameters:
        ///   - policy: The app's answers about streams and key bindings.
        ///   - inputMode: The input mode to start in.
        ///   - diagnostics: Where to report focus decisions.
        public init(
            policy: MenuInputPolicy,
            inputMode: InputModeCenter = InputModeCenter(),
            diagnostics: MenuFocusDiagnostics = .silent
        ) {
            self.policy = policy
            self.inputMode = inputMode
            visibility = AppKitFocusVisibility(inputMode: inputMode, policy: policy, diagnostics: diagnostics)
        }

        /// Whether a native menu is open and tracking input.
        public var isTrackingMenu: Bool {
            menus?.isTracking == true
        }

        /// The key or main window, or the sheet attached to it.
        public var activeWindow: PlatformWindow? {
            WindowFocus.activeWindow
        }

        /// Starts watching the keyboard, the pointer, text editing, native menus and alerts.
        public func start() {
            guard !monitors.isRunning else {
                return
            }
            monitors.start(
                keys: { [weak self] event in
                    self?.router.decide(event) ?? .deliver
                },
                pointer: { [weak self] event in
                    self?.pointerEvent(event)
                }
            )
            textEditing.start()
            let menus = AppKitMenuTracking(
                activeWindow: { [weak self] in
                    self?.activeWindow
                },
                returnFocus: { [weak self] view, window, advance in
                    Task {
                        await self?.returnFocus(to: view, in: window, advance: advance)
                    }
                }
            )
            menus.start()
            self.menus = menus
        }

        /// Stops watching events and drops every handler and remembered state.
        public func stop() {
            monitors.stop()
            menus?.stop()
            menus = nil
            textEditing.stop()
            keys.reset()
            visibility.forget()
            handlers.removeAll()
            keyCaptureWindows.removeAll()
        }

        /// Whether a key event was synthesised by this navigator rather than typed.
        ///
        /// - Parameter event: A key event.
        /// - Returns: `true` for an event the navigator posted.
        public func isControllerEvent(_ event: NSEvent) -> Bool {
            keys.synthesised(event)
        }

        /// Performs a command in the active window, while the app is active.
        ///
        /// - Parameter command: The controller command.
        public func perform(_ command: MenuCommand) {
            guard NSApp.isActive, let window = activeWindow else {
                return
            }
            guard window.isKeyWindow else {
                perform(command, in: window) { event in
                    window.sendEvent(event)
                }
                return
            }
            perform(command, in: window)
        }

        /// Performs a command in a window.
        ///
        /// - Parameters:
        ///   - command: The controller command.
        ///   - window: The window to perform it in.
        ///   - deliver: Delivers each synthesised key event; tests pass the window's `sendEvent`.
        public func perform(
            _ command: MenuCommand,
            in window: PlatformWindow,
            deliver: (NSEvent) -> Void = { NSApp.postEvent($0, atStart: false) }
        ) {
            performed.send(command, to: window)
            if AppKitAlertFocus.handle(command, in: window) {
                return
            }
            if command.isNavigation {
                scheduleFocusReveal(in: window)
            }
            if !command.isNavigation {
                commands.send(command, to: window)
            } else if let arrow = MenuArrowKey(command: command) {
                if !performFocusMove(arrow.direction, in: window) {
                    keys.press(arrow, in: window, deliver: deliver)
                }
            } else if command == .confirm {
                confirm(in: window, deliver: deliver)
            } else if isTrackingMenu || !handlers.back(in: window) {
                keys.pressEscape(in: window, deliver: deliver)
            }
        }

        /// Asks the registered focus move handlers about a direction.
        ///
        /// - Parameters:
        ///   - direction: The direction pressed.
        ///   - window: The window it belongs to.
        /// - Returns: Whether a handler moved focus.
        public func performFocusMove(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
            handlers.performFocusMove(direction, in: window)
        }

        private func confirm(in window: PlatformWindow, deliver: (NSEvent) -> Void) {
            if handlers.activateModal(in: window) || handlers.activate(in: window) {
                return
            }
            if !isTrackingMenu, window.firstResponder is NSTextView, handlers.activateText(in: window) {
                return
            }
            keys.pressConfirm(
                returnKey: isTrackingMenu || window.firstResponder is NSTextView,
                in: window,
                deliver: deliver
            )
        }

        /// Whether a held arrow key's repeat should be delivered as a fresh press, so SwiftUI moves focus
        /// once per repeat instead of ignoring repeats.
        ///
        /// - Parameter event: A key event.
        /// - Returns: `true` for a repeated arrow key outside text entry and outside a stream window.
        public func renewsArrowPress(_ event: NSEvent) -> Bool {
            router.renewsArrowPress(event)
        }

        /// A copy of a repeated key event that is not marked as a repeat.
        ///
        /// - Parameter event: A repeated key event.
        /// - Returns: The same key press as a fresh event.
        public nonisolated static func freshArrowPress(_ event: NSEvent) -> NSEvent {
            AppKitKeyRouter.freshArrowPress(event)
        }

        /// The tab command a real key press is bound to in menus.
        ///
        /// - Parameter event: A key event.
        /// - Returns: The bound command, or `nil` for synthesised events, modified keys and unbound keys.
        public func keyboardTabShortcut(for event: NSEvent) -> MenuCommand? {
            router.keyboardTabShortcut(for: event)
        }

        /// Makes a view first responder again, optionally moving one step on after a short pause.
        ///
        /// - Parameters:
        ///   - view: The view to focus.
        ///   - window: The window it must still be in.
        ///   - advance: Whether to move to the next control afterwards.
        public func returnFocus(to view: NSView, in window: PlatformWindow, advance: Bool) async {
            guard window.isVisible, view.window === window else {
                return
            }
            if window.firstResponder !== view {
                window.makeFirstResponder(view)
            }
            if advance {
                try? await Task.sleep(for: .milliseconds(60))
                move(backward: false, in: window)
            }
        }

        /// Whether a responder accepts typed text: a text view or anything inside a web view.
        ///
        /// - Parameter responder: A first responder.
        /// - Returns: `true` when typing goes to `responder`.
        public static func acceptsTextInput(_ responder: NSResponder?) -> Bool {
            AppKitKeyViews.acceptsTextInput(responder)
        }

        /// Whether the focused view in a window accepts typed text.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` for a text view or web view.
        public func acceptsTextInput(in window: PlatformWindow) -> Bool {
            Self.acceptsTextInput(window.firstResponder)
        }

        /// Whether the focused view in a window can open the on-screen keyboard.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` when a text field's editor has focus.
        public func focusAcceptsControllerKeyboard(in window: PlatformWindow) -> Bool {
            window.firstResponder is NSTextView
        }

        /// The focused view in a window.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: The first responder, if it is a view.
        public func focusOrigin(in window: PlatformWindow) -> FocusOrigin? {
            window.firstResponder as? NSView
        }

        /// The focused view in a window, resolving a field editor to the text field that owns it.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: The text field or other focused view.
        public func editingFocusOrigin(in window: PlatformWindow) -> FocusOrigin? {
            (window.firstResponder as? NSTextView)?.delegate as? NSView ?? window.firstResponder as? NSView
        }

        /// Returns focus to a remembered view.
        ///
        /// - Parameters:
        ///   - origin: The view to focus.
        ///   - window: The window it is in.
        ///   - advance: Whether to move to the next control afterwards.
        public func restoreFocus(to origin: FocusOrigin, in window: PlatformWindow, advance: Bool) async {
            await returnFocus(to: origin, in: window, advance: advance)
        }

        /// Removes focus from every control in a window.
        ///
        /// - Parameter window: The window to clear.
        public func resignFocus(in window: PlatformWindow) {
            window.makeFirstResponder(nil)
        }

        /// Removes focus from every control in the key window without animating, ending text entry.
        public func endEditing() {
            AppKitTextEditing.clearKeyWindowFocus()
        }

        /// Moves focus to the next or previous navigation stop in reading order, wrapping at the ends.
        ///
        /// - Parameters:
        ///   - backward: Whether to move to the previous stop.
        ///   - window: The window to move focus in.
        public func move(backward: Bool, in window: PlatformWindow) {
            textEditing.end()
            mover.move(backward: backward, in: window)
        }

        /// Moves focus to the nearest navigation stop in a direction.
        ///
        /// - Parameters:
        ///   - direction: The direction pressed.
        ///   - window: The window to move focus in.
        ///   - belowGlobalY: Only stops below this SwiftUI global y position count, when given.
        ///   - allowUnaligned: Whether a vertical move may reach stops out of line with the focused one.
        ///   - horizontalWeight: How much sideways distance counts against a vertical move.
        /// - Returns: Whether focus moved.
        @discardableResult
        public func moveGeometric(
            _ direction: MenuMoveDirection,
            in window: PlatformWindow,
            belowGlobalY: CGFloat? = nil,
            allowUnaligned: Bool = false,
            horizontalWeight: CGFloat = 0.1
        ) -> Bool {
            let moved = mover.moveGeometric(
                direction,
                in: window,
                belowGlobalY: belowGlobalY,
                allowUnaligned: allowUnaligned,
                horizontalWeight: horizontalWeight
            )
            if moved {
                textEditing.end()
            }
            return moved
        }

        /// Focuses the navigation stop nearest to a rectangle.
        ///
        /// - Parameters:
        ///   - target: The window-space rectangle focus should land near.
        ///   - window: The window to move focus in.
        /// - Returns: Whether a stop took focus.
        @discardableResult
        public func focusNearest(to target: CGRect, in window: PlatformWindow) -> Bool {
            let moved = mover.focusNearest(to: target, in: window)
            if moved {
                textEditing.end()
            }
            return moved
        }

        /// Whether a control-sized view in the window has focus.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` when the focused view is not the content view and is smaller than a container.
        public func hasControlFocus(in window: PlatformWindow) -> Bool {
            AppKitFocusVisibility.hasControlFocus(in: window)
        }

        /// Moves focus to the first stop unless a control already has it.
        ///
        /// - Parameter window: The window to check.
        public func ensureControlFocused(in window: PlatformWindow) {
            if let frame = AppKitKeyViews.focusFrame(window.firstResponder), frame.height < 120 {
                return
            }
            move(backward: false, in: window)
        }

        /// Steps focus forward until it lands on a control below a SwiftUI global y position.
        ///
        /// - Parameters:
        ///   - globalY: The y position in SwiftUI global coordinates.
        ///   - window: The window to move focus in.
        public func focusEntry(belowGlobalY globalY: CGFloat, in window: PlatformWindow) {
            guard let limit = AppKitKeyViews.windowY(fromGlobalY: globalY, in: window) else {
                return
            }
            textEditing.end()
            mover.focusEntry(below: limit, in: window)
        }

        /// Whether the focused text field is being edited, which starts with Return and ends with Return or
        /// Escape.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: `true` while the focused field is in editing mode.
        public func isEditingText(in window: PlatformWindow) -> Bool {
            textEditing.isEditing(in: window)
        }

        /// Handles a key on a focused text field: Return starts or ends editing, Escape ends it, and arrows
        /// move focus while the field is not being edited.
        ///
        /// - Parameters:
        ///   - event: A key event.
        ///   - window: The window it belongs to.
        /// - Returns: Whether the key was consumed.
        public func handleTextFieldKey(_ event: NSEvent, in window: PlatformWindow) -> Bool {
            textEditing.handleKey(event, in: window) { direction in
                if !performFocusMove(direction, in: window) {
                    move(backward: direction.isBackward, in: window)
                }
            }
        }

        /// Scrolls the focused control into view now and again after the focus change settles.
        ///
        /// - Parameter window: The window whose focus to reveal.
        public func scheduleFocusReveal(in window: PlatformWindow) {
            AppKitScrollReveal.scheduleReveal(in: window)
        }

        /// Switches the input mode for a pointer event and hides the controller focus when it does.
        ///
        /// - Parameters:
        ///   - event: A mouse, drag or scroll event.
        ///   - windows: The windows whose focus to release; defaults to every app window.
        public func pointerEvent(_ event: NSEvent, windows: [PlatformWindow]? = nil) {
            visibility.pointerEvent(event, windows: windows)
        }

        /// Removes focus from the focused control of each visible window, remembering it for
        /// ``restoreFocus(in:)``.
        ///
        /// - Parameter windows: The windows to release.
        public func releaseFocus(in windows: [PlatformWindow]) {
            visibility.releaseFocus(in: windows)
        }

        /// Switches the input mode for a real key press and restores the controller focus when it does.
        ///
        /// - Parameter event: A key event typed by the user.
        /// - Returns: Whether the key should be swallowed because it only brought the focus back.
        public func keyboardEvent(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown,
                  let window = activeWindow,
                  event.windowNumber == window.windowNumber else {
                return false
            }
            return visibility.keyPressed(event, in: window)
        }

        /// Shows the controller focus again in a window.
        ///
        /// The released control gets focus back if it is still there; otherwise ``focusFallback`` runs and
        /// the first control is focused when nothing took focus.
        ///
        /// - Parameter window: The window to restore focus in.
        /// - Returns: `false` when the window hosts a stream and focus stays with the game.
        @discardableResult
        public func restoreFocus(in window: PlatformWindow) -> Bool {
            visibility.restoreFocus(in: window)
        }
    }
#endif
