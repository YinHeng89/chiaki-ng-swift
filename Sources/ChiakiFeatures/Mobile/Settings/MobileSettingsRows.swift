import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// A touch settings page: its groups in two columns on a wide screen and one column otherwise, scrolling as one.
struct MobileSettingsForm<Leading: View, Trailing: View>: View {
    /// The groups of the first column.
    @ViewBuilder let leading: Leading

    /// The groups of the second column, which follow the first on a narrow screen.
    @ViewBuilder let trailing: Trailing

    @Environment(\.screenLayout) private var layout

    var body: some View {
        ScrollView {
            Group {
                if !layout.isCompact || layout.isShort {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 20) {
                            leading
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 20) {
                            trailing
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        leading
                        trailing
                    }
                }
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .tint(Palette.accent)
    }
}

extension MobileSettingsForm where Trailing == EmptyView {
    /// Creates a one-column page.
    ///
    /// - Parameter leading: The page's groups.
    init(@ViewBuilder leading: () -> Leading) {
        self.leading = leading()
        trailing = EmptyView()
    }
}

/// A group of settings rows: an optional title above one rounded block of rows divided by hairlines, and an
/// optional footer explaining the group below it.
struct MobileSettingsGroup<Content: View>: View {
    /// The title above the group.
    var title: Text?

    /// The explanation below the group.
    var footer: LocalizedStringResource?

    /// The rows.
    @ViewBuilder let content: Content

    /// Creates a group.
    ///
    /// - Parameters:
    ///   - title: The title above the group.
    ///   - footer: The explanation below the group.
    ///   - content: The rows.
    init(
        _ title: LocalizedStringResource? = nil,
        footer: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title.map { Text($0) }
        self.footer = footer
        self.content = content()
    }

    /// Creates a group whose title is shown as it is, such as a name.
    ///
    /// - Parameters:
    ///   - verbatim: The title above the group, shown without localization.
    ///   - footer: The explanation below the group.
    ///   - content: The rows.
    init(
        verbatim: String,
        footer: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        title = Text(verbatim: verbatim)
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                title
                    .textCase(.uppercase)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        row
                        if index < rows.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 24))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }
}

/// A settings row with a switch at its trailing edge.
struct MobileToggleRow: View {
    /// The title.
    let title: LocalizedStringResource

    /// A line under the title.
    var detail: LocalizedStringResource?

    /// The setting.
    @Binding var isOn: Bool

    /// Creates a switch row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    ///   - isOn: The setting.
    init(_ title: LocalizedStringResource, detail: LocalizedStringResource? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            MobileRowTitle(title: title, detail: detail)
        }
        .toggleStyle(.switch)
        .tint(Palette.accent)
        .mobileRowPadding()
        .contentShape(.rect)
        .mobileRowFocus {
            isOn.toggle()
        }
    }
}

/// A settings row choosing one value from a menu, showing the current value at its trailing edge.
///
/// A tap opens the menu. With a controller the row is one focus stop, and Confirm opens the same choices as a
/// native menu anchored to the row.
struct MobilePickerRow<Value: Hashable>: View {
    /// The title.
    let title: LocalizedStringResource

    /// A line under the title.
    var detail: LocalizedStringResource?

    /// The chosen value.
    @Binding var selection: Value

    /// The values offered, in order.
    let choices: [Value]

    /// A value's name in the menu, resolved for the current locale.
    private let label: (Value) -> String

    @State private var menuAnchor = NativeMenuAnchorReference()

    /// Creates a menu row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    ///   - selection: The chosen value.
    ///   - choices: The values offered, in order.
    ///   - label: A value's name in the menu.
    init(
        _ title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        selection: Binding<Value>,
        choices: [Value],
        label: @escaping (Value) -> LocalizedStringResource
    ) {
        self.title = title
        self.detail = detail
        _selection = selection
        self.choices = choices
        self.label = { String(localized: label($0)) }
    }

    /// Creates a menu row whose values are shown as they are, such as names.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    ///   - selection: The chosen value.
    ///   - choices: The values offered, in order.
    ///   - verbatimLabel: A value's name in the menu, shown without localization.
    init(
        _ title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        selection: Binding<Value>,
        choices: [Value],
        verbatimLabel: @escaping (Value) -> String
    ) {
        self.title = title
        self.detail = detail
        _selection = selection
        self.choices = choices
        label = verbatimLabel
    }

    var body: some View {
        HStack(spacing: 12) {
            MobileRowTitle(title: title, detail: detail)
            Spacer(minLength: 8)
            Picker(selection: $selection) {
                ForEach(choices, id: \.self) { choice in
                    Text(verbatim: label(choice)).tag(choice)
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.secondary)
        }
        .mobileRowPadding()
        .contentShape(.rect)
        .nativeMenuAnchor(menuAnchor)
        .mobileRowFocus(activate: presentChoices)
        .accessibilityValue(label(selection))
    }

    private func presentChoices() {
        menuAnchor.presentMenu(
            titles: choices.map(label),
            selected: choices.firstIndex(of: selection)
        ) { index in
            guard choices.indices.contains(index) else {
                return
            }
            selection = choices[index]
        }
    }
}

/// A settings row showing a value, optionally opening something when tapped.
struct MobileValueRow: View {
    /// The title.
    let title: Text

    /// The value at the trailing edge.
    var value: Text?

    /// What a tap does, or `nil` for a plain row.
    var action: (() -> Void)?

    /// Creates a value row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - value: The value at the trailing edge.
    ///   - action: What a tap does, or `nil` for a plain row.
    init(
        _ title: LocalizedStringResource,
        value: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = Text(title)
        self.value = value.map { Text($0) }
        self.action = action
    }

    /// Creates a value row whose value is shown as it is, such as a name, a number or a path.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - verbatim: The value at the trailing edge, shown without localization.
    ///   - action: What a tap does, or `nil` for a plain row.
    init(_ title: LocalizedStringResource, verbatim: String?, action: (() -> Void)? = nil) {
        self.title = Text(title)
        value = verbatim.map { Text(verbatim: $0) }
        self.action = action
    }

    /// Creates a value row whose title and value are both shown as they are, such as a person's name and
    /// their address.
    ///
    /// - Parameters:
    ///   - verbatimTitle: The title, shown without localization.
    ///   - verbatim: The value at the trailing edge, shown without localization.
    ///   - action: What a tap does, or `nil` for a plain row.
    init(verbatimTitle: String, verbatim: String?, action: (() -> Void)? = nil) {
        title = Text(verbatim: verbatimTitle)
        value = verbatim.map { Text(verbatim: $0) }
        self.action = action
    }

    var body: some View {
        if let action {
            FocusButton(action: action) {
                content(chevron: true)
            }
            .buttonStyle(.plain)
            .focusWithoutGrowth()
            .focusHighlightShape(MobileRowFocus.shape)
        } else {
            content(chevron: false)
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            title
            Spacer(minLength: 8)
            if let value {
                value
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .mobileRowPadding()
        .contentShape(.rect)
    }
}

/// A settings row that runs an action, its title in the accent colour, or red when destructive.
struct MobileButtonRow: View {
    /// The title.
    let title: LocalizedStringResource

    /// Whether the action destroys something.
    var destructive = false

    /// What a tap does.
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    /// Creates an action row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - destructive: Whether the action destroys something.
    ///   - action: What a tap does.
    init(_ title: LocalizedStringResource, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        FocusButton(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(
                        destructive
                            ? Color.red
                            : Palette.accent
                    )
                    .opacity(
                        isEnabled
                            ? 1
                            : 0.4
                    )
                Spacer()
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(MobileRowFocus.shape)
    }
}

/// A settings row with a slider under its title and current value.
struct MobileSliderRow: View {
    /// The title.
    let title: LocalizedStringResource

    /// The current value, as shown.
    let valueText: Text

    /// The value.
    @Binding var value: Double

    /// The values the slider covers.
    let range: ClosedRange<Double>

    /// The step between values, or `nil` for a continuous slider.
    var step: Double?

    @Environment(\.mobileSliderAdjustment) private var adjustment
    @Environment(\.isEnabled) private var isEnabled
    @MenuFocusState private var focused: Bool
    @State private var id = UUID()

    /// Creates a slider row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - valueText: The current value, as shown.
    ///   - value: The value.
    ///   - range: The values the slider covers.
    ///   - step: The step between values, or `nil` for a continuous slider.
    init(
        title: LocalizedStringResource,
        valueText: LocalizedStringResource,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil
    ) {
        self.init(title: title, valueText: Text(valueText), value: value, range: range, step: step)
    }

    /// Creates a slider row whose current value is shown as it is, such as a formatted number.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - verbatimValue: The current value, shown without localization.
    ///   - value: The value.
    ///   - range: The values the slider covers.
    ///   - step: The step between values, or `nil` for a continuous slider.
    init(
        title: LocalizedStringResource,
        verbatimValue: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil
    ) {
        self.init(
            title: title,
            valueText: Text(verbatim: verbatimValue),
            value: value,
            range: range,
            step: step
        )
    }

    private init(
        title: LocalizedStringResource,
        valueText: Text,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double?
    ) {
        self.title = title
        self.valueText = valueText
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                valueText
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
            if focused, adjustment != nil {
                SliderAdjustmentPrompt(adjusting: adjusting)
            }
        }
        .tint(Palette.accent)
        .mobileRowPadding()
        .contentShape(.rect)
        .interactiveGrowth()
        .focusWithoutGrowth()
        .menuFocusable(isEnabled && adjustment != nil)
        .menuFocusBinding($focused)
        .environment(\.menuItemFocused, focused)
        .focusHighlightShape(MobileRowFocus.shape)
        .focusEffectDisabled()
        .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            guard isEnabled, let adjustment else {
                return .ignored
            }
            adjustment.confirm(id, value: $value)
            return .handled
        }
        .onMenuKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            guard adjusting else {
                return .ignored
            }
            nudge(
                press.key == .leftArrow
                    ? -1
                    : 1
            )
            return .handled
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused, adjusting {
                adjustment?.leave()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var adjusting: Bool {
        adjustment?.isAdjusting(id) ?? false
    }

    private func nudge(_ steps: Double) {
        let increment = step ?? (range.upperBound - range.lowerBound) / 20
        value = min(range.upperBound, max(range.lowerBound, value + steps * increment))
    }
}

/// Which phone settings slider the controller is adjusting, shared by the sliders and the screen that hosts them
/// so Back and Up or Down can end an adjustment.
///
/// Confirm on a slider starts adjusting it and Confirm again keeps the new value; Back restores the value from
/// when adjusting started.
@MainActor
@Observable
final class MobileSliderAdjustment {
    private var state = SliderAdjustment<UUID, Double>.navigating
    @ObservationIgnored private var restore: ((Double) -> Void)?

    /// Whether any slider is being adjusted.
    var isAdjusting: Bool {
        state.adjustingSlider != nil
    }

    /// Whether one slider is being adjusted.
    ///
    /// - Parameter slider: The slider's identity.
    /// - Returns: `true` while that slider is being adjusted.
    func isAdjusting(_ slider: UUID) -> Bool {
        state.isAdjusting(slider)
    }

    /// Starts adjusting a slider, or keeps its new value when it is already being adjusted.
    ///
    /// - Parameters:
    ///   - slider: The slider's identity.
    ///   - value: The slider's value, which Back restores.
    func confirm(_ slider: UUID, value: Binding<Double>) {
        state.confirm(slider, current: value.wrappedValue)
        restore = state.isAdjusting(slider)
            ? { value.wrappedValue = $0 }
            : nil
    }

    /// Keeps the adjusted value and stops adjusting.
    func leave() {
        state.leave()
        restore = nil
    }

    /// Restores the value from when adjusting started and stops adjusting.
    ///
    /// - Returns: Whether a slider was being adjusted.
    func cancel() -> Bool {
        guard case .adjusting(_, let original) = state else {
            return false
        }
        restore?(original)
        leave()
        return true
    }
}

extension EnvironmentValues {
    /// The controller adjustment shared by the phone settings sliders, or `nil` where no screen drives them with
    /// a controller.
    @Entry var mobileSliderAdjustment: MobileSliderAdjustment?
}

/// Makes a whole phone settings row one controller focus stop: Confirm runs the row's action and the outline
/// hugs the row.
struct MobileRowFocus: ViewModifier {
    /// The outline of a focused row.
    static let shape = FocusHighlightShape.roundedRectangle(16)

    /// What Confirm does.
    let activate: () -> Void

    /// The row with the controller focus behaviour applied.
    ///
    /// - Parameter content: The row.
    /// - Returns: The row as a focus stop.
    func body(content: Content) -> some View {
        content
            .interactiveGrowth()
            .focusWithoutGrowth()
            .modifier(MenuButtonFocus(activate: activate))
            .focusHighlightShape(Self.shape)
    }
}

/// A row's title, with an optional smaller line under it.
struct MobileRowTitle: View {
    /// The title.
    let title: Text

    /// A line under the title.
    var detail: Text?

    /// Creates a row title.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    init(title: LocalizedStringResource, detail: LocalizedStringResource? = nil) {
        self.title = Text(title)
        self.detail = detail.map { Text($0) }
    }

    /// Creates a row title from text already built, such as a name shown verbatim.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    init(title: Text, detail: Text?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
            if let detail {
                detail
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Pads a settings row to the touch row height and inset.
    ///
    /// - Returns: The padded row.
    func mobileRowPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
    }

    /// Makes a settings row one controller focus stop.
    ///
    /// - Parameter activate: What Confirm does.
    /// - Returns: The row with ``MobileRowFocus`` applied.
    func mobileRowFocus(activate: @escaping () -> Void) -> some View {
        modifier(MobileRowFocus(activate: activate))
    }
}
