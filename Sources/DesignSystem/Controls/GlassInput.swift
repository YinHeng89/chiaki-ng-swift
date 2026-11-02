import SwiftUI

/// The glass field style of the entry screens' text fields.
public struct GlassInput: ViewModifier {
    /// Creates the style.
    public init() {}

    /// Styles a text field.
    ///
    /// - Parameter content: The text field.
    /// - Returns: The field without its own border, padded, on interactive glass.
    public func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .glassEffect(AppGlass.control.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }
}
