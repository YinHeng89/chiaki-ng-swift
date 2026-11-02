import SwiftUI

/// The shape of a control's focus outline, which hugs the control instead of drawing a halo.
public enum FocusHighlightShape: Equatable, Sendable {
    /// A rounded rectangle with the given corner radius.
    case roundedRectangle(CGFloat)
    /// A circle.
    case circle
    /// A capsule, for sliders and pills.
    case capsule
    /// The outline is drawn by an inner view with ``SwiftUICore/View/containedFocusGlow(in:)``.
    case contained
    /// The shape of a glass button at its control size: see ``resolved(for:)``.
    case control

    /// The outline of an ordinary control: a 10-point rounded rectangle.
    public static let standard = FocusHighlightShape.roundedRectangle(10)

    /// The shape as a SwiftUI shape.
    public var shape: AnyShape {
        outset(by: 0)
    }

    /// The shape grown outwards.
    ///
    /// - Parameter amount: How many points to grow it by.
    /// - Returns: The grown shape; corner radii grow with it.
    public func outset(by amount: CGFloat) -> AnyShape {
        switch self {
        case .roundedRectangle(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius + amount))
        case .circle:
            AnyShape(Circle())
        case .capsule, .control:
            AnyShape(Capsule())
        case .contained:
            AnyShape(Rectangle())
        }
    }

    /// The concrete shape of a ``control`` outline at a control size: 5-point corners for small, 6 for
    /// regular, a capsule for large. Other shapes pass through.
    ///
    /// - Parameter size: The control size.
    /// - Returns: The concrete shape.
    public func resolved(for size: ControlSize) -> FocusHighlightShape {
        guard self == .control else {
            return self
        }
        switch size {
        case .mini, .small:
            return .roundedRectangle(5)
        case .regular:
            return .roundedRectangle(6)
        default:
            return .capsule
        }
    }

    /// The button border shape that matches the outline.
    public var buttonBorderShape: ButtonBorderShape {
        switch self {
        case .roundedRectangle(let radius):
            .roundedRectangle(radius: radius)
        case .circle:
            .circle
        case .capsule:
            .capsule
        case .contained, .control:
            .automatic
        }
    }
}

extension EnvironmentValues {
    /// The outline shape a control declared with ``SwiftUICore/View/focusHighlightShape(_:)``.
    @Entry public var focusHighlightShape: FocusHighlightShape?

    /// The outline shape a button style implies, used when the control declared none.
    @Entry public var focusHighlightStyleShape: FocusHighlightShape?

    /// The tint an enclosing control hands to an inner view drawing a contained outline.
    @Entry public var containedFocusGlowOpacity: Double = 0

    /// Whether an enclosing view already draws the focus outline, so inner views draw none.
    @Entry public var focusGlowDrawnOutside = false

    /// Whether controls skip growing while highlighted, for tight tracks and shared glass containers.
    @Entry public var focusGrowthSuppressed = false

    /// The outline shape in effect: the declared shape, else the style's, else ``FocusHighlightShape/standard``.
    public var resolvedFocusHighlightShape: FocusHighlightShape {
        focusHighlightShape ?? focusHighlightStyleShape ?? .standard
    }
}

extension View {
    /// Declares the shape of the view's focus outline.
    ///
    /// - Parameter shape: The outline's shape.
    /// - Returns: The view with the shape set.
    public func focusHighlightShape(_ shape: FocusHighlightShape) -> some View {
        environment(\.focusHighlightShape, shape)
    }

    /// Declares that the view draws its own focus border, so no other outline is drawn.
    ///
    /// - Returns: The view with shared outlines turned off.
    public func drawsOwnFocusHighlight() -> some View {
        environment(\.focusGlowDrawnOutside, true)
    }

    /// Turns off growth for controls inside the view.
    ///
    /// - Returns: The view with growth suppressed.
    public func focusWithoutGrowth() -> some View {
        environment(\.focusGrowthSuppressed, true)
    }

    /// Sets the button border shape and the matching focus outline together.
    ///
    /// - Parameter shape: The outline's shape.
    /// - Returns: The view with both shapes set.
    public func focusBorderShape(_ shape: FocusHighlightShape) -> some View {
        buttonBorderShape(shape.buttonBorderShape).focusHighlightShape(shape)
    }
}
