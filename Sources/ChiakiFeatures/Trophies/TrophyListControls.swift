import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// A row of choices on one glass capsule, the chosen one highlighted, each choice a focus stop.
///
/// Left and Right move along the row through the given move closure, which also hands focus to the next control
/// at either end; Confirm chooses the focused choice.
struct TrophyChoiceChips<Choice: Hashable, Stop: Hashable>: View {
    /// What the choices decide, read by VoiceOver.
    let title: LocalizedStringResource
    /// The choices, in order.
    let choices: [Choice]
    /// The choice in effect.
    let chosen: Choice
    /// A choice's label.
    let label: (Choice) -> LocalizedStringResource
    /// A choice's focus stop.
    let stop: (Choice) -> Stop
    /// The section's focus.
    let focus: MenuFocusState<Stop?>.Binding
    /// Moves focus from a stop.
    let move: (Stop, MenuMoveDirection) -> Void
    /// The direction of the order in effect, for a row of sorts, shown on the chosen chip; `nil` for a row of
    /// filters.
    var direction: TrophySortDirection?
    /// Makes a choice.
    let choose: (Choice) -> Void
    @Environment(\.screenLayout) private var layout

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.self) { choice in
                chip(choice)
            }
        }
        .padding(4)
        .glassEffect(AppGlass.control, in: .capsule)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func chip(_ choice: Choice) -> some View {
        let selected = choice == chosen
        let target = stop(choice)
        return FocusButton {
            choose(choice)
        } label: {
            HStack(spacing: 4) {
                Text(label(choice))
                if selected, let direction {
                    Image(systemName: direction == .reversed
                        ? "arrow.up"
                        : "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityLabel(direction == .reversed
                            ? Text(.trophiesArrangementReversed)
                            : Text(verbatim: ""))
                }
            }
            .font(.system(
                size: 15,
                weight: selected
                    ? .semibold
                    : .regular
            ))
            .foregroundStyle(
                selected
                    ? Palette.accent
                    : .white
            )
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(minHeight: max(0, layout.controlSize - 8))
            .background(
                selected
                    ? Palette.accent.opacity(0.22)
                    : .clear,
                in: .capsule
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.capsule)
        .menuFocused(focus, equals: target)
        .environment(\.menuMove) { direction in
            move(target, direction)
        }
        .accessibilityAddTraits(selected
            ? .isSelected
            : [])
    }
}

/// A glass search field that takes typing, opens the on-screen keyboard on Confirm with a controller and hands Up
/// and Down to the section's focus moves.
struct TrophySearchField<Stop: Hashable>: View {
    /// The placeholder and the on-screen keyboard's title.
    let prompt: LocalizedStringResource
    /// The text searched for.
    let query: Binding<String>
    /// The section's focus.
    let focus: MenuFocusState<Stop?>.Binding
    /// The field's focus stop.
    let stop: Stop
    /// Moves focus from a stop.
    let move: (Stop, MenuMoveDirection) -> Void
    @Environment(\.screenLayout) private var layout

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: query)
                .textFieldStyle(.plain)
                .menuFocusBinding(focus, equals: stop)
                .controllerKeyboard(
                    title: prompt,
                    text: query,
                    isFocused: focus.wrappedValue == stop
                )
                .onMenuKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                    move(stop, press.key == .upArrow
                        ? .up
                        : .down)
                    return .handled
                }
        }
        .font(.system(size: 15, weight: .regular))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: layout.isCompact
            ? 180
            : 240)
            .frame(minHeight: layout.controlSize)
            .glassEffect(AppGlass.control, in: .capsule)
            .modifier(CloudSearchFocusRing(focused: focus.wrappedValue == stop))
    }
}
