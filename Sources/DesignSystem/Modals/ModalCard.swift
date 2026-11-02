import SwiftUI

/// The chrome around a modal card: panel glass, rounded corners and a drop shadow.
///
/// Every modal in the app draws its card through this modifier instead of repeating the glass, clip and
/// shadow by hand. Apply it with ``SwiftUICore/View/modalCard(_:)``.
public struct ModalCard: ViewModifier {
    /// Where the card is shown, which decides how it sits on the content behind it.
    public enum Style: Sendable {
        /// A card over the app's own screens: an opaque fallback when Reduce Transparency is on, a soft
        /// shadow and an outer margin.
        case app
        /// A card over a stream or full-screen overlay: a deeper shadow and no outer margin.
        case overlay
    }

    private let style: Style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Creates the chrome for one style of card.
    ///
    /// - Parameter style: Where the card is shown.
    public init(style: Style) {
        self.style = style
    }

    /// Wraps the card content in its chrome.
    ///
    /// - Parameter content: The card's content.
    /// - Returns: The content on a rounded glass card.
    public func body(content: Content) -> some View {
        switch style {
        case .app:
            content
                .background(appBackground, in: GlassPanel.Radius.modal.shape)
                .glassPanel(.modal)
                .clipShape(GlassPanel.Radius.modal.shape)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                .padding(20)
        case .overlay:
            content
                .glassPanel(.modal)
                .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
        }
    }

    private var appBackground: Color {
        reduceTransparency
            ? Palette.windowBackground
            : .clear
    }
}

extension View {
    /// Draws the view as a modal card.
    ///
    /// - Parameter style: Where the card is shown.
    /// - Returns: The view inside the shared modal chrome.
    public func modalCard(_ style: ModalCard.Style) -> some View {
        modifier(ModalCard(style: style))
    }
}
