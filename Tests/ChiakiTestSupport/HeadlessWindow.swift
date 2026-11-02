#if os(macOS)
    import AppKit
    import PlatformUI

    /// A test window that lives far off every screen, so hosted-window tests never show anything or take
    /// focus from the person at the machine.
    ///
    /// The window ignores the frame constraints that would pull it back onto a display, reports that it can
    /// become key, and keeps the test process an accessory app without a Dock icon. Tests never activate
    /// the process; key and first-responder state stay inside the window.
    @MainActor
    public final class HeadlessWindow: PlatformWindow {
        private static let offscreenOrigin = CGPoint(x: -60000, y: -60000)

        /// Creates a window off screen.
        ///
        /// - Parameters:
        ///   - contentRect: The content size; its origin is replaced with an off-screen one.
        ///   - style: The window style.
        ///   - backingStoreType: The backing store.
        ///   - flag: Whether to defer creating the window device.
        override public init(
            contentRect: NSRect,
            styleMask style: NSWindow.StyleMask,
            backing backingStoreType: NSWindow.BackingStoreType,
            defer flag: Bool
        ) {
            NSApplication.shared.setActivationPolicy(.accessory)
            super.init(
                contentRect: NSRect(origin: Self.offscreenOrigin, size: contentRect.size),
                styleMask: style,
                backing: backingStoreType,
                defer: flag
            )
            isReleasedWhenClosed = false
            animationBehavior = .none
            super.setFrameOrigin(Self.offscreenOrigin)
        }

        /// Creates a small titled window off screen.
        public convenience init() {
            self.init(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
        }

        /// Whether the window can become key, which it always can.
        override public var canBecomeKey: Bool {
            true
        }

        /// Keeps a requested frame exactly where it is instead of moving it onto a display.
        ///
        /// - Parameters:
        ///   - frameRect: The requested frame.
        ///   - screen: The screen AppKit would constrain to.
        /// - Returns: The requested frame, unchanged.
        override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }

        /// Applies a frame's size while keeping the window at its off-screen origin.
        ///
        /// - Parameters:
        ///   - frameRect: The requested frame; only its size is used.
        ///   - flag: Whether to redisplay.
        override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
            super.setFrame(NSRect(origin: Self.offscreenOrigin, size: frameRect.size), display: flag)
        }

        /// Keeps the window at its off-screen origin whatever origin is asked for.
        ///
        /// - Parameter point: The requested origin, ignored.
        override public func setFrameOrigin(_ point: NSPoint) {
            super.setFrameOrigin(Self.offscreenOrigin)
        }

        /// Keeps the window at its off-screen origin when asked to centre it.
        override public func center() {
            super.setFrameOrigin(Self.offscreenOrigin)
        }

        /// Moves the window off screen, then orders it in relative to another window.
        ///
        /// - Parameters:
        ///   - place: Where to order the window.
        ///   - otherWin: The window to order relative to, or zero for all windows.
        override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
            super.setFrameOrigin(Self.offscreenOrigin)
            super.order(place, relativeTo: otherWin)
        }

        /// Moves the window off screen, then makes it key and orders it in.
        ///
        /// - Parameter sender: The sender.
        override public func makeKeyAndOrderFront(_ sender: Any?) {
            super.setFrameOrigin(Self.offscreenOrigin)
            super.makeKeyAndOrderFront(sender)
        }

        /// Moves the window off screen, then orders it in front.
        override public func orderFrontRegardless() {
            super.setFrameOrigin(Self.offscreenOrigin)
            super.orderFrontRegardless()
        }
    }
#endif
