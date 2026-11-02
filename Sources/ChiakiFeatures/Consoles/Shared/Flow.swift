import DesignSystem
import MenuFocus
import SwiftUI

/// The prominent button of a sign-in or console screen, with a symbol after its label.
public struct FlowPrimaryButton<Focus: Hashable>: View {
    /// The text shown on the button.
    let label: String
    /// The SF Symbol name shown after the label.
    let symbol: String
    /// The focus stop this button occupies in the screen's focus.
    let focus: Focus
    /// The screen's controller focus that the button joins at `focus`.
    let focusedAction: MenuFocusState<Focus?>.Binding
    /// The action run when the button is pressed.
    let perform: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - label: The button's text.
    ///   - symbol: The SF Symbol shown with the label.
    ///   - focus: The focus stop the button is.
    ///   - focusedAction: The screen's focus.
    ///   - perform: What the button does.
    public init(
        label: String,
        symbol: String,
        focus: Focus,
        focusedAction: MenuFocusState<Focus?>.Binding,
        perform: @escaping () -> Void
    ) {
        self.label = label
        self.symbol = symbol
        self.focus = focus
        self.focusedAction = focusedAction
        self.perform = perform
    }

    /// The button.
    public var body: some View {
        FocusButton(action: perform) {
            Label(label, systemImage: symbol)
                .frame(width: 220)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
        }
        .glassProminentControlStyle()
        .tint(Palette.accent)
        .menuFocused(focusedAction, equals: focus)
        .foregroundStyle(Color(red: 0.086, green: 0.176, blue: 0.314))
        .controlSize(.large)
        .padding(.vertical, 4)
    }
}

/// The quiet text button under a sign-in or console screen, such as Back or Cancel.
public struct FlowSecondaryButton<Focus: Hashable>: View {
    /// The text shown on the button.
    let label: String
    /// The focus stop this button occupies in the screen's focus.
    let focus: Focus
    /// The screen's controller focus that the button joins at `focus`.
    let focusedAction: MenuFocusState<Focus?>.Binding
    /// The action run when the button is pressed.
    let perform: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - label: The button's text.
    ///   - focus: The focus stop the button is.
    ///   - focusedAction: The screen's focus.
    ///   - perform: What the button does.
    public init(
        label: String,
        focus: Focus,
        focusedAction: MenuFocusState<Focus?>.Binding,
        perform: @escaping () -> Void
    ) {
        self.label = label
        self.focus = focus
        self.focusedAction = focusedAction
        self.perform = perform
    }

    @Environment(\.screenLayout) private var layout

    /// The button.
    public var body: some View {
        FocusButton(action: perform) {
            Text(label)
                .padding(.horizontal, 12)
                .frame(minWidth: layout.controlSize, minHeight: layout.controlSize)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.capsule)
        .foregroundStyle(.secondary)
        .menuFocused(focusedAction, equals: focus)
        .padding(
            .top,
            layout.touch
                ? 6
                : 20
        )
    }
}

/// The headline and detail line at the top of a sign-in or console screen.
public struct FlowTitle: View {
    /// The headline.
    let text: String

    /// The line under the headline.
    let detail: String

    /// Creates the title.
    ///
    /// - Parameters:
    ///   - text: The headline.
    ///   - detail: The line under the headline.
    public init(text: String, detail: String) {
        self.text = text
        self.detail = detail
    }

    @Environment(\.screenLayout) private var layout

    /// The view.
    public var body: some View {
        VStack(spacing: 10) {
            Text(text).font(.system(size: 28, weight: .medium)).tracking(-0.7)
            Text(detail).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(
            .bottom,
            layout.isShort
                ? 12
                : 26
        )
    }
}

/// One choice on a ``FlowTileRow``: a square tile with a symbol over a short label, and the line the row
/// explains it with while it is hovered or focused.
public struct FlowTileChoice<Focus: Hashable> {
    /// The text under the symbol.
    let label: String
    /// The SF Symbol name drawn on the tile.
    let symbol: String
    /// The line shown under the row while the tile is hovered or focused.
    let hint: String
    /// The focus stop this tile occupies in the screen's focus.
    let focus: Focus
    /// Whether the tile is filled with the accent as the screen's main choice.
    let prominent: Bool
    /// Whether the tile can be pressed; a disabled tile is dimmed and takes no focus.
    let enabled: Bool
    /// Whether Escape or the controller's back button presses the tile.
    let cancels: Bool
    /// The action run when the tile is pressed.
    let perform: () -> Void

    /// Creates a choice.
    ///
    /// - Parameters:
    ///   - label: The text under the symbol.
    ///   - symbol: The SF Symbol drawn on the tile.
    ///   - hint: The line shown while the tile is hovered or focused.
    ///   - focus: The focus stop the tile is.
    ///   - prominent: Whether the tile is the screen's main choice, filled with the accent.
    ///   - enabled: Whether the tile can be pressed; by default it can.
    ///   - cancels: Whether Escape presses the tile.
    ///   - perform: What the tile does.
    public init(
        label: String,
        symbol: String,
        hint: String,
        focus: Focus,
        prominent: Bool = false,
        enabled: Bool = true,
        cancels: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.label = label
        self.symbol = symbol
        self.hint = hint
        self.focus = focus
        self.prominent = prominent
        self.enabled = enabled
        self.cancels = cancels
        self.perform = perform
    }
}

/// A row of square tiles that a sign-in or console screen offers its choices on, with one line under the row
/// explaining whichever tile the pointer is over or controller focus rests on.
///
/// Left and Right walk the tiles under a controller, which ``EntryFocusGraph`` maps onto the screen's stop
/// order, so Up and Down keep working too.
public struct FlowTileRow<Focus: Hashable>: View {
    /// The side of a tile on a regular screen.
    public static var side: CGFloat {
        108
    }

    /// The side of a tile on a compact screen.
    public static var compactSide: CGFloat {
        92
    }

    /// The tiles, left to right.
    let choices: [FlowTileChoice<Focus>]
    /// The screen's controller focus that every tile joins at its own stop.
    let focusedAction: MenuFocusState<Focus?>.Binding
    @State private var hovered: Focus?
    @Environment(\.screenLayout) private var layout

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - choices: The tiles, left to right.
    ///   - focusedAction: The screen's focus.
    public init(_ choices: [FlowTileChoice<Focus>], focusedAction: MenuFocusState<Focus?>.Binding) {
        self.choices = choices
        self.focusedAction = focusedAction
    }

    /// The row and its hint line.
    public var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: layout.isCompact
                ? 10
                : 14) {
                    ForEach(choices, id: \.focus) { choice in
                        tile(choice)
                    }
                }
            Text(explained?.hint ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, minHeight: 44, alignment: .top)
                .animation(.easeOut(duration: 0.15), value: explained?.focus)
                .accessibilityHidden(true)
        }
        .padding(.top, 6)
    }

    private var explained: FlowTileChoice<Focus>? {
        let current = layout.hoverAffordances
            ? hovered ?? focusedAction.wrappedValue
            : focusedAction.wrappedValue
        return choices.first { $0.focus == current }
    }

    private var side: CGFloat {
        layout.isCompact
            ? Self.compactSide
            : Self.side
    }

    private func tile(_ choice: FlowTileChoice<Focus>) -> some View {
        let radius = GlassPanel.Radius.medium
        return FocusButton(action: choice.perform) {
            VStack(spacing: 10) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 28, weight: .medium))
                Text(choice.label)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .frame(width: side, height: side)
            .foregroundStyle(choice.prominent
                ? Self.onAccent
                : Color.primary)
                .background {
                    if choice.prominent {
                        radius.shape.fill(Palette.accent)
                    }
                }
                .glassEffect(
                    choice.prominent
                        ? AppGlass.control
                        : AppGlass.panel,
                    in: .rect(cornerRadius: radius.points)
                )
                .contentShape(.rect(cornerRadius: radius.points))
        }
        .buttonStyle(.plain)
        .disabled(!choice.enabled)
        .opacity(choice.enabled
            ? 1
            : 0.4)
            .focusHighlightShape(.roundedRectangle(radius.points))
            .menuFocused(focusedAction, equals: choice.focus)
            .onHover { hovering in
                if hovering {
                    hovered = choice.focus
                } else if hovered == choice.focus {
                    hovered = nil
                }
            }
            .keyboardShortcut(choice.cancels
                ? .cancelAction
                : nil)
                .accessibilityLabel(choice.label)
                .accessibilityHint(choice.hint)
    }

    private static var onAccent: Color {
        Color(red: 0.086, green: 0.176, blue: 0.314)
    }
}
