import DesignSystem
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
    var title: String?

    /// The explanation below the group.
    var footer: String?

    /// The rows.
    @ViewBuilder let content: Content

    /// Creates a group.
    ///
    /// - Parameters:
    ///   - title: The title above the group.
    ///   - footer: The explanation below the group.
    ///   - content: The rows.
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
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
    let title: String

    /// A line under the title.
    var detail: String?

    /// The setting.
    @Binding var isOn: Bool

    /// Creates a switch row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    ///   - isOn: The setting.
    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
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
    }
}

/// A settings row choosing one value from a menu, showing the current value at its trailing edge.
struct MobilePickerRow<Value: Hashable, Options: View>: View {
    /// The title.
    let title: String

    /// A line under the title.
    var detail: String?

    /// The chosen value.
    @Binding var selection: Value

    /// The menu's options, each tagged with its value.
    @ViewBuilder let options: Options

    /// Creates a menu row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: A line under the title.
    ///   - selection: The chosen value.
    ///   - options: The menu's options, each tagged with its value.
    init(
        _ title: String,
        detail: String? = nil,
        selection: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.detail = detail
        _selection = selection
        self.options = options()
    }

    var body: some View {
        HStack(spacing: 12) {
            MobileRowTitle(title: title, detail: detail)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                options
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.secondary)
        }
        .mobileRowPadding()
    }
}

/// A settings row showing a value, optionally opening something when tapped.
struct MobileValueRow: View {
    /// The title.
    let title: String

    /// The value at the trailing edge.
    var value: String?

    /// What a tap does, or `nil` for a plain row.
    var action: (() -> Void)?

    /// Creates a value row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - value: The value at the trailing edge.
    ///   - action: What a tap does, or `nil` for a plain row.
    init(_ title: String, value: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                content(chevron: true)
            }
            .buttonStyle(.plain)
        } else {
            content(chevron: false)
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value)
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
    let title: String

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
    init(_ title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
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
    }
}

/// A settings row with a slider under its title and current value.
struct MobileSliderRow: View {
    /// The title.
    let title: String

    /// The current value, as shown.
    let valueText: String

    /// The value.
    @Binding var value: Double

    /// The values the slider covers.
    let range: ClosedRange<Double>

    /// The step between values, or `nil` for a continuous slider.
    var step: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .tint(Palette.accent)
        .mobileRowPadding()
    }
}

/// A row's title, with an optional smaller line under it.
struct MobileRowTitle: View {
    /// The title.
    let title: String

    /// A line under the title.
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
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
}
