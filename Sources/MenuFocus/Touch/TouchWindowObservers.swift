#if os(iOS)
    import CoreGraphics
    import Observation
    import PlatformUI
    import UIKit

    /// Puts a ``TouchObserver`` on every window of the app, including windows that become key later.
    @MainActor
    final class TouchWindowObservers {
        private var recognizers = [ObjectIdentifier: TouchObserver]()
        private var keyObserver: NSObjectProtocol?

        /// Observes touches in every window of every connected scene and in each window that becomes key.
        ///
        /// - Parameter navigator: The navigator the observers report touches to.
        func start(reportingTo navigator: TouchMenuNavigator) {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                for window in scene.windows {
                    observe(window, reportingTo: navigator)
                }
            }
            guard keyObserver == nil else {
                return
            }
            keyObserver = NotificationCenter.default.addObserver(
                forName: PlatformWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak navigator] notification in
                guard let window = notification.object as? PlatformWindow else {
                    return
                }
                nonisolated(unsafe) let keyWindow = window
                MainActor.assumeIsolated {
                    guard let navigator else {
                        return
                    }
                    self?.observe(keyWindow, reportingTo: navigator)
                }
            }
        }

        /// Removes every observer.
        func stop() {
            for observer in recognizers.values {
                observer.view?.removeGestureRecognizer(observer)
            }
            recognizers = [:]
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
            }
            keyObserver = nil
        }

        private func observe(_ window: PlatformWindow, reportingTo navigator: TouchMenuNavigator) {
            let id = ObjectIdentifier(window)
            guard recognizers[id] == nil else {
                return
            }
            let observer = TouchObserver(target: nil, action: nil)
            observer.navigator = navigator
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            window.addGestureRecognizer(observer)
            recognizers[id] = observer
        }
    }

    /// Watches every touch in a window for the touch navigator without taking part in gesture recognition.
    ///
    /// A touch switches the app to pointer mode and records a single finger's press for
    /// ``TouchPress``.
    final class TouchObserver: UIGestureRecognizer {
        /// The navigator to report touches to.
        weak var navigator: TouchMenuNavigator?

        /// Reports a touch landing.
        ///
        /// - Parameters:
        ///   - touches: The touches that began.
        ///   - event: The touch event.
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            navigator?.touched(in: view as? UIWindow)
            guard numberOfTouches == 1, let touch = touches.first else {
                navigator?.touchPress.ended()
                return
            }
            navigator?.touchPress.began(at: touch.location(in: nil))
        }

        /// Reports a finger moving.
        ///
        /// - Parameters:
        ///   - touches: The touches that moved.
        ///   - event: The touch event.
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else {
                return
            }
            navigator?.touchPress.moved(to: touch.location(in: nil))
        }

        /// Ends the press and fails, so no other gesture is affected.
        ///
        /// - Parameters:
        ///   - touches: The touches that ended.
        ///   - event: The touch event.
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            navigator?.touchPress.ended()
            state = .failed
        }

        /// Ends the press and fails.
        ///
        /// - Parameters:
        ///   - touches: The touches that were cancelled.
        ///   - event: The touch event.
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            navigator?.touchPress.ended()
            state = .failed
        }

        /// Never blocks another gesture.
        ///
        /// - Parameter preventedGestureRecognizer: Another recognizer.
        /// - Returns: Always `false`.
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        /// Is never blocked by another gesture.
        ///
        /// - Parameter preventingGestureRecognizer: Another recognizer.
        /// - Returns: Always `false`.
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }

    /// Where a single finger is resting, so the control under it can draw itself pressed.
    ///
    /// The press ends when the finger lifts or slides more than ``slop`` points.
    @MainActor
    @Observable
    public final class TouchPress {
        /// How far a finger may slide before the press is abandoned.
        public static let slop: CGFloat = 10

        /// The finger's position in global coordinates, or `nil` when no press is in progress.
        public private(set) var location: CGPoint?

        /// Creates a tracker with no press.
        public init() {
        }

        /// Records a finger landing.
        ///
        /// - Parameter point: Where it landed.
        public func began(at point: CGPoint) {
            location = point
        }

        /// Records a finger moving, abandoning the press beyond ``slop``.
        ///
        /// - Parameter point: Where it moved to.
        public func moved(to point: CGPoint) {
            guard let location else {
                return
            }
            if hypot(point.x - location.x, point.y - location.y) > Self.slop {
                ended()
            }
        }

        /// Records the finger lifting or the touch being cancelled.
        public func ended() {
            guard location != nil else {
                return
            }
            location = nil
        }
    }
#endif
