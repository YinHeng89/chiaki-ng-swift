import PlatformUI
import MenuFocus
import SwiftUI

#if os(macOS)
    /// An invisible view that, while a keyboard capture is listening, intercepts the next key press in its
    /// window and reports its key code and label; losing key window status cancels the capture.
    public struct KeyBindingCapture: NSViewRepresentable {
        /// The capture in progress; the key monitor is installed only while this is set.
        public let capture: ControlsCapture?
        /// Called with the capture ID, virtual key code and display label of the captured key.
        public let receive: (UUID, Int, String) -> Void
        /// Cancels the capture when the window stops being key.
        public let cancel: () -> Void
        @Environment(\.menuNavigator) private var navigator

        /// Creates a key binding capture.
        ///
        /// - Parameters:
        ///   - capture: The capture in progress; the key monitor is installed only while this is set.
        ///   - receive: Called with the capture ID, virtual key code and display label of the captured key.
        ///   - cancel: Cancels the capture when the window stops being key.
        public init(
            capture: ControlsCapture?,
            receive: @escaping (UUID, Int, String) -> Void,
            cancel: @escaping () -> Void
        ) {
            self.capture = capture
            self.receive = receive
            self.cancel = cancel
        }

        /// Creates the capture view.
        public func makeNSView(context: Context) -> CaptureView {
            CaptureView()
        }
        /// Hands the current capture, callbacks and navigator to the view and installs or removes its key
        /// monitor.
        public func updateNSView(_ view: CaptureView, context: Context) {
            view.capture = capture
            view.receive = receive
            view.cancel = cancel
            view.navigator = navigator
            view.updateMonitor()
        }

        /// Removes the key monitor when SwiftUI tears the view down.
        public static func dismantleNSView(_ view: CaptureView, coordinator: ()) {
            view.removeMonitor()
        }
        /// The AppKit view that owns the local key-down monitor and marks its window as capturing keys so the
        /// menu navigator leaves key presses alone.
        public final class CaptureView: NSView {
            /// The capture in progress, or `nil` when no key should be intercepted.
            public var capture: ControlsCapture?
            /// Called with the capture ID, virtual key code and label of a captured key.
            public var receive: ((UUID, Int, String) -> Void)?
            /// Called when the window loses key status during a capture.
            public var cancel: (() -> Void)?
            /// The navigator told which windows are capturing keys, and asked whether an event came from a
            /// controller.
            public weak var navigator: AppKitMenuNavigator?
            private var monitor: Any?
            private weak var registeredWindow: PlatformWindow?

            /// Returns `nil` so the view never intercepts mouse clicks.
            public override func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            /// Installs the key monitor when a capture is set and the view is in a window, and removes it
            /// otherwise.
            public func updateMonitor() {
                if capture != nil, window != nil {
                    installMonitor()
                } else {
                    removeMonitor()
                }
            }

            /// Removes the key monitor and unregisters the window from the navigator's key capture windows.
            public func removeMonitor() {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
                if let registeredWindow {
                    navigator?.keyCaptureWindows.remove(ObjectIdentifier(registeredWindow))
                }
                registeredWindow = nil
            }

            private func installMonitor() {
                guard monitor == nil else {
                    return
                }
                if let window {
                    registeredWindow = window
                    navigator?.keyCaptureWindows.insert(ObjectIdentifier(window))
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let consumed = MainActor.assumeIsolated {
                        self?.handle(event) == true
                    }
                    return consumed
                        ? nil
                        : event
                }
            }

            /// Refreshes the key monitor and observes the new window losing key status.
            public override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                updateMonitor()
                NotificationCenter.default.removeObserver(
                    self,
                    name: PlatformWindow.didResignKeyNotification,
                    object: nil
                )
                if let window {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowLostFocus),
                                                           name: PlatformWindow.didResignKeyNotification,
                                                           object: window)
                }
            }
            @objc private func windowLostFocus(_ notification: Notification) {
                if capture != nil {
                    cancel?()
                }
            }
            /// Captures a key press for the current capture.
            ///
            /// Repeats, Command shortcuts, controller-generated events, events for other windows and presses
            /// while a sheet is attached are ignored.
            ///
            /// - Parameter event: The key-down event.
            /// - Returns: `true` when the event was captured and should be swallowed.
            public func handle(_ event: NSEvent) -> Bool {
                guard let capture, let window, event.window === window, !event.isARepeat,
                      window.attachedSheet == nil,
                      navigator?.isControllerEvent(event) != true,
                      !event.modifierFlags.contains(.command) else {
                    return false
                }
                let label = KeyCodeLabels.label(
                    for: Int(event.keyCode),
                    characters: event.charactersIgnoringModifiers
                )
                receive?(capture.id, Int(event.keyCode), label)
                return true
            }
        }
    }
#else
    /// A placeholder that does nothing on platforms without a hardware keyboard capture.
    public struct KeyBindingCapture: View {
        /// The capture in progress, ignored on this platform.
        public let capture: ControlsCapture?
        /// Called with a captured key, never invoked on this platform.
        public let receive: (UUID, Int, String) -> Void
        /// Cancels the capture, never invoked on this platform.
        public let cancel: () -> Void

        /// Creates a key binding capture.
        ///
        /// - Parameters:
        ///   - capture: The capture in progress, ignored on this platform.
        ///   - receive: Called with a captured key, never invoked on this platform.
        ///   - cancel: Cancels the capture, never invoked on this platform.
        public init(
            capture: ControlsCapture?,
            receive: @escaping (UUID, Int, String) -> Void,
            cancel: @escaping () -> Void
        ) {
            self.capture = capture
            self.receive = receive
            self.cancel = cancel
        }

        public var body: some View {
            EmptyView()
        }
    }
#endif
