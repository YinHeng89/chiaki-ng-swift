import Foundation
import PlatformUI
import SwiftUI

/// Whether the window showing ambient motion can be seen and is the one the user is working in.
struct AmbientWindowState: Equatable {
    #if os(macOS)
        /// The window notifications after which the state is read again.
        static let changes: [Notification.Name] = [
            PlatformWindow.didChangeOcclusionStateNotification,
            PlatformWindow.didBecomeMainNotification,
            PlatformWindow.didResignMainNotification,
            PlatformWindow.didMiniaturizeNotification,
            PlatformWindow.didDeminiaturizeNotification
        ]
    #else
        /// The scene notifications after which the state is read again.
        static let changes: [Notification.Name] = [
            UIScene.didActivateNotification,
            UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification,
            UIScene.willEnterForegroundNotification
        ]
    #endif

    /// Whether any part of the window is on screen.
    var visible = true

    /// Whether the window is the main window on macOS, or its scene is in the foreground and active on iOS.
    var main = true

    /// Creates a state from known values.
    ///
    /// - Parameters:
    ///   - visible: Whether any part of the window is on screen.
    ///   - main: Whether the window is the one the user is working in.
    init(visible: Bool = true, main: Bool = true) {
        self.visible = visible
        self.main = main
    }

    #if os(macOS)
        /// Reads the state of a window.
        ///
        /// - Parameter window: The window to read; it counts as visible only when shown, not
        ///   minimised and not fully covered.
        @MainActor
        init(window: PlatformWindow) {
            visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
            main = window.isMainWindow
        }

        /// Reads the state of a window after one of the ``changes`` notifications.
        ///
        /// - Parameters:
        ///   - window: The window to read.
        ///   - change: The notification that triggered the read; the window already reflects it on macOS.
        @MainActor
        init(window: PlatformWindow, after change: Notification.Name) {
            self.init(window: window)
        }

        /// The object whose notifications describe a window's state.
        ///
        /// - Parameter window: The observed window.
        /// - Returns: The window itself.
        @MainActor
        static func source(for window: PlatformWindow) -> AnyObject? {
            window
        }
    #else
        /// Reads the state of a window from its scene's activation state.
        ///
        /// - Parameter window: The window to read; it counts as visible unless hidden, in the
        ///   background or detached from its scene.
        @MainActor
        init(window: PlatformWindow) {
            let activation = window.windowScene?.activationState ?? .foregroundActive
            visible = !window.isHidden && activation != .background && activation != .unattached
            main = activation == .foregroundActive
        }

        /// Reads the state of a window after one of the ``changes`` notifications.
        ///
        /// - Parameters:
        ///   - window: The window to read.
        ///   - change: The notification that triggered the read; a pending deactivation is not yet
        ///     reflected in the scene, so it marks the window inactive directly.
        @MainActor
        init(window: PlatformWindow, after change: Notification.Name) {
            self.init(window: window)
            if change == UIScene.willDeactivateNotification {
                main = false
            }
        }

        /// The object whose notifications describe a window's state.
        ///
        /// - Parameter window: The observed window.
        /// - Returns: The window's scene.
        @MainActor
        static func source(for window: PlatformWindow) -> AnyObject? {
            window.windowScene
        }
    #endif
}
