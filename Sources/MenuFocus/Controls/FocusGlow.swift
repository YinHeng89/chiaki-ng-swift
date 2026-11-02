import DesignSystem
import SwiftUI

/// The accent fill and outline drawn around a hovered or focused control.
///
/// The fill follows the tint opacity; the two-point outline appears only once the tint reaches the
/// focused level. Inner controls see ``SwiftUICore/EnvironmentValues/focusGlowDrawnOutside`` and skip their
/// own glow, so a control shows exactly one outline.
struct FocusGlow: ViewModifier {
    /// The tint opacity from which the outline is drawn.
    static let focusedTint = 0.15

    /// How far the glow extends past the control's edge.
    static let outset: CGFloat = 1

    /// The outline's shape.
    let shape: FocusHighlightShape

    /// The tint's opacity.
    let opacity: Double
    @Environment(\.focusGlowDrawnOutside) private var drawnOutside

    /// Draws the fill behind and the outline over the control.
    ///
    /// - Parameter content: The control.
    /// - Returns: The control with its glow.
    func body(content: Content) -> some View {
        content
            .environment(\.focusGlowDrawnOutside, drawnOutside || opacity > 0)
            .background {
                shape.outset(by: Self.outset)
                    .fill(Palette.accent.opacity(fillOpacity))
                    .padding(-Self.outset)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.outset(by: Self.outset)
                    .stroke(Palette.accent.opacity(ringOpacity), lineWidth: 2)
                    .padding(-Self.outset)
                    .allowsHitTesting(false)
            }
    }

    private var fillOpacity: Double {
        drawnOutside
            ? 0
            : opacity
    }

    private var ringOpacity: Double {
        !drawnOutside && opacity >= Self.focusedTint
            ? 0.9
            : 0
    }
}

/// Draws the focus tint of an enclosing control around an inner view, for controls whose highlight is
/// ``FocusHighlightShape/contained``, such as a checkbox that outlines only its box.
///
/// Apply it with ``SwiftUICore/View/containedFocusGlow(in:)``.
public struct ContainedFocusGlow: ViewModifier {
    private let shape: FocusHighlightShape
    @Environment(\.containedFocusGlowOpacity) private var opacity

    /// Creates the modifier.
    ///
    /// - Parameter shape: The shape of the inner view's outline.
    public init(shape: FocusHighlightShape) {
        self.shape = shape
    }

    /// Draws the tint the enclosing control handed down.
    ///
    /// - Parameter content: The inner view.
    /// - Returns: The inner view with the tint.
    public func body(content: Content) -> some View {
        content.modifier(FocusGlow(shape: shape, opacity: opacity))
    }
}

extension View {
    /// Draws the enclosing control's focus tint around this view.
    ///
    /// - Parameter shape: The shape of the outline.
    /// - Returns: The view with ``ContainedFocusGlow`` applied.
    public func containedFocusGlow(in shape: FocusHighlightShape) -> some View {
        modifier(ContainedFocusGlow(shape: shape))
    }
}
