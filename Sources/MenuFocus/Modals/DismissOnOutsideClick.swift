import PlatformUI
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Dismisses a panel or card when the user clicks or taps outside it, or when its window stops being key.
///
/// Place it in the background of the panel. Clicks in windows the panel's window owns, such as its sheets,
/// do not count as outside.
public struct DismissOnOutsideClick: PlatformViewRepresentable {
    /// The invisible view that watches clicks and touches.
    public typealias PlatformViewType = ObserverView

    private let active: Bool
    private let dismiss: @MainActor () -> Void

    /// Creates the watcher.
    ///
    /// - Parameters:
    ///   - active: Whether outside clicks dismiss now.
    ///   - dismiss: Runs for an outside click or touch.
    public init(active: Bool, dismiss: @escaping @MainActor () -> Void) {
        self.active = active
        self.dismiss = dismiss
    }

    /// Creates the observer view.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: A new observer.
    public func makePlatformView(context: Context) -> ObserverView {
        ObserverView()
    }

    /// Passes the current state to the observer and installs its monitors.
    ///
    /// - Parameters:
    ///   - view: The observer.
    ///   - context: The representable context.
    public func updatePlatformView(_ view: ObserverView, context: Context) {
        view.active = active
        view.dismiss = dismiss
        view.install()
    }

    /// Removes the observer's monitors.
    ///
    /// - Parameters:
    ///   - view: The observer.
    ///   - coordinator: The representable's coordinator.
    public static func dismantlePlatformView(_ view: ObserverView, coordinator: ()) {
        view.uninstall()
    }

    #if os(macOS)
        /// Watches mouse clicks in the app and the window's key state.
        public final class ObserverView: NSView {
            /// Whether outside clicks dismiss now.
            public var active = false

            /// Runs for an outside click.
            public var dismiss: @MainActor () -> Void = {
            }

            private var monitor: Any?
            private var observer: NSObjectProtocol?

            /// Lets every click pass through.
            ///
            /// - Parameter point: The point being tested.
            /// - Returns: Always `nil`.
            override public func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            /// Starts watching clicks and the window resigning key, once.
            public func install() {
                guard monitor == nil else {
                    return
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [
                    .leftMouseDown,
                    .rightMouseDown
                ]) { [weak self] event in
                    MainActor.assumeIsolated {
                        self?.outsideCandidate(event)
                    }
                    return event
                }
                observer = NotificationCenter.default.addObserver(
                    forName: PlatformWindow.didResignKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let window = notification.object as? PlatformWindow else {
                        return
                    }
                    MainActor.assumeIsolated {
                        self?.windowResignedKey(window)
                    }
                }
            }

            private func outsideCandidate(_ event: NSEvent) {
                guard active else {
                    return
                }
                if event.window === window {
                    if !bounds.contains(convert(event.locationInWindow, from: nil)) {
                        dismiss()
                    }
                } else if !ownsWindow(event.window) {
                    dismiss()
                }
            }

            private func windowResignedKey(_ resigned: PlatformWindow) {
                guard active, resigned === window, resigned.attachedSheet == nil else {
                    return
                }
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, self.active, self.observer != nil, let host = self.window,
                          host === resigned else {
                        return
                    }
                    guard !host.isKeyWindow, host.attachedSheet == nil,
                          !self.ownsWindow(NSApp.keyWindow) else {
                        return
                    }
                    self.dismiss()
                }
            }

            /// Whether a window is this view's window or one of its sheets or child windows.
            ///
            /// - Parameter candidate: The window a click happened in.
            /// - Returns: `true` when the click belongs to the panel's window.
            public func ownsWindow(_ candidate: PlatformWindow?) -> Bool {
                guard let host = window else {
                    return false
                }
                var current = candidate
                while let window = current {
                    if window === host {
                        return true
                    }
                    current = window.sheetParent ?? window.parent
                }
                return false
            }

            /// Stops watching clicks.
            public func uninstall() {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                monitor = nil
                observer = nil
            }
        }
    #else
        /// Watches touches in the view's window.
        public final class ObserverView: UIView {
            /// Whether outside touches dismiss now.
            public var active = false

            /// Runs for an outside touch.
            public var dismiss: @MainActor () -> Void = {
            }

            private var recognizer: OutsideTouchRecognizer?

            /// Lets every touch pass through.
            ///
            /// - Parameters:
            ///   - point: The point being tested.
            ///   - event: The touch event.
            /// - Returns: Always `nil`.
            override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                nil
            }

            /// Reinstalls the touch recognizer on the new window.
            override public func didMoveToWindow() {
                super.didMoveToWindow()
                uninstall()
                install()
            }

            /// Adds a touch recognizer to the window, once.
            public func install() {
                guard recognizer == nil, let window else {
                    return
                }
                let created = OutsideTouchRecognizer(target: nil, action: nil)
                created.cancelsTouchesInView = false
                created.delaysTouchesBegan = false
                created.delaysTouchesEnded = false
                created.began = { [weak self] touches in
                    self?.touchesBegan(touches)
                }
                window.addGestureRecognizer(created)
                recognizer = created
            }

            /// Removes the touch recognizer.
            public func uninstall() {
                if let recognizer {
                    recognizer.view?.removeGestureRecognizer(recognizer)
                }
                recognizer = nil
            }

            private func touchesBegan(_ touches: Set<UITouch>) {
                guard active, let window, !isCovered(in: window) else {
                    return
                }
                let outside = touches.contains { touch in
                    !bounds.contains(touch.location(in: self))
                }
                if outside {
                    dismiss()
                }
            }

            private func isCovered(in window: PlatformWindow) -> Bool {
                guard let top = WindowFocus(window).topPresentedController?.view else {
                    return false
                }
                return !isDescendant(of: top)
            }
        }
    #endif
}

#if os(iOS)
    /// Reports touches anywhere in a window without taking part in gesture recognition.
    final class OutsideTouchRecognizer: UIGestureRecognizer {
        /// Receives the touches that began.
        var began: (Set<UITouch>) -> Void = { _ in
        }

        /// Reports the touches and fails, so no other gesture is affected.
        ///
        /// - Parameters:
        ///   - touches: The touches that began.
        ///   - event: The touch event.
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            began(touches)
            state = .failed
        }
    }
#endif
