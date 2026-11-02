import PlatformUI
import SwiftUI

#if os(macOS)
    /// The navigator of the platform the app is built for.
    public typealias PlatformMenuNavigator = AppKitMenuNavigator

    /// A control focus can be returned to: the focused `NSView`.
    public typealias FocusOrigin = NSView
#else
    /// The navigator of the platform the app is built for.
    public typealias PlatformMenuNavigator = TouchMenuNavigator

    /// A control focus can be returned to: a registered focus stop.
    public typealias FocusOrigin = MenuFocusStop
#endif

private struct MenuMoveKey: EnvironmentKey {
    static let defaultValue: (@MainActor (MenuMoveDirection) -> Void)? = nil
}

extension EnvironmentValues {
    /// The app's focus engine, published once at the root of every window.
    ///
    /// It is `nil` in a view tree the app did not set up, such as a preview; focus-aware views then keep
    /// working with the pointer and simply register no handlers.
    @Entry public var menuNavigator: PlatformMenuNavigator?

    /// Overrides where arrow presses on the shared focus controls move focus.
    ///
    /// When set, a ``FocusButton`` or ``FocusableSegments`` calls it with the direction instead of moving
    /// to the next control in the key view order.
    public var menuMove: (@MainActor (MenuMoveDirection) -> Void)? {
        get {
            self[MenuMoveKey.self]
        }
        set {
            self[MenuMoveKey.self] = newValue
        }
    }

    /// Whether focus controls track their own focus with a private focus state, as the Settings panel's
    /// rows do, so the highlight shows even without a bound focus value.
    @Entry public var settingsMenuFocus = false

    /// Whether the enclosing control has controller focus, which draws the focus highlight.
    @Entry public var menuItemFocused = false
}

extension View {
    /// Publishes the app's focus engine and input mode to the views below.
    ///
    /// - Parameter navigator: The navigator the composition root created.
    /// - Returns: The view with ``SwiftUICore/EnvironmentValues/menuNavigator`` and the input mode set.
    public func menuNavigator(_ navigator: PlatformMenuNavigator) -> some View {
        inputModeEnvironment()
            .environment(\.menuNavigator, navigator)
    }
}
