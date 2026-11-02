#if os(macOS)
    import AppKit
    import PlatformUI
    import WebKit

    /// Finds the focusable views of an AppKit window and measures them.
    ///
    /// A navigation stop is a visible view that can become key, excluding read-only text. SwiftUI focus
    /// proxies (`KeyViewProxy`) count too. When two stops cover the same control the one that accepts first
    /// responder wins.
    @MainActor
    public enum AppKitKeyViews {
        /// The navigation stops of a window, one per control.
        ///
        /// - Parameter window: The window to search.
        /// - Returns: The stops in view hierarchy order.
        public static func navigationStops(in window: PlatformWindow) -> [NSView] {
            guard let root = window.contentView else {
                return []
            }
            var collected = [NSView]()
            collectStops(in: root, into: &collected)
            var stops = [(view: NSView, frame: CGRect)]()
            for view in collected {
                let frame = focusFrame(view) ?? .zero
                if let index = stops.firstIndex(where: { FocusGeometry.isSameControl($0.frame, frame) }) {
                    if !stops[index].view.acceptsFirstResponder, view.acceptsFirstResponder {
                        stops[index] = (view, frame)
                    }
                } else {
                    stops.append((view, frame))
                }
            }
            return stops.map(\.view)
        }

        /// Whether a responder accepts typed text: a text view or anything inside a web view.
        ///
        /// - Parameter responder: A first responder.
        /// - Returns: `true` when typing goes to `responder`.
        public static func acceptsTextInput(_ responder: NSResponder?) -> Bool {
            if responder is NSTextView {
                return true
            }
            var view = responder as? NSView
            while let current = view {
                if current is WKWebView {
                    return true
                }
                view = current.superview
            }
            return false
        }

        /// Whether a view can take focus during navigation.
        ///
        /// - Parameter view: The view to check.
        /// - Returns: `true` for a visible key view that is not read-only text.
        public static func isNavigationStop(_ view: NSView) -> Bool {
            guard view.window != nil, !view.isHiddenOrHasHiddenAncestor else {
                return false
            }
            if let field = view as? NSTextField, !field.isEditable {
                return false
            }
            if let text = view as? NSTextView, !text.isEditable {
                return false
            }
            if view.accessibilityRole() == .staticText {
                return false
            }
            if view.canBecomeKeyView {
                return true
            }
            return NSStringFromClass(type(of: view)).hasSuffix("KeyViewProxy")
        }

        /// The next navigation stop along the key view loop.
        ///
        /// - Parameters:
        ///   - view: The view to start from.
        ///   - backward: Whether to follow the previous key view instead of the next.
        /// - Returns: The next stop, descending into containers, or `nil` when the loop has none.
        public static func nextNavigationStop(after view: NSView, backward: Bool) -> NSView? {
            var next = step(from: view, backward: backward)
            var visited = 0
            while let candidate = next, candidate !== view, visited < 400 {
                visited += 1
                if isNavigationStop(candidate) {
                    return candidate
                }
                if candidate.window != nil, !candidate.isHiddenOrHasHiddenAncestor,
                   !view.isDescendant(of: candidate),
                   let nested = nestedStop(in: candidate, backward: backward) {
                    return nested
                }
                next = step(from: candidate, backward: backward)
            }
            return nil
        }

        /// The view that has focus in a window, resolving a field editor to the text field that owns it.
        ///
        /// - Parameter window: The window to check.
        /// - Returns: The focused view, if the first responder is a view.
        public static func focusView(in window: PlatformWindow) -> NSView? {
            guard let responder = window.firstResponder as? NSView else {
                return nil
            }
            if let textView = responder as? NSTextView, let owner = textView.delegate as? NSView {
                return owner
            }
            return responder
        }

        /// A responder's frame in window coordinates, rounded to whole points.
        ///
        /// - Parameter responder: A responder.
        /// - Returns: The frame, or `nil` when the responder is not a view.
        public static func focusFrame(_ responder: NSResponder?) -> CGRect? {
            guard let view = responder as? NSView else {
                return nil
            }
            return view.convert(view.bounds, to: nil).integral
        }

        /// Converts a SwiftUI global y position to a window y position.
        ///
        /// - Parameters:
        ///   - globalY: A y position measured from the top of the content view.
        ///   - window: The window.
        /// - Returns: The y position in window coordinates.
        public static func windowY(fromGlobalY globalY: CGFloat, in window: PlatformWindow) -> CGFloat? {
            guard let content = window.contentView else {
                return nil
            }
            let local = content.isFlipped
                ? globalY
                : content.bounds.height - globalY
            return content.convert(CGPoint(x: 0, y: local), to: nil).y
        }

        private static func collectStops(in view: NSView, into stops: inout [NSView]) {
            guard !view.isHidden else {
                return
            }
            if isNavigationStop(view) {
                stops.append(view)
            }
            for subview in view.subviews {
                collectStops(in: subview, into: &stops)
            }
        }

        private static func nestedStop(in view: NSView, backward: Bool) -> NSView? {
            let subviews = backward
                ? Array(view.subviews.reversed())
                : view.subviews
            for subview in subviews where !subview.isHidden {
                if isNavigationStop(subview) {
                    return subview
                }
                if let nested = nestedStop(in: subview, backward: backward) {
                    return nested
                }
            }
            return nil
        }

        private static func step(from view: NSView, backward: Bool) -> NSView? {
            if backward {
                return view.previousKeyView
            }
            return view.nextKeyView
        }
    }
#endif
