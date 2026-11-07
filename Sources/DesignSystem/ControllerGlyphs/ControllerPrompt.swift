import SwiftUI

/// An on-screen hint pairing a controller button with what it does, such as the Circle glyph and "Close".
///
/// The glyph follows the connected navigation controller through
/// ``SwiftUICore/EnvironmentValues/controllerPromptGlyphs``. The hint draws nothing while no controller is
/// connected.
public struct ControllerPrompt: View {
    private let control: ControllerPromptControl
    private let text: LocalizedStringResource
    @Environment(\.controllerPromptGlyphs) private var glyphs

    /// Creates a hint for a face button.
    ///
    /// - Parameters:
    ///   - button: The button the hint names.
    ///   - text: What the button does.
    public init(button: ControllerButton, text: LocalizedStringResource) {
        control = .button(button)
        self.text = text
    }

    /// Creates a hint for any control.
    ///
    /// - Parameters:
    ///   - control: The control the hint names.
    ///   - text: What the control does.
    public init(control: ControllerPromptControl, text: LocalizedStringResource) {
        self.control = control
        self.text = text
    }

    /// The glyph and text, or nothing without a controller.
    public var body: some View {
        if let glyphs {
            let glyph = glyphs.glyph(for: control)
            HStack(spacing: 6) {
                ControllerGlyphLabel(glyph: glyph, showsName: false)
                Text(text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(.promptAccessibility(
                button: String(localized: glyph.name),
                action: String(localized: text)
            ))
        }
    }
}

/// Draws a controller button as its symbol, its name, or both.
public struct ControllerGlyphLabel: View {
    private let glyph: ControllerGlyph
    private let showsName: Bool

    /// Creates a label for a button.
    ///
    /// - Parameters:
    ///   - glyph: The button to draw.
    ///   - showsName: Whether the name is shown beside the symbol. A glyph without a symbol always shows
    ///     its name.
    public init(glyph: ControllerGlyph, showsName: Bool = true) {
        self.glyph = glyph
        self.showsName = showsName
    }

    /// The symbol and name, read by accessibility as the button's name.
    public var body: some View {
        HStack(spacing: 5) {
            if let symbol = glyph.symbol {
                Image(systemName: symbol)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
            }
            if showsName || glyph.symbol == nil {
                Text(glyph.name)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(glyph.name)
    }
}

/// The controller hint shown below a focused slider: how to start adjusting it, or how to finish or cancel.
///
/// It follows the connected controller's glyphs through ``ControllerPrompt`` and draws nothing without a
/// controller.
public struct SliderAdjustmentPrompt: View {
    private let adjusting: Bool

    /// Creates the hint.
    ///
    /// - Parameter adjusting: Whether the slider is being adjusted.
    public init(adjusting: Bool) {
        self.adjusting = adjusting
    }

    /// The Confirm hint, and the Cancel hint while adjusting.
    public var body: some View {
        HStack(spacing: 12) {
            ControllerPrompt(button: .south, text: adjusting
                ? .sliderFinishAdjusting
                : .sliderAdjust)
            if adjusting {
                ControllerPrompt(button: .east, text: .sliderCancelAdjustment)
            }
        }
        .font(.caption)
    }
}
