import Foundation
import CoreGraphics
import PlatformUI

/// The focus engine of one platform: it performs controller commands and moves focus between controls.
///
/// ``AppKitMenuNavigator`` drives AppKit's key view loop and first responder on macOS;
/// `TouchMenuNavigator` drives the registered focus stops on iOS. Both choose targets with the same
/// ``FocusGeometry``. The app creates one navigator at its composition root, gives it the app's
/// ``MenuInputPolicy``, and publishes it to views through ``SwiftUICore/EnvironmentValues/menuNavigator``.
///
/// A command is performed in the active window: directions go to the registered focus move handlers and
/// otherwise to geometry or a synthesised arrow key; confirm goes to modal activation handlers, then
/// activation handlers, then the focused control; back goes to back handlers and otherwise to Escape;
/// every other command is routed to views through ``commands``.
@MainActor
public protocol MenuNavigator: AnyObject {
    /// The handlers views register to take part in navigation.
    var handlers: MenuHandlerStack { get }

    /// The router that delivers non-navigation commands to views.
    var commands: MenuCommandRouter { get }

    /// The router that reports every command the navigator performs, navigation included, to views that only
    /// watch input, such as a secret code; subscribe with ``SwiftUICore/View/onPerformedMenuCommand(_:perform:)``.
    var performed: MenuCommandRouter { get }

    /// The record of presentations that own input.
    var inputGate: MenuInputGate { get }

    /// Whether the user is driving the app with a controller or a pointer.
    var inputMode: InputModeCenter { get }

    /// The window controller commands apply to now.
    var activeWindow: PlatformWindow? { get }

    /// Whether a native menu is open and tracking input.
    var isTrackingMenu: Bool { get }

    /// Starts observing keyboard, pointer and window events.
    func start()

    /// Stops observing events and drops every handler.
    func stop()

    /// Performs a command in the active window.
    ///
    /// - Parameter command: The controller command.
    func perform(_ command: MenuCommand)

    /// Moves focus to the next or previous control in reading order, wrapping at the ends.
    ///
    /// - Parameters:
    ///   - backward: Whether to move to the previous control.
    ///   - window: The window to move focus in.
    func move(backward: Bool, in window: PlatformWindow)

    /// Moves focus to the nearest control in a direction.
    ///
    /// - Parameters:
    ///   - direction: The direction pressed.
    ///   - window: The window to move focus in.
    ///   - belowGlobalY: Only controls below this SwiftUI global y position count, when given.
    ///   - allowUnaligned: Whether a vertical move may reach controls out of line with the focused one.
    ///   - horizontalWeight: How much sideways distance counts against a vertical move.
    /// - Returns: Whether focus moved.
    @discardableResult
    func moveGeometric(
        _ direction: MenuMoveDirection,
        in window: PlatformWindow,
        belowGlobalY: CGFloat?,
        allowUnaligned: Bool,
        horizontalWeight: CGFloat
    ) -> Bool

    /// Focuses the control nearest to a rectangle, used after a view is rebuilt.
    ///
    /// - Parameters:
    ///   - target: The window-space rectangle focus should land near.
    ///   - window: The window to move focus in.
    /// - Returns: Whether a control took focus.
    @discardableResult
    func focusNearest(to target: CGRect, in window: PlatformWindow) -> Bool

    /// Whether a control, rather than a container or nothing, has focus in a window.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: `true` when a control-sized view holds focus.
    func hasControlFocus(in window: PlatformWindow) -> Bool

    /// Moves focus to the first control when no control has focus.
    ///
    /// - Parameter window: The window to check.
    func ensureControlFocused(in window: PlatformWindow)

    /// Focuses the first control below a SwiftUI global y position.
    ///
    /// - Parameters:
    ///   - globalY: The y position in SwiftUI global coordinates.
    ///   - window: The window to move focus in.
    func focusEntry(belowGlobalY globalY: CGFloat, in window: PlatformWindow)

    /// Whether the focused text field is being edited rather than merely focused.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: `true` while the user is typing into the focused field.
    func isEditingText(in window: PlatformWindow) -> Bool

    /// Scrolls the focused control into view now and again after a short delay.
    ///
    /// - Parameter window: The window whose focus to reveal.
    func scheduleFocusReveal(in window: PlatformWindow)

    /// Asks the registered focus move handlers about a direction.
    ///
    /// - Parameters:
    ///   - direction: The direction pressed.
    ///   - window: The window it belongs to.
    /// - Returns: Whether a handler moved focus.
    func performFocusMove(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool

    /// Hides the controller focus because the pointer took over, remembering what had focus.
    ///
    /// - Parameter windows: The windows whose focus to release.
    func releaseFocus(in windows: [PlatformWindow])

    /// Shows the controller focus again: the remembered control, or the first sensible one.
    ///
    /// - Parameter window: The window to restore focus in.
    /// - Returns: `false` when the window hosts a stream and focus stays with the game.
    @discardableResult
    func restoreFocus(in window: PlatformWindow) -> Bool

    /// Whether the focused view in a window accepts typed text.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: `true` for a text field, text view or web view.
    func acceptsTextInput(in window: PlatformWindow) -> Bool

    /// Whether the focused view in a window can open the on-screen keyboard.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: `true` when a text field has focus.
    func focusAcceptsControllerKeyboard(in window: PlatformWindow) -> Bool

    /// The focused control in a window, kept to return focus to it later.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: The focused control, if any.
    func focusOrigin(in window: PlatformWindow) -> FocusOrigin?

    /// The focused control in a window, resolving a field editor to the text field that owns it.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: The focused control, if any.
    func editingFocusOrigin(in window: PlatformWindow) -> FocusOrigin?

    /// Returns focus to a control remembered earlier, optionally moving one step on.
    ///
    /// - Parameters:
    ///   - origin: The control to focus.
    ///   - window: The window it is in.
    ///   - advance: Whether to move to the next control afterwards.
    func restoreFocus(to origin: FocusOrigin, in window: PlatformWindow, advance: Bool) async

    /// Removes focus from every control in a window.
    ///
    /// - Parameter window: The window to clear.
    func resignFocus(in window: PlatformWindow)

    /// Removes focus from every control in the key window without animating the change, ending text entry.
    func endEditing()
}

extension MenuNavigator {
    /// Moves focus to the next or previous control in the active window.
    ///
    /// - Parameter backward: Whether to move to the previous control.
    public func move(backward: Bool) {
        guard let window = activeWindow else {
            return
        }
        move(backward: backward, in: window)
    }
}

extension MenuNavigator {
    /// Checks twice after short delays and, if no control in the window has focus, runs `reset` and then
    /// `apply` to set focus again; when the window is still not key after that, it checks once more as the
    /// window next becomes key.
    ///
    /// SwiftUI can drop a focus request made while a view is appearing or another is fading out, and drops
    /// every request made while its window is not key, as when the app is inactive during a full-screen
    /// transition; this puts it back without overriding focus the user has already moved.
    ///
    /// - Parameters:
    ///   - window: The window whose focus is checked, or `nil` to do nothing.
    ///   - reset: Clears the focus value so the next assignment is seen as a change.
    ///   - apply: Sets the intended focus.
    public func ensureFocus(
        in window: PlatformWindow?,
        reset: @escaping @MainActor () -> Void,
        apply: @escaping @MainActor () -> Void
    ) {
        ensureFocus(
            in: { [weak window] in
                window
            },
            reset: reset,
            apply: apply
        )
    }

    /// Ensures focus as the overload taking a window does, reading the window at each check, for a view that
    /// sets its focus before its window is known.
    ///
    /// - Parameters:
    ///   - window: Reads the window whose focus is checked; a check that reads `nil` does nothing.
    ///   - reset: Clears the focus value so the next assignment is seen as a change.
    ///   - apply: Sets the intended focus.
    public func ensureFocus(
        in window: @escaping @MainActor () -> PlatformWindow?,
        reset: @escaping @MainActor () -> Void,
        apply: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor [weak self] in
            for delay in [80, 250] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, let window = window(), !hasControlFocus(in: window) else {
                    continue
                }
                reset()
                await Task.yield()
                apply()
            }
            guard window()?.isKeyWindow == false,
                  await Self.becomesKey(window, within: Self.keyWindowPatience) else {
                return
            }
            guard let self, let found = window(), !hasControlFocus(in: found) else {
                return
            }
            reset()
            await Task.yield()
            apply()
        }
    }

    /// How long focus is ensured for a window that is not key, waiting for it to become key.
    static var keyWindowPatience: Duration {
        .seconds(60)
    }

    /// How often a window that is not key is checked while focus waits for it to become key.
    static var keyWindowPoll: Duration {
        .milliseconds(250)
    }

    private static func becomesKey(
        _ window: @escaping @MainActor () -> PlatformWindow?,
        within patience: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: patience)
        while clock.now < deadline {
            do {
                try await Task.sleep(for: keyWindowPoll)
            } catch {
                return false
            }
            guard let current = window() else {
                return false
            }
            if current.isKeyWindow {
                return true
            }
        }
        return false
    }
}
