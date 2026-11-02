import PlatformUI
import SwiftUI

/// Marks a scroll view that scrolls itself to its focused control, so the navigator's automatic reveal
/// leaves it alone.
///
/// Apply it inside the scroll view's content with ``SwiftUICore/View/selfManagedFocusScrolling()``.
public struct SelfManagedFocusScrolling: PlatformViewRepresentable {
    /// The invisible marker view the navigator looks for.
    public typealias PlatformViewType = Marker

    /// Creates the marker.
    public init() {
    }

    /// Creates the marker view.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: A new marker.
    public func makePlatformView(context: Context) -> Marker {
        Marker()
    }

    /// Does nothing; the marker has no state.
    ///
    /// - Parameters:
    ///   - view: The marker.
    ///   - context: The representable context.
    public func updatePlatformView(_ view: Marker, context: Context) {
    }

    /// An empty view that ignores hits and only marks its scroll view.
    public final class Marker: PlatformView {
        #if os(macOS)
            /// Lets every click pass through.
            ///
            /// - Parameter point: The point being tested.
            /// - Returns: Always `nil`.
            override public func hitTest(_ point: CGPoint) -> NSView? {
                nil
            }
        #else
            /// Lets every touch pass through.
            ///
            /// - Parameters:
            ///   - point: The point being tested.
            ///   - event: The touch event.
            /// - Returns: Always `nil`.
            override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
                nil
            }
        #endif
    }
}

extension View {
    /// Tells the navigator that this scroll view keeps its focused control visible by itself.
    ///
    /// - Returns: The view with a ``SelfManagedFocusScrolling`` marker in its background.
    public func selfManagedFocusScrolling() -> some View {
        background(SelfManagedFocusScrolling())
    }
}
