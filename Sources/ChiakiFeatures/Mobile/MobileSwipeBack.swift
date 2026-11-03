import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Goes back when the page is swiped far enough sideways, in either direction, the way a navigation stack pops.
///
/// On iOS the swipe is a UIKit pan that recognizes alongside scroll views, so it also works over scrolling
/// pages, where a SwiftUI drag never sees the touches.
struct MobileSwipeBack: ViewModifier {
    /// Whether there is anything to go back from.
    let enabled: Bool

    /// Goes back.
    let back: () -> Void

    /// How far a swipe must travel to go back.
    static let distance: CGFloat = 110

    /// How fast a shorter swipe must be flicked to go back, in points per second.
    static let flick: CGFloat = 700

    @State private var travel: CGFloat = 0

    /// The page with the swipe attached.
    ///
    /// - Parameter content: The page.
    /// - Returns: The page, going back on a sideways swipe.
    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .offset(x: travel)
                .gesture(MobileSwipeRecognizer(enabled: enabled) { moved in
                    travel = moved * 0.6
                } ended: { goesBack in
                    withAnimation(.spring(duration: 0.35)) {
                        travel = 0
                        if goesBack {
                            back()
                        }
                    }
                })
        #else
            content
        #endif
    }

    /// Whether a finished swipe goes back.
    ///
    /// - Parameters:
    ///   - translation: How far the finger travelled.
    ///   - velocity: How fast it was moving when it lifted.
    /// - Returns: `true` for a long or fast enough sideways swipe.
    static func goesBack(translation: CGSize, velocity: CGSize) -> Bool {
        guard abs(translation.width) > abs(translation.height) * 2 else {
            return false
        }
        return abs(translation.width) > distance
            || (abs(translation.width) > distance / 2 && abs(velocity.width) > flick)
    }
}

#if os(iOS)
    /// The UIKit pan behind ``MobileSwipeBack``, recognizing alongside every other gesture and beginning only on a
    /// sideways move while there is something to go back from.
    struct MobileSwipeRecognizer: UIGestureRecognizerRepresentable {
        /// Whether there is anything to go back from.
        let enabled: Bool

        /// Follows the finger with how far it has travelled sideways.
        let moved: (CGFloat) -> Void

        /// Ends the swipe, saying whether it goes back.
        let ended: (Bool) -> Void

        /// Creates the pan.
        ///
        /// - Parameter context: The representable's context.
        /// - Returns: The pan, with the coordinator as its delegate.
        func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
            let recognizer = UIPanGestureRecognizer()
            recognizer.delegate = context.coordinator
            recognizer.cancelsTouchesInView = false
            return recognizer
        }

        /// Keeps the coordinator's view of whether the swipe may begin current.
        ///
        /// - Parameters:
        ///   - recognizer: The pan.
        ///   - context: The representable's context.
        func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
            context.coordinator.enabled = enabled
        }

        /// Creates the delegate.
        ///
        /// - Parameter converter: Converts between coordinate spaces.
        /// - Returns: The delegate.
        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
            Coordinator(enabled: enabled)
        }

        /// Follows the pan and, when it lifts, reports whether it went far or fast enough to go back.
        ///
        /// - Parameters:
        ///   - recognizer: The pan.
        ///   - context: The representable's context.
        func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
            let translation = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .changed:
                moved(translation.x)
            case .ended:
                let velocity = recognizer.velocity(in: recognizer.view)
                ended(MobileSwipeBack.goesBack(
                    translation: CGSize(width: translation.x, height: translation.y),
                    velocity: CGSize(width: velocity.x, height: velocity.y)
                ))
            case .cancelled, .failed:
                ended(false)
            default:
                break
            }
        }

        /// Lets the pan run beside scroll views and begin only on a sideways move.
        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            /// Whether there is anything to go back from.
            var enabled: Bool

            /// Creates the delegate.
            ///
            /// - Parameter enabled: Whether there is anything to go back from.
            init(enabled: Bool) {
                self.enabled = enabled
            }

            /// Begins only while enabled and on a mostly sideways move.
            ///
            /// - Parameter recognizer: The pan.
            /// - Returns: Whether it may begin.
            func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard enabled, let pan = recognizer as? UIPanGestureRecognizer else {
                    return false
                }
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y) * 1.5
            }

            /// Ignores touches that start inside something scrolling sideways, which the swipe would otherwise
            /// steal.
            ///
            /// - Parameters:
            ///   - recognizer: The pan.
            ///   - touch: The touch.
            /// - Returns: Whether the pan follows the touch.
            func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
                var view = touch.view
                while let current = view {
                    if let scroll = current as? UIScrollView,
                       scroll.contentSize.width > scroll.bounds.width + 1 {
                        return false
                    }
                    view = current.superview
                }
                return true
            }

            /// Recognizes alongside every other gesture, scroll views included.
            ///
            /// - Parameters:
            ///   - recognizer: The pan.
            ///   - other: Another gesture.
            /// - Returns: `true`.
            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
            ) -> Bool {
                true
            }
        }
    }
#endif

extension View {
    /// Goes back on a long enough sideways swipe.
    ///
    /// - Parameters:
    ///   - enabled: Whether there is anything to go back from.
    ///   - back: Goes back.
    /// - Returns: The view with the swipe attached.
    func mobileSwipeBack(enabled: Bool, back: @escaping () -> Void) -> some View {
        modifier(MobileSwipeBack(enabled: enabled, back: back))
    }
}
