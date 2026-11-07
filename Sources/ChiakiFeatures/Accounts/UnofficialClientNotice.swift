import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// The orange glass notice that chiaki-ng is an unofficial client, shown before a PlayStation sign-in and on
/// the About settings page, with room under its text for an acknowledgement and a row of actions centred
/// across the whole card.
public struct UnofficialClientNotice<Footer: View, Actions: View>: View {
    /// The notice's headline.
    public static var title: LocalizedStringResource {
        .accountsUnofficialTitle
    }

    /// The notice's explanation.
    public static var text: LocalizedStringResource {
        .accountsUnofficialText
    }

    private let footer: Footer
    private let actions: Actions

    /// Creates the notice with something under its text and a row of actions under the whole card.
    ///
    /// - Parameters:
    ///   - footer: What sits under the text, such as an acknowledgement.
    ///   - actions: The buttons centred across the card under everything else.
    public init(@ViewBuilder footer: () -> Footer, @ViewBuilder actions: () -> Actions) {
        self.footer = footer()
        self.actions = actions()
    }

    /// The notice.
    public var body: some View {
        VStack(spacing: 14) {
            message
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(AppGlass.warning, in: .rect(cornerRadius: GlassPanel.Radius.medium.points))
        .overlay {
            GlassPanel.Radius.medium.shape.strokeBorder(Color.orange.opacity(0.4))
        }
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.title)
                    .font(.headline)
                Text(AttributedString(localized: Self.text))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                footer
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension UnofficialClientNotice where Actions == EmptyView {
    /// Creates the notice with something under its text and no actions.
    ///
    /// - Parameter footer: What sits under the text, such as an acknowledgement.
    public init(@ViewBuilder footer: () -> Footer) {
        self.init(footer: footer) {
            EmptyView()
        }
    }
}

extension UnofficialClientNotice where Footer == EmptyView, Actions == EmptyView {
    /// Creates the notice with nothing under its text.
    public init() {
        self.init(footer: {
            EmptyView()
        })
    }
}

/// The checkbox under the unofficial-client notice that a PlayStation sign-in needs ticked before its code is
/// shown or its page opens.
///
/// It joins the sign-in screen's controller focus at the `acknowledgeUnofficial` entry stop.
public struct UnofficialClientAcknowledgement: View {
    private let acknowledged: Bool
    private let focusedInput: MenuFocusState<EntryFocus?>.Binding
    private let toggle: () -> Void

    /// Creates the acknowledgement.
    ///
    /// - Parameters:
    ///   - acknowledged: Whether the box is ticked.
    ///   - focusedInput: The sign-in screen's focus.
    ///   - toggle: Ticks or clears the box.
    public init(
        acknowledged: Bool,
        focusedInput: MenuFocusState<EntryFocus?>.Binding,
        toggle: @escaping () -> Void
    ) {
        self.acknowledged = acknowledged
        self.focusedInput = focusedInput
        self.toggle = toggle
    }

    /// The box and its label as one button.
    public var body: some View {
        FocusButton(action: toggle) {
            HStack(spacing: 9) {
                box
                Text(.accountsUnofficialAcknowledge)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(8))
        .menuFocused(focusedInput, equals: .acknowledgeUnofficial)
        .accessibilityValue(acknowledged
            ? LocalizedStringResource.accountsUnofficialChecked
            : .accountsUnofficialUnchecked)
            .accessibilityHint(.accountsUnofficialAcknowledgeHint)
    }

    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(acknowledged
                    ? Palette.accent
                    : Color.black.opacity(0.25))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(acknowledged
                    ? Color.clear
                    : Color.orange.opacity(0.7), lineWidth: 1.5)
            if acknowledged {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 20, height: 20)
        .animation(.easeOut(duration: 0.15), value: acknowledged)
    }
}
