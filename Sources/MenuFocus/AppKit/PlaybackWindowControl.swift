import PlatformUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Window and display queries and actions used by playback, hiding the AppKit and UIKit differences.
@MainActor public enum PlaybackWindowControl {
    /// The window that currently receives key input, if any.
    public static var keyWindow: PlatformWindow? {
        #if os(macOS)
            NSApp.keyWindow
        #else
            WindowFocus.keyWindow
        #endif
    }

    /// Whether the app is frontmost and active.
    public static var isApplicationActive: Bool {
        #if os(macOS)
            NSApp.isActive
        #else
            UIApplication.shared.applicationState == .active
        #endif
    }

    /// Returns whether a sheet is attached to the window, which is always false outside macOS.
    public static func hasAttachedSheet(_ window: PlatformWindow) -> Bool {
        #if os(macOS)
            window.attachedSheet != nil
        #else
            false
        #endif
    }

    /// The main display's highest refresh rate, or 60 when it is unknown.
    public static var displayMaximumFramesPerSecond: Int {
        #if os(macOS)
            NSScreen.main?.maximumFramesPerSecond ?? 60
        #else
            keyWindow?.screen.maximumFramesPerSecond ?? 60
        #endif
    }

    /// Takes the key window out of full screen when it is in full screen.
    /// - Returns: Whether a full-screen window was exited; always false outside macOS.
    public static func leaveFullScreen() -> Bool {
        #if os(macOS)
            guard let window = NSApp.keyWindow,
                  window.styleMask.contains(.fullScreen) else {
                return false
            }
            window.toggleFullScreen(nil)
            return true
        #else
            false
        #endif
    }
}
