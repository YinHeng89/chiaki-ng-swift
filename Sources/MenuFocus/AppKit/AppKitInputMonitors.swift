#if os(macOS)
    import AppKit
    import PlatformUI

    /// Watches the app's local key and pointer events and the windows that become key.
    ///
    /// Key events pass through a filter that may swallow or replace them; pointer events are only observed.
    /// An alert that becomes key has its preferred button focused.
    @MainActor
    final class AppKitInputMonitors {
        private var keyMonitor: Any?
        private var pointerMonitor: Any?
        private var alertObserver: NSObjectProtocol?

        /// Whether the monitors are installed.
        var isRunning: Bool {
            alertObserver != nil
        }

        /// Installs the monitors.
        ///
        /// - Parameters:
        ///   - keys: Decides whether each key event is delivered, swallowed or renewed.
        ///   - pointer: Observes each mouse, drag and scroll event.
        func start(
            keys: @escaping @MainActor (NSEvent) -> AppKitKeyRouter.Decision,
            pointer: @escaping @MainActor (NSEvent) -> Void
        ) {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                let decision = MainActor.assumeIsolated {
                    keys(event)
                }
                switch decision {
                case .deliver:
                    return event
                case .discard:
                    return nil
                case .renew:
                    return AppKitKeyRouter.freshArrowPress(event)
                }
            }
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
            ]) { event in
                MainActor.assumeIsolated {
                    pointer(event)
                }
                return event
            }
            alertObserver = NotificationCenter.default.addObserver(
                forName: PlatformWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let window = notification.object as? PlatformWindow else {
                    return
                }
                MainActor.assumeIsolated {
                    if AppKitAlertFocus.isAlert(window) {
                        AppKitAlertFocus.focusPreferredButton(in: window)
                    }
                }
            }
        }

        /// Removes the monitors.
        func stop() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
            if let pointerMonitor {
                NSEvent.removeMonitor(pointerMonitor)
            }
            pointerMonitor = nil
            if let alertObserver {
                NotificationCenter.default.removeObserver(alertObserver)
            }
            alertObserver = nil
        }
    }
#endif
