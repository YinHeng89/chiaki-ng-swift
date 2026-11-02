import DesignSystem
import PlatformUI
import SwiftUI

/// A segmented choice whose segments are controller focus stops.
///
/// Left and right move between segments, confirm selects the focused one, and up and down leave the control
/// through ``SwiftUICore/EnvironmentValues/menuMove`` or the nearest control in that direction. After a
/// selection, focus follows the selected segment. On touch the capsule grows to the screen layout's `controlSize`.
public struct FocusableSegments<Value: Hashable>: View {
    private let options: [Value]
    private let title: (Value) -> String
    @Binding private var selection: Value
    private let externalFocus: MenuFocusState<Value?>.Binding?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuMove) private var menuMove
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.screenLayout) private var layout
    @MenuFocusState private var internalFocus: Value?
    @State private var hostWindow: PlatformWindow?

    /// Creates the control.
    ///
    /// - Parameters:
    ///   - options: The choices, in order.
    ///   - title: The label of a choice.
    ///   - selection: The selected choice.
    ///   - focus: A focus state to bind the segments to, so the owner can move focus into the control.
    public init(
        options: [Value],
        title: @escaping (Value) -> String,
        selection: Binding<Value>,
        focus: MenuFocusState<Value?>.Binding? = nil
    ) {
        self.options = options
        self.title = title
        _selection = selection
        externalFocus = focus
    }

    private var focusBinding: MenuFocusState<Value?>.Binding {
        externalFocus ?? $internalFocus
    }

    private var focusedOption: Value? {
        get {
            focusBinding.wrappedValue
        }
        nonmutating set {
            focusBinding.wrappedValue = newValue
        }
    }

    /// The segments in a glass capsule.
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(4)
        .glassEffect(AppGlass.control, in: .capsule)
        .background(WindowAccessor { hostWindow = $0 })
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: 0.15),
            value: selection
        )
        .onChange(of: selection) { _, option in
            focusedOption = nil
            DispatchQueue.main.async {
                if selection == option {
                    #if os(macOS)
                        hostWindow?.recalculateKeyViewLoop()
                    #endif
                    focusedOption = option
                }
            }
        }
    }

    private func segment(_ option: Value) -> some View {
        Button {
            selection = option
        } label: {
            Text(title(option))
                .font(.callout.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .frame(minHeight: segmentHeight)
                .background(fill(for: option), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .menuFocusable()
        .focusEffectDisabled()
        .interactiveGrowth()
        .focusHighlightShape(.capsule)
        .focusWithoutGrowth()
        .menuFocused(focusBinding, equals: option)
        .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            selection = option
            return .handled
        }
        .onMenuKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
            guard let direction = MenuMoveDirection(press.key) else {
                return .ignored
            }
            move(from: option, direction: direction)
            return .handled
        }
        .accessibilityAddTraits(
            selection == option
                ? .isSelected
                : []
        )
    }

    private var segmentHeight: CGFloat {
        max(0, layout.controlSize - 8)
    }

    private func fill(for option: Value) -> Color {
        if selection == option {
            return Color.primary.opacity(0.14)
        }
        return .clear
    }

    private func move(from option: Value, direction: MenuMoveDirection) {
        if direction.isVertical {
            if let menuMove {
                menuMove(direction)
            } else if let window = hostWindow {
                navigator?.moveGeometric(direction, in: window, allowUnaligned: true)
            }
            return
        }
        guard let index = options.firstIndex(of: option) else {
            return
        }
        let next = index + (direction == .left
            ? -1
            : 1)
        if options.indices.contains(next) {
            focusedOption = options[next]
        }
    }
}
