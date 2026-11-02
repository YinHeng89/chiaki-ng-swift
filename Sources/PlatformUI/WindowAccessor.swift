import SwiftUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Reports the window a SwiftUI view is in, without taking part in hit testing.
///
/// Place it in a `background` and keep the window it resolves; it reports again whenever the view moves to
/// another window and after every SwiftUI update.
public struct WindowAccessor: PlatformViewRepresentable {
    /// The invisible view that watches its window.
    public typealias PlatformViewType = PassthroughView

    private let resolve: (PlatformWindow?) -> Void

    /// Creates an accessor.
    ///
    /// - Parameter resolve: Called on the main queue with the view's window, or `nil` before it has one.
    public init(resolve: @escaping (PlatformWindow?) -> Void) {
        self.resolve = resolve
    }

    /// Creates the passthrough view.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: A view that reports its window.
    public func makePlatformView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        view.resolve = resolve
        return view
    }

    /// Replaces the callback and reports the current window again.
    ///
    /// - Parameters:
    ///   - view: The passthrough view.
    ///   - context: The representable context.
    public func updatePlatformView(_ view: PassthroughView, context: Context) {
        view.resolve = resolve
        DispatchQueue.main.async {
            resolve(view.window)
        }
    }

    /// An empty view that ignores hits and reports each window it joins.
    public final class PassthroughView: PlatformView {
        /// The callback that receives the window.
        public var resolve: ((PlatformWindow?) -> Void)?

        #if os(macOS)
            /// Lets every click pass through to the views below.
            ///
            /// - Parameter point: The point being tested.
            /// - Returns: Always `nil`.
            override public func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }

            /// Reports the new window.
            override public func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                report()
            }
        #else
            /// Lets every touch pass through to the views below.
            ///
            /// - Parameters:
            ///   - point: The point being tested.
            ///   - event: The touch event.
            /// - Returns: Always `nil`.
            override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                nil
            }

            /// Reports the new window.
            override public func didMoveToWindow() {
                super.didMoveToWindow()
                report()
            }
        #endif

        private func report() {
            guard let window else {
                return
            }
            let resolve = resolve
            DispatchQueue.main.async {
                resolve?(window)
            }
        }
    }
}
