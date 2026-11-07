import SwiftUI

/// How a controller button is drawn: an SF Symbol when one exists, and the name the controller's maker uses.
public struct ControllerGlyph: Equatable, Sendable {
    /// The SF Symbol for the button, or `nil` when there is none and the name is shown instead.
    public let symbol: String?

    /// The button's name, such as "Cross" or "LB", also used as its accessibility label.
    public let name: LocalizedStringResource

    /// Creates a glyph.
    ///
    /// - Parameters:
    ///   - symbol: The SF Symbol for the button, if one exists.
    ///   - name: The button's name.
    public init(symbol: String?, name: LocalizedStringResource) {
        self.symbol = symbol
        self.name = name
    }
}

/// A face button named by its position, independent of the controller family's own labels.
public enum ControllerButton: Int, CaseIterable, Sendable {
    /// The bottom face button: Cross, A, or B on Nintendo controllers.
    case south = 0
    /// The right face button: Circle, B, or A on Nintendo controllers.
    case east = 1
    /// The left face button: Square, X, or Y on Nintendo controllers.
    case west = 2
    /// The top face button: Triangle, Y, or X on Nintendo controllers.
    case north = 3
}

/// Turns the controls a hint names into the glyphs of the controller that is driving navigation.
///
/// The app publishes one through ``SwiftUICore/EnvironmentValues/controllerPromptGlyphs`` while a navigation
/// controller is connected, built from that controller's family and button layout. With no controller
/// connected the value is `nil` and every ``ControllerPrompt`` hides itself.
public struct ControllerGlyphResolver: Sendable {
    private let resolve: @Sendable (ControllerPromptControl) -> ControllerGlyph

    /// Creates a resolver.
    ///
    /// - Parameter resolve: Returns the glyph the connected controller uses for a control.
    public init(_ resolve: @escaping @Sendable (ControllerPromptControl) -> ControllerGlyph) {
        self.resolve = resolve
    }

    /// The glyph for a control on the connected controller.
    ///
    /// - Parameter control: The control a hint names.
    /// - Returns: The symbol and name to draw.
    public func glyph(for control: ControllerPromptControl) -> ControllerGlyph {
        resolve(control)
    }
}

extension EnvironmentValues {
    /// The glyphs of the controller driving navigation, or `nil` while no controller is connected.
    @Entry public var controllerPromptGlyphs: ControllerGlyphResolver?
}

/// A control an on-screen hint can name.
public enum ControllerPromptControl: Equatable, Sendable {
    /// A face button.
    case button(ControllerButton)
    /// The left trigger: L2, LT or ZL.
    case leftTrigger
    /// The right trigger: R2, RT or ZR.
    case rightTrigger
}
