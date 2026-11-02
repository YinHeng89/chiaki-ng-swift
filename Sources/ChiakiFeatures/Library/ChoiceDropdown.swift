import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// One glass button naming a choice in effect, which opens the choices as a menu: the compact screens' stand-in
/// for a row of chips, shared by the trophies and cloud sections.
///
/// A tap opens the SwiftUI menu. With a controller the button is one focus stop, whose stop follows the choice
/// in effect, and Confirm opens the same choices as a native menu anchored to the button; choosing or dismissing
/// returns focus to the button.
struct ChoiceDropdown<Choice: Hashable, Stop: Hashable>: View {
    /// What the choices decide, read by VoiceOver and shown before the choice unless ``titleShown`` is off.
    let title: String
    /// The choices, in order.
    let choices: [Choice]
    /// The choice in effect.
    let chosen: Choice
    /// A choice's label.
    let label: (Choice) -> String
    /// A choice's focus stop.
    let stop: (Choice) -> Stop
    /// The section's focus.
    let focus: MenuFocusState<Stop?>.Binding
    /// Moves focus from a stop.
    let move: (Stop, MenuMoveDirection) -> Void
    /// Whether the title is shown before the choice; off where the choice names itself, such as a platform.
    var titleShown = true
    /// The direction of the order in effect, for a choice of sorts, shown beside the chosen sort; `nil` for a
    /// choice of filters.
    var direction: TrophySortDirection?
    /// Makes a choice.
    let choose: (Choice) -> Void
    @State private var menuAnchor = NativeMenuAnchorReference()
    @Environment(\.screenLayout) private var layout

    private var focused: Bool {
        focus.wrappedValue == stop(chosen)
    }

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                SwiftUI.Button {
                    pick(choice)
                } label: {
                    if choice == chosen {
                        Label(label(choice), systemImage: "checkmark")
                    } else {
                        Text(label(choice))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if titleShown {
                    Text(title)
                        .foregroundStyle(.white)
                }
                HStack(spacing: 3) {
                    Text(label(chosen))
                    if let direction {
                        Image(systemName: direction == .reversed
                            ? "arrow.up"
                            : "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityLabel(direction == .reversed
                                ? "reversed"
                                : "")
                    }
                }
                .foregroundStyle(Palette.accent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: layout.controlSize)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .focusable(false)
        .glassEffect(AppGlass.control, in: .capsule)
        .nativeMenuAnchor(menuAnchor)
        .menuFocusable()
        .menuFocusBinding(focus, equals: stop(chosen))
        .focusEffectDisabled()
        .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            present()
            return .handled
        }
        .onMenuKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
            guard let direction = MenuMoveDirection(press.key) else {
                return .ignored
            }
            move(stop(chosen), direction)
            return .handled
        }
        .interactiveGrowth()
        .environment(\.menuItemFocused, focused)
        .environment(\.focusHighlightStyleShape, .capsule)
        .accessibilityLabel(title)
        .accessibilityValue(label(chosen))
        .accessibilityHint("Opens the choices")
    }

    private func pick(_ choice: Choice) {
        choose(choice)
        focus.wrappedValue = stop(choice)
    }

    private func present() {
        menuAnchor
            .presentMenu(titles: choices.map(label), selected: choices.firstIndex(of: chosen)) { index in
                guard choices.indices.contains(index) else {
                    return
                }
                pick(choices[index])
            }
        focus.wrappedValue = stop(chosen)
    }
}
