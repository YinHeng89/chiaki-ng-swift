import SwiftUI

/// Gives a native control, such as a picker or slider, the app's focus outline and growth.
///
/// Apply it with ``SwiftUICore/View/nativeFocusHighlight()``.
public struct NativeFocusHighlight: ViewModifier {
    @MenuFocusState private var focused: Bool

    /// Creates the modifier.
    public init() {
    }

    /// Tracks the control's focus and draws the outline for its control size.
    ///
    /// - Parameter content: The native control.
    /// - Returns: The control with the app's focus highlight.
    public func body(content: Content) -> some View {
        content
            .menuFocusBinding($focused)
            .interactiveGrowth()
            .environment(\.menuItemFocused, focused)
            .environment(\.focusHighlightStyleShape, .control)
    }
}

extension View {
    /// Draws the app's focus highlight on a native control.
    ///
    /// - Returns: The view with ``NativeFocusHighlight`` applied.
    public func nativeFocusHighlight() -> some View {
        modifier(NativeFocusHighlight())
    }
}
