import DesignSystem
import MenuFocus
import SwiftUI

/// One labelled control in a ``SettingsCard``: the title and optional detail on the leading side, the control
/// in a trailing column at least ``controlColumnWidth`` wide.
///
/// When the title and the control do not fit side by side, the control stacks under the label at full width.
/// On touch the control is at least the screen layout's `controlSize` tall.
public struct SettingsRow<Content: View>: View {
    /// The width of the trailing control column.
    public static var controlColumnWidth: CGFloat {
        184
    }

    @Environment(\.screenLayout) private var layout
    private let title: Text
    private let detail: LocalizedStringResource?
    private let content: Content

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - title: What the control sets.
    ///   - detail: A short explanation under the title, if any.
    ///   - content: The control.
    public init(
        _ title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        self.detail = detail
        self.content = content()
    }

    /// Creates a row whose title is data shown as it is, such as a console's name.
    ///
    /// - Parameters:
    ///   - title: What the control sets.
    ///   - detail: A short explanation under the title, if any.
    ///   - content: The control.
    public init(
        verbatim title: String,
        detail: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(verbatim: title)
        self.detail = detail
        self.content = content()
    }

    /// The row.
    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                label(singleLineTitle: true)
                Spacer(minLength: 8)
                control
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: Self.controlColumnWidth, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                label(singleLineTitle: false)
                control
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: max(26, layout.controlSize))
        .controlSize(
            layout.touch
                ? .large
                : .regular
        )
    }

    private func label(singleLineTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.callout)
                .lineLimit(
                    singleLineTitle
                        ? 1
                        : nil
                )
                .fixedSize(horizontal: singleLineTitle, vertical: false)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(idealWidth: 0, alignment: .leading)
            }
        }
    }

    private var control: some View {
        content
            .labelsHidden()
            .nativeFocusHighlight()
            .frame(minHeight: layout.controlSize)
            .tint(.primary)
    }
}
