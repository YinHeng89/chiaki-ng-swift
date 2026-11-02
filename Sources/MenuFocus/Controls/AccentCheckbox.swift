import DesignSystem
import SwiftUI

/// The checkbox drawn by ``AccentCheckboxToggleStyle``: a 16-point box filled with the accent when on.
///
/// Return and Space toggle it; its focus outline hugs only the box. On touch the row it sits in is at least a
/// finger tall, so the box stays small while the hit area does not. Accessibility sees a native toggle.
struct AccentCheckbox: View {
    /// The toggle being drawn.
    let configuration: ToggleStyleConfiguration

    /// Whether the checkbox takes controller focus itself.
    let focusable: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.menuItemFocused) private var inheritedFocus
    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.screenLayout) private var layout
    @MenuFocusState private var focused: Bool

    /// The box and label as one plain button.
    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                box
                if labelsVisibility != .hidden {
                    configuration.label
                }
            }
            .frame(minHeight: layout.controlSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuFocusable(focusable && isEnabled)
        .menuFocusBinding($focused)
        .focusEffectDisabled()
        .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            guard focusable, isEnabled else {
                return .ignored
            }
            configuration.isOn.toggle()
            return .handled
        }
        .opacity(
            isEnabled
                ? 1
                : 0.45
        )
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
        }
    }

    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    configuration.isOn
                        ? Palette.accent
                        : Color.primary.opacity(0.08)
                )
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    configuration.isOn
                        ? Color.clear
                        : Color.primary.opacity(0.3),
                    lineWidth: 1
                )
            if configuration.isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 16, height: 16)
        .interactiveGrowth()
        .focusHighlightShape(.roundedRectangle(4))
        .environment(\.menuItemFocused, focused || inheritedFocus)
    }
}

/// The app's toggle style: an accent-filled checkbox that is a controller focus stop.
///
/// The app applies it to every toggle at the root; apply it yourself to a toggle outside that tree.
public struct AccentCheckboxToggleStyle: ToggleStyle {
    private let focusable: Bool

    /// Creates the style.
    ///
    /// - Parameter focusable: Whether the checkbox takes controller focus itself. Pass `false` when an
    ///   enclosing row is the focus stop.
    public init(focusable: Bool = true) {
        self.focusable = focusable
    }

    /// Draws the toggle as an ``AccentCheckbox``.
    ///
    /// - Parameter configuration: The toggle's state and label.
    /// - Returns: The checkbox.
    public func makeBody(configuration: Configuration) -> some View {
        AccentCheckbox(configuration: configuration, focusable: focusable)
    }
}
