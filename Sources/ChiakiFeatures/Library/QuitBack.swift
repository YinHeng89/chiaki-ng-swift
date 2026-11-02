import MenuFocus
import PlatformUI

/// Decides whether Back on a root screen may offer to quit.
public enum QuitBack {
    /// Tells whether Back in a window may move to the rail or offer to quit.
    ///
    /// Back is left alone while the window is hidden, shows a sheet or an alert, is a sheet itself, or while a
    /// modal, a menu or text editing owns the input.
    ///
    /// - Parameters:
    ///   - window: The window Back was pressed in.
    ///   - navigator: The app's menu navigator.
    /// - Returns: `true` when the root screen may handle Back.
    @MainActor public static func available(in window: PlatformWindow,
                                            navigator: PlatformMenuNavigator?) -> Bool {
        WindowFocus(window).isOnScreen
            && !WindowFocus(window).hasAttachedSheet
            && !WindowFocus(window).isAttachedSheet
            && !WindowFocus(window).isAlertPanel
            && !(navigator?.inputGate.isBlocking ?? false)
            && !(navigator?.isTrackingMenu ?? false)
            && !(navigator?.isEditingText(in: window) ?? false)
    }
}
