import SwiftUI

/// The rounded glass surface behind panels, cards and modals.
///
/// Panels use one of four named corner radii instead of a radius chosen per view, so surfaces of the same
/// role look the same everywhere. Apply one with ``SwiftUICore/View/glassPanel(_:)``.
public enum GlassPanel {
    /// A named corner radius for a glass surface.
    public enum Radius: CGFloat, Sendable {
        /// Rows, tiles and compact panels.
        case small = 12
        /// Inline panels and popovers.
        case medium = 18
        /// Large panels and side sheets.
        case large = 24
        /// Modal cards and full overlays.
        case modal = 28

        /// The radius in points.
        public var points: CGFloat {
            rawValue
        }

        /// The rounded rectangle with this radius.
        public var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: rawValue)
        }
    }
}

extension View {
    /// Draws the panel glass behind the view, rounded with a named radius.
    ///
    /// - Parameter radius: The corner radius of the panel.
    /// - Returns: The view on a glass panel.
    public func glassPanel(_ radius: GlassPanel.Radius) -> some View {
        glassEffect(AppGlass.panel, in: .rect(cornerRadius: radius.points))
    }
}
