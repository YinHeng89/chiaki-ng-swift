import SwiftUI
import DesignSystem
import MenuFocus

/// A capsule of mutually exclusive option buttons that selects a value on click, Return or Space, marks the
/// selected option and joins stream menu controller focus when a focus binding is given.
struct StreamMenuChoiceRow<Value: Hashable>: View {
    /// The options in display order.
    let options: [Value]
    /// Returns the label shown for an option.
    let title: (Value) -> String
    /// The selected option.
    @Binding var selection: Value
    /// The stream menu focus binding, or `nil` when the row is shown outside controller navigation.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus, used to draw an option as focused.
    let focusedControl: StreamMenuControl?
    /// Returns the stream menu control that identifies an option for focus.
    let control: (Value) -> StreamMenuControl
    @Environment(\.screenLayout) private var layout

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let target = StreamMenuFocusTarget.control(control(option))
                let focused = focusedControl == control(option)
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .frame(minHeight: layout.controlSize)
                        .background(
                            choiceBackground(isSelected: selection == option),
                            in: .capsule
                        )
                        .contentShape(.capsule)
                        .foregroundStyle(
                            focused
                                ? Color.primary
                                : Color.secondary
                        )
                }
                .buttonStyle(.plain)
                .modifier(OptionalStreamMenuFocus(
                    focus: focus,
                    target: target,
                    isFocused: focused
                ))
                .focusHighlightShape(.capsule)
                .focusWithoutGrowth()
                .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
                    selection = option
                    return .handled
                }
                .accessibilityAddTraits(
                    selection == option
                        ? .isSelected
                        : []
                )
            }
        }
        .padding(4)
        .glassEffect(AppGlass.control, in: .capsule)
    }

    private func choiceBackground(isSelected: Bool) -> Color {
        if isSelected {
            return Color.primary.opacity(0.14)
        }
        return .clear
    }
}

/// Makes content a stream menu focus target with the menu's focus growth and highlight when a focus binding
/// is given, and leaves it unchanged otherwise.
struct OptionalStreamMenuFocus: ViewModifier {
    /// The stream menu focus binding, or `nil` to leave the content unfocusable.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The focus target this content represents.
    let target: StreamMenuFocusTarget
    /// Whether the content holds focus, which drives its focused appearance.
    let isFocused: Bool

    /// Wraps the content in stream menu focus when a binding is present.
    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content
                .menuFocusable()
                .menuFocusBinding(focus, equals: target)
                .focusEffectDisabled()
                .interactiveGrowth()
                .environment(\.menuItemFocused, isFocused)
        } else {
            content
        }
    }
}

/// A stream menu choice that a controller focuses as one row and opens with Confirm.
///
/// Confirm opens the choices as a native menu with the current choice marked and positioned; choosing or
/// dismissing returns focus to the row. The pointer opens the same choices through the SwiftUI menu.
struct StreamMenuDropdown<Option: Hashable>: View {
    /// The label shown before the current choice.
    let title: String
    /// The choices, in order.
    let options: [Option]
    /// The title shown for a choice.
    let optionTitle: (Option) -> String
    /// The current choice.
    @Binding var selection: Option
    /// The control this row represents for controller focus.
    let target: StreamMenuControl
    /// The stream menu focus binding, or `nil` to leave the row out of controller focus.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// Whether the row holds focus.
    let focused: Bool
    @State private var menuAnchor = NativeMenuAnchorReference()
    @Environment(\.screenLayout) private var layout

    /// The title and current choice, with the choice menu and controller focus.
    var body: some View {
        let row = HStack(spacing: 8) {
            Text(title)
            Menu {
                ForEach(options, id: \.self) { option in
                    SwiftUI.Button {
                        selection = option
                        focus?.wrappedValue = .control(target)
                    } label: {
                        if option == selection {
                            Label(optionTitle(option), systemImage: "checkmark")
                        } else {
                            Text(optionTitle(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(optionTitle(selection))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: layout.controlSize)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(optionTitle(selection))
            .focusable(false)
        }
        .nativeMenuAnchor(menuAnchor)
        if let focus {
            row
                .modifier(StreamMenuControlFocus(
                    focus: focus,
                    target: target,
                    focused: focused,
                    confirm: presentChoices
                ))
        } else {
            row
        }
    }

    private func presentChoices() -> Bool {
        _ = menuAnchor.presentMenu(titles: options.map(optionTitle),
                                   selected: options.firstIndex(of: selection)) { index in
            guard options.indices.contains(index) else {
                return
            }
            selection = options[index]
            focus?.wrappedValue = .control(target)
        }
        focus?.wrappedValue = .control(target)
        return true
    }
}

/// Makes a stream menu control a controller focus target that runs the menu's activation on Return or Space,
/// with the menu's focus growth and highlight unless the highlight is turned off.
struct StreamMenuControlFocus: ViewModifier {
    /// The stream menu focus binding.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding
    /// The control this content represents.
    let target: StreamMenuControl
    /// Whether the control holds focus, which drives its focused appearance.
    let focused: Bool
    /// Whether the control grows and draws the control highlight when focused. Toggles turn this off.
    var highlight = true
    /// Runs instead of the menu's activation on Confirm, such as opening a dropdown's choices; returns whether
    /// the press was handled.
    var confirm: (() -> Bool)?
    @Environment(\.streamMenuActivate) private var activate
    @Environment(\.streamMenuSliderAdjusting) private var adjustingSlider

    /// Wraps the content in stream menu focus and the activation key handler.
    @ViewBuilder
    func body(content: Content) -> some View {
        let control = content
            .menuFocusable()
            .menuFocusBinding(focus, equals: .control(target))
            .focusEffectDisabled()
        let activated = control.onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            if let confirm {
                return confirm()
                    ? .handled
                    : .ignored
            }
            guard let activate, activate(target) else {
                return .ignored
            }
            return .handled
        }
        if target.isSlider {
            VStack(alignment: .leading, spacing: 4) {
                styled(activated)
                if focused {
                    SliderAdjustmentPrompt(adjusting: adjustingSlider == target)
                }
            }
        } else {
            styled(activated)
        }
    }

    @ViewBuilder
    private func styled<Control: View>(_ control: Control) -> some View {
        if highlight {
            control
                .interactiveGrowth()
                .environment(\.menuItemFocused, focused)
                .environment(\.focusHighlightStyleShape, .control)
        } else {
            control
                .environment(\.menuItemFocused, focused)
        }
    }
}

/// Makes a stream menu button a controller focus target with the menu's focus growth when a focus binding
/// is given, and leaves it unchanged otherwise.
struct OptionalStreamMenuButtonFocus: ViewModifier {
    /// The stream menu focus binding, or `nil` to leave the button unfocusable.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The control this button represents.
    let target: StreamMenuControl
    /// Whether the button holds focus, which drives its focused appearance.
    let focused: Bool

    /// Wraps the button in stream menu focus when a binding is present.
    func body(content: Content) -> some View {
        if let focus {
            content
                .menuFocusBinding(focus, equals: .control(target))
                .focusEffectDisabled()
                .interactiveGrowth()
                .environment(\.menuItemFocused, focused)
        } else {
            content
        }
    }
}

private struct StreamMenuActivateKey: EnvironmentKey {
    static let defaultValue: (@MainActor (StreamMenuControl) -> Bool)? = nil
}

private struct StreamMenuSliderAdjustingKey: EnvironmentKey {
    static let defaultValue: StreamMenuControl? = nil
}

extension EnvironmentValues {
    /// The stream menu's activation action for a control, which returns whether the press was
    /// handled, or `nil` outside the stream menu.
    var streamMenuActivate: (@MainActor (StreamMenuControl) -> Bool)? {
        get {
            self[StreamMenuActivateKey.self]
        }
        set {
            self[StreamMenuActivateKey.self] = newValue
        }
    }

    /// The stream menu slider being adjusted with the controller, or `nil` when none is.
    var streamMenuSliderAdjusting: StreamMenuControl? {
        get {
            self[StreamMenuSliderAdjustingKey.self]
        }
        set {
            self[StreamMenuSliderAdjustingKey.self] = newValue
        }
    }
}
