import ChiakiModels
import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

/// Sizes and spacing shared by the compact library bar and its rows.
enum CompactLibraryBarMetrics {
    /// The edge length of a round bar control.
    static let control: CGFloat = 44
    /// The spacing between items in the bar.
    static let spacing: CGFloat = 12
    /// The vertical padding above and below the bar.
    static let inset: CGFloat = 6
    /// The gap between tiles in a compact recently played rail.
    static let gap: CGFloat = 16
}

/// The thin outline drawn around compact tiles and controls.
enum CompactRim {
    /// The outline's line width.
    static let width: CGFloat = 1

    /// The outline's colour, a faint tint of the primary colour.
    static var color: Color {
        Color.primary.opacity(0.26)
    }
}

/// The layout value that tells ``CompactBarLayout`` which slot a bar item occupies.
enum CompactBarRole: LayoutValueKey {
    /// The slot a bar item occupies.
    enum Role {
        /// Packed from the leading edge.
        case leading
        /// Centred in the bar and squeezed first when space runs out.
        case sections
        /// Packed from the trailing edge.
        case trailing
    }

    /// Items default to the leading slot.
    static let defaultValue = Role.leading
}

/// Lays out the compact bar: leading items from the left, trailing items from the right, and the sections
/// centred between them.
///
/// When the items do not fit, the sections shrink toward their smallest size before anything else does.
struct CompactBarLayout: Layout {
    /// The slot and width chosen for one bar item.
    struct Item {
        /// The slot the item occupies.
        let role: CompactBarRole.Role
        /// The width the item is given.
        var width: CGFloat
    }

    /// The spacing between neighbouring items.
    var spacing = CompactLibraryBarMetrics.spacing

    /// Reports the tallest item's height and the proposed width, or the natural width of all items when none
    /// is proposed.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let height = subviews.map { subview in
            subview.sizeThatFits(.unspecified).height
        }.max() ?? 0
        let natural = subviews.reduce(0) { total, subview in
            total + subview.sizeThatFits(.unspecified).width
        } + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    /// Places leading items from the left edge, trailing items from the right edge, and the sections centred
    /// but clamped between them.
    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let items = fitted(subviews, in: bounds.width)
        var leading = bounds.minX
        var trailing = bounds.maxX
        for (subview, item) in zip(subviews, items) where item.role == .leading {
            place(subview, width: item.width, at: leading, anchor: .leading, in: bounds)
            leading += item.width + spacing
        }
        for (subview, item) in zip(subviews, items).reversed() where item.role == .trailing {
            place(subview, width: item.width, at: trailing, anchor: .trailing, in: bounds)
            trailing -= item.width + spacing
        }
        for (subview, item) in zip(subviews, items) where item.role == .sections {
            let centred = bounds.midX - item.width / 2
            let latest = max(leading, trailing - item.width)
            place(
                subview,
                width: item.width,
                at: min(max(centred, leading), latest),
                anchor: .leading,
                in: bounds
            )
        }
    }

    private func place(
        _ subview: LayoutSubview, width: CGFloat, at x: CGFloat, anchor: UnitPoint, in bounds: CGRect
    ) {
        subview.place(
            at: CGPoint(x: x, y: bounds.midY),
            anchor: anchor,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }

    /// Chooses each item's slot and width, shrinking the sections when the natural widths overflow the
    /// available width.
    ///
    /// - Parameters:
    /// - subviews: The bar items.
    /// - width: The width available to the bar.
    /// - Returns: One entry per subview, in order.
    func fitted(_ subviews: Subviews, in width: CGFloat) -> [Item] {
        var items = subviews.map { subview in
            Item(role: subview[CompactBarRole.self], width: subview.sizeThatFits(.unspecified).width)
        }
        let taken = items.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, items.count - 1))
        guard taken > width else {
            return items
        }
        for (index, subview) in subviews.enumerated() where items[index].role == .sections {
            let squeezed = subview.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
            items[index].width = min(items[index].width, max(squeezed, items[index].width - (taken - width)))
        }
        return items
    }
}

/// The compact library bar: leading controls, centred section tabs, then the account and settings controls on
/// the right.
///
/// While the account controls are expanded, the leading and section items fade out and stop taking input to
/// make room.
struct CompactLibraryBar<Leading: View, Sections: View, Account: View, Settings: View>: View {
    /// Which part of the bar has the room.
    enum Showing {
        /// The navigation items are visible.
        case navigation
        /// The account actions are expanded over the navigation items.
        case accountActions
    }

    /// Extra trailing padding kept free for window controls drawn over the bar.
    let trailingReserve: CGFloat
    /// The controls at the leading edge.
    @ViewBuilder let leading: Leading
    /// The section tabs centred in the bar.
    @ViewBuilder let sections: Sections
    /// The account control on the trailing side.
    @ViewBuilder let account: Account
    /// The settings control at the trailing edge.
    @ViewBuilder let settings: Settings
    @State private var showing = Showing.navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CompactBarLayout {
            Group {
                leading
            }
            .modifier(Yielding(yields: showing == .accountActions))
            .layoutValue(key: CompactBarRole.self, value: .leading)
            sections
                .modifier(Yielding(yields: showing == .accountActions))
                .layoutValue(key: CompactBarRole.self, value: .sections)
            account
                .layoutValue(key: CompactBarRole.self, value: .trailing)
            settings
                .layoutValue(key: CompactBarRole.self, value: .trailing)
        }
        .frame(height: CompactLibraryBarMetrics.control)
        .padding(.vertical, CompactLibraryBarMetrics.inset)
        .frame(maxWidth: .infinity)
        .padding(.trailing, trailingReserve)
        .onPreferenceChange(AccountControlsExpansion.self) { expanded in
            MainActor.assumeIsolated {
                showing = expanded
                    ? .accountActions
                    : .navigation
            }
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: showing)
    }

    private struct Yielding: ViewModifier {
        let yields: Bool

        func body(content: Content) -> some View {
            content
                .opacity(
                    yields
                        ? 0
                        : 1
                )
                .allowsHitTesting(!yields)
                .accessibilityHidden(yields)
        }
    }
}

/// A round settings button for the compact bar that opens settings in its own window.
///
/// It takes controller focus when the window asks for the settings control, unless input is blocked.
struct CompactSettingsButton: View {
    /// The menu navigator that sends the settings command and owns the input gate.
    @Environment(\.menuNavigator) var navigator
    /// Moves controller focus to the left of the button.
    let moveLeft: () -> Void
    /// Moves controller focus below the button.
    let moveDown: () -> Void
    @MenuFocusState private var focused: Bool
    @State private var hostWindow: PlatformWindow?
    @Environment(\.topControlsLayout) private var topControlsLayout

    var body: some View {
        FocusButton {
            navigator?.endEditing()
            navigator?.commands.send(.settings, to: hostWindow ?? WindowFocus.keyWindow)
        } label: {
            AppIcon.settings.image
                .font(.system(size: 17, weight: .medium))
                .frame(width: CompactLibraryBarMetrics.control, height: CompactLibraryBarMetrics.control)
                .glassEffect(AppGlass.control, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.circle)
        .focusWithoutGrowth()
        .menuFocused($focused)
        .environment(\.menuMove) { direction in
            switch direction {
            case .left:
                moveLeft()
            case .down:
                moveDown()
            default:
                break
            }
        }
        .accessibilityLabel(.commonSettings)
        .background(WindowAccessor { hostWindow = $0 })
        .onReceive(NotificationCenter.default.publisher(for: .focusSettingsControl)) { notification in
            guard let window = notification.object as? PlatformWindow, window === hostWindow,
                  !(navigator?.inputGate.isBlocking ?? false) else {
                return
            }
            focused = true
        }
    }
}
