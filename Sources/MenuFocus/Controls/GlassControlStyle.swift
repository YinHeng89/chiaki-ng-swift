import DesignSystem
import SwiftUI

/// Applies the app's glass button styles together with the focus outline they need.
///
/// A glass button's outline follows its bezel, which depends on its control size, so these styles also
/// set ``FocusHighlightShape/control``. On touch a bezel below the large control size grows to it, so every
/// glass button is at least a finger tall. Apply them with ``SwiftUICore/View/glassControlStyle(_:)`` and
/// ``SwiftUICore/View/glassProminentControlStyle()``.
public struct GlassControlStyle: ViewModifier {
    /// Which glass button style to use.
    public enum Kind: Sendable {
        /// The clear glass style of ordinary buttons.
        case standard(Glass)
        /// The tinted prominent style of primary actions.
        case prominent
    }

    private let kind: Kind
    @Environment(\.screenLayout) private var layout

    /// Creates the modifier.
    ///
    /// - Parameter kind: Which glass style to use.
    public init(kind: Kind) {
        self.kind = kind
    }

    /// Applies the button style and the matching outline shape.
    ///
    /// - Parameter content: The button.
    /// - Returns: The styled button.
    public func body(content: Content) -> some View {
        switch kind {
        case .standard(let glass):
            content
                .buttonStyle(.glass(glass))
                .transformEnvironment(\.controlSize, transform: raiseForTouch)
                .environment(\.focusHighlightStyleShape, .control)
        case .prominent:
            content
                .buttonStyle(.glassProminent)
                .transformEnvironment(\.controlSize, transform: raiseForTouch)
                .environment(\.focusHighlightStyleShape, .control)
        }
    }

    private func raiseForTouch(_ size: inout ControlSize) {
        guard layout.touch else {
            return
        }
        switch size {
        case .mini, .small, .regular:
            size = .large
        case .large, .extraLarge:
            break
        @unknown default:
            break
        }
    }
}

extension View {
    /// Styles buttons with clear glass and the matching focus outline.
    ///
    /// - Parameter glass: The glass to use, `AppGlass/control` unless a control needs another.
    /// - Returns: The view with ``GlassControlStyle`` applied.
    public func glassControlStyle(_ glass: Glass = AppGlass.control) -> some View {
        modifier(GlassControlStyle(kind: .standard(glass)))
    }

    /// Styles buttons with prominent glass and the matching focus outline.
    ///
    /// - Returns: The view with ``GlassControlStyle`` applied.
    public func glassProminentControlStyle() -> some View {
        modifier(GlassControlStyle(kind: .prominent))
    }
}
