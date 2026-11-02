import PlatformUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Questions about a window's presentation state that focus handlers ask before acting.
///
/// Handlers must act only for their own window and step aside while a sheet or alert is in front of it.
@MainActor
public struct WindowFocus {
    /// The window being asked about.
    public let window: PlatformWindow

    /// Wraps a window.
    ///
    /// - Parameter window: The window to ask about.
    public init(_ window: PlatformWindow) {
        self.window = window
    }

    /// The window that receives keyboard input: the key window on macOS, the active scene's key window on
    /// iOS.
    public static var keyWindow: PlatformWindow? {
        #if os(macOS)
            return NSApp.keyWindow
        #else
            let scenes = UIApplication.shared.connectedScenes.compactMap { scene in
                scene as? UIWindowScene
            }
            let active = scenes.first { scene in
                scene.activationState == .foregroundActive
            } ?? scenes.first
            return active?.keyWindow ?? active?.windows.first
        #endif
    }

    #if os(macOS)
        /// The windows that claimed controller input while they show, newest last.
        private static let claimed = NSHashTable<NSWindow>.weakObjects()

        /// The window controller commands apply to: the newest visible window that claimed input, else the key or
        /// main window, or the sheet attached to it.
        public static var activeWindow: PlatformWindow? {
            if let window = claimed.allObjects.last(where: { $0.isVisible }) {
                return window
            }
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                return window.attachedSheet ?? window
            }
            return NSApp.windows.first { window in
                window.isVisible && window.attachedSheet != nil
            }?.attachedSheet
        }
    #endif

    /// Claims controller input for the window while it shows, as a popover does: commands go to it even when
    /// it is not key, which a popover opened with the pointer never becomes, and it is made key when it can be.
    /// Release the claim when the window's content goes away.
    public func claimInput() {
        #if os(macOS)
            Self.claimed.remove(window)
            Self.claimed.add(window)
            guard NSApp.isActive, window.canBecomeKey, !window.isKeyWindow else {
                return
            }
        #else
            guard !window.isKeyWindow else {
                return
            }
        #endif
        window.makeKey()
    }

    /// Gives up the window's claim on controller input, so commands go to the key window again.
    public func releaseInput() {
        #if os(macOS)
            Self.claimed.remove(window)
        #endif
    }

    /// Whether the window is on screen.
    public var isOnScreen: Bool {
        #if os(macOS)
            return window.isVisible
        #else
            return !window.isHidden && window.windowScene != nil
        #endif
    }

    /// Whether a sheet is attached to the window.
    public var hasAttachedSheet: Bool {
        #if os(macOS)
            return window.attachedSheet != nil
        #else
            return window.rootViewController?.presentedViewController != nil
        #endif
    }

    /// Whether the window is itself a sheet attached to another window.
    public var isAttachedSheet: Bool {
        #if os(macOS)
            return window.sheetParent != nil
        #else
            return false
        #endif
    }

    /// Whether the window is a system alert.
    public var isAlertPanel: Bool {
        #if os(macOS)
            return AppKitAlertFocus.isAlert(window)
        #else
            return topPresentedController is UIAlertController
        #endif
    }

    /// The bounds of the window's content.
    public var contentBounds: CGRect? {
        #if os(macOS)
            return window.contentView?.bounds
        #else
            return window.bounds
        #endif
    }

    /// Whether the window presents a sheet that a command in another window reached.
    ///
    /// - Parameter candidate: The window a command was performed in.
    /// - Returns: `true` when the window has a sheet and `candidate` is the window or its sheet.
    public func presentsSheet(reachedThrough candidate: PlatformWindow) -> Bool {
        guard hasAttachedSheet else {
            return false
        }
        #if os(macOS)
            return candidate === window || candidate === window.attachedSheet
        #else
            return candidate === window
        #endif
    }

    #if os(iOS)
        /// The topmost view controller presented in the window.
        public var topPresentedController: UIViewController? {
            var top = window.rootViewController
            while let presented = top?.presentedViewController {
                top = presented
            }
            return top
        }
    #endif
}
