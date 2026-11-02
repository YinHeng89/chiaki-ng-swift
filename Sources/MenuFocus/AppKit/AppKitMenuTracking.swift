#if os(macOS)
    import AppKit
    import PlatformUI

    /// Watches native menus and returns focus to the control that opened a pop-up menu once it closes.
    ///
    /// When an item was chosen, focus also advances one step so the next press continues the flow.
    @MainActor
    final class AppKitMenuTracking {
        private let activeWindow: () -> PlatformWindow?
        private let returnFocus: (NSView, PlatformWindow, Bool) -> Void
        private var menus = Set<ObjectIdentifier>()
        private var origin: (window: PlatformWindow, view: NSView)?
        private var selected = false
        private var observers = [NSObjectProtocol]()

        /// Creates a tracker.
        ///
        /// - Parameters:
        ///   - activeWindow: Resolves the window a menu opens over.
        ///   - returnFocus: Focuses a view in a window again, advancing one step when the flag is set.
        init(
            activeWindow: @escaping () -> PlatformWindow?,
            returnFocus: @escaping (NSView, PlatformWindow, Bool) -> Void
        ) {
            self.activeWindow = activeWindow
            self.returnFocus = returnFocus
        }

        /// Whether a native menu is open and tracking input.
        var isTracking: Bool {
            !menus.isEmpty
        }

        /// Starts observing native menus.
        func start() {
            guard observers.isEmpty else {
                return
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSMenu.didSendActionNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.selected = true
                }
            })
            for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let menu = notification.object as? NSMenu else {
                        return
                    }
                    let began = notification.name == NSMenu.didBeginTrackingNotification
                    nonisolated(unsafe) let trackedMenu = menu
                    MainActor.assumeIsolated {
                        self?.tracking(trackedMenu, began: began)
                    }
                })
            }
        }

        /// Stops observing and forgets every open menu.
        func stop() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            menus.removeAll()
            origin = nil
            selected = false
        }

        private func tracking(_ menu: NSMenu, began: Bool) {
            let id = ObjectIdentifier(menu)
            if began {
                if menus.isEmpty {
                    beginCapture(menu)
                }
                menus.insert(id)
            } else {
                menus.remove(id)
                if menus.isEmpty {
                    finishCapture()
                }
            }
        }

        private func beginCapture(_ menu: NSMenu) {
            selected = false
            origin = nil
            guard menu !== NSApp.mainMenu,
                  menu.supermenu == nil,
                  let window = activeWindow(),
                  let view = window.firstResponder as? NSView,
                  !(view is NSTextView),
                  view !== window.contentView else {
                return
            }
            origin = (window, view)
        }

        private func finishCapture() {
            guard let origin else {
                return
            }
            self.origin = nil
            let advance = selected
            selected = false
            returnFocus(origin.view, origin.window, advance)
        }
    }
#endif
