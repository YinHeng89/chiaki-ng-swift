import PlatformUI
import SwiftUI

/// Sets `\.ambientMotion` for the content from Reduce Motion, streaming and the hosting window.
struct AmbientMotionGate: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window = AmbientWindowState()

    /// Whether a stream is playing, which pauses decorative motion.
    let streaming: Bool

    /// Observes the hosting window and publishes the resolved ``AmbientMotionState``.
    ///
    /// - Parameter content: The view whose decorative motion is gated.
    /// - Returns: The content with `\.ambientMotion` set.
    func body(content: Content) -> some View {
        content
            .background {
                AmbientWindowObserver { state in
                    if window != state {
                        window = state
                    }
                }
            }
            .environment(
                \.ambientMotion,
                AmbientMotionState.resolve(reduceMotion: reduceMotion, streaming: streaming, window: window)
            )
    }
}

extension View {
    /// Pauses decorative motion inside this view while Reduce Motion is on, a stream is playing,
    /// or its window is hidden or inactive.
    ///
    /// - Parameter streaming: Whether a stream is playing.
    /// - Returns: The view with `\.ambientMotion` set for its contents.
    public func ambientMotion(streaming: Bool) -> some View {
        modifier(AmbientMotionGate(streaming: streaming))
    }
}

/// An invisible view that reports the ``AmbientWindowState`` of the window it is placed in.
private struct AmbientWindowObserver: PlatformViewRepresentable {
    /// The platform view that observes its window.
    typealias PlatformViewType = ObserverView

    /// Receives the window state once the view joins a window and after every relevant change.
    let changed: @MainActor (AmbientWindowState) -> Void

    /// Creates the observing view.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: An ``ObserverView`` that reports to ``changed``.
    func makePlatformView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.changed = changed
        return view
    }

    /// Points an existing observing view at the current callback.
    ///
    /// - Parameters:
    ///   - view: The view created by ``makePlatformView(context:)``.
    ///   - context: The representable context.
    func updatePlatformView(_ view: ObserverView, context: Context) {
        view.changed = changed
    }

    /// A view that ignores hit testing and subscribes to its window's notifications.
    final class ObserverView: PlatformView {
        /// Receives the window state.
        var changed: @MainActor (AmbientWindowState) -> Void = { _ in
        }

        private var tokens = [NSObjectProtocol]()

        #if os(macOS)
            /// Lets every event pass through to the views beneath.
            ///
            /// - Parameter point: The location being tested.
            /// - Returns: Always `nil`.
            override func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            /// Moves the subscriptions to the new window and reports its state.
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                observe()
            }
        #else
            /// Lets every touch pass through to the views beneath.
            ///
            /// - Parameters:
            ///   - point: The location being tested.
            ///   - event: The event being delivered.
            /// - Returns: Always `nil`.
            override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                nil
            }

            /// Moves the subscriptions to the new window and reports its state.
            override func didMoveToWindow() {
                super.didMoveToWindow()
                observe()
            }
        #endif

        private func observe() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            guard let window else {
                return
            }
            let source = AmbientWindowState.source(for: window)
            tokens = AmbientWindowState.changes.map { name in
                NotificationCenter.default
                    .addObserver(forName: name, object: source, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.report(after: name)
                        }
                    }
            }
            DispatchQueue.main.async { [weak self] in
                self?.report(after: nil)
            }
        }

        private func report(after change: Notification.Name?) {
            guard let window else {
                return
            }
            guard let change else {
                changed(AmbientWindowState(window: window))
                return
            }
            changed(AmbientWindowState(window: window, after: change))
        }
    }
}
