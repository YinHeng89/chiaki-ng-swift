import ChiakiModels
import ComposableArchitecture
import CryptoKit
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The library bar's account pill: the selected profile with its cloud status, which expands into
/// icons to switch, add, refresh, sign in again and delete accounts, with hover and controller
/// tooltips and a popover account chooser.
struct AccountControls: View {
    /// The app's menu navigator, used to check whether a control still holds focus.
    @Environment(\.menuNavigator) var navigator
    /// Every saved profile, offered by the account chooser.
    let profiles: [RegistrationFlow.Profile]
    /// The active profile shown in the pill, or `nil` when there is none.
    let selected: RegistrationFlow.Profile?
    /// The short cloud status line under the profile name.
    let cloudText: LocalizedStringResource
    /// The longer cloud status explanation shown as the pill's tooltip.
    let cloudHelp: LocalizedStringResource
    /// The colour of the cloud status line.
    let cloudColor: Color
    /// Whether account details are refreshing, which disables the refresh icon.
    let isRefreshing: Bool
    /// Refreshes the account details.
    let refresh: () -> Void
    /// Sends a library request, such as selecting, adding or reconnecting an account.
    let send: (LibraryRequest) -> Void
    /// Deletes the profile with the given id.
    let delete: (UUID) -> Void
    /// The library's controller focus; the pill is its `profile` stop.
    @MenuFocusState.Binding var navigationFocus: ConsoleLibraryFocus?
    /// Moves focus down to the console row, nearest the given horizontal position.
    let moveToConsole: (CGFloat?) -> Void
    /// Moves focus left to the library tabs.
    let moveToLibraryTab: () -> Void
    /// Whether the system asks for reduced motion, which turns off the expand animation.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Whether the live log button is to the right, so moving right focuses it instead of settings.
    @Environment(\.liveLogButtonShown) var liveLogButtonShown
    /// Whether the pointer or a controller is driving the interface.
    @Environment(\.inputMode) var inputMode
    /// The room and pointing method of the screen, which size the actions and decide whether they show titles.
    @Environment(\.screenLayout) var layout
    /// Whether the pointer is over the controls.
    @State var hovering = false
    /// The id of the action icon under the pointer.
    @State var hoveredAction: String?
    /// The pointer's position inside the controls, which places the tooltip.
    @State var pointer: CGPoint?
    /// Whether the strip stays open after a click or controller press.
    @State var pinned = false
    /// The account chooser popover's window, once it is shown.
    @State var chooserWindow: PlatformWindow?
    /// Whether the account chooser popover is open.
    @State var choosingAccount = false
    /// The pill's horizontal centre in global coordinates, passed on when focus moves down.
    @State var profileCenterX: CGFloat?
    /// The id of the action icon holding controller focus.
    @MenuFocusState var focused: String?
    /// The account holding controller focus in the chooser.
    @MenuFocusState var focusedAccount: UUID?
    /// The focused action id while a controller drives the interface, otherwise `nil`.
    var shownFocus: String? {
        inputMode == .controller
            ? focused
            : nil
    }

    /// Whether the action strip is open: hovered, pinned, focused with a controller, or choosing.
    var expanded: Bool {
        hovering || pinned || inputMode.shows(focused != nil) || choosingAccount
    }

    /// Every focus target id from left to right, used to find a neighbour when one disappears.
    static let targetOrder = ["account", "switch", "add", "refresh", "signin", "delete"]

    /// The focus target ids available now, leaving out actions that are disabled.
    var focusTargets: [String] {
        var targets = ["account"]
        if profiles.count > 1 {
            targets.append("switch")
        }
        targets.append("add")
        if !isRefreshing {
            targets.append("refresh")
        }
        if selected != nil {
            targets += ["signin", "delete"]
        }
        return targets
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                icon(.accountsControlsSwitchAccount, .switchAccount, id: "switch") {
                    choosingAccount = true
                }
                .disabled(profiles.count < 2)
                .popover(isPresented: $choosingAccount) {
                    ScrollView(.horizontal) {
                        HStack(spacing: layout.controlSpacing) {
                            ForEach(profiles, id: \.id) { account in
                                FocusButton {
                                    send(.selectAccount(account.id))
                                    choosingAccount = false
                                } label: {
                                    VStack(spacing: 8) {
                                        AccountAvatar(data: account.avatarData, name: account.name)
                                        Text(account.name).font(.caption).lineLimit(1)
                                        if account.id == selected?.id {
                                            AppIcon.selected.image.font(.caption)
                                        }
                                    }.frame(width: 100).frame(minHeight: layout.controlSize).padding(8)
                                }
                                .glassControlStyle()
                                .menuFocused($focusedAccount, equals: account.id)
                                .onHover { hovering in
                                    if hovering {
                                        focusedAccount = account.id
                                    }
                                }
                                .environment(\.menuMove, moveAccountFocus)
                            }
                        }.padding(16)
                    }.frame(maxWidth: 380)
                        .background(WindowAccessor { chooserWindow = $0 })
                        .onAppear {
                            let initial = selected?.id ?? profiles.first?.id
                            focusedAccount = initial
                            navigator?.ensureFocus(
                                in: { chooserWindow },
                                reset: {},
                                apply: {
                                    guard focusedAccount == nil else {
                                        return
                                    }
                                    focusedAccount = initial
                                }
                            )
                        }
                        .onMenuExitCommand {
                            closeAccountChooser()
                        }
                        .presentationCompactAdaptation(.popover)
                }
                icon(.accountsControlsAddAccount, .addAccount, id: "add") {
                    send(.addAccount)
                }
                icon(.accountsControlsRefreshDetails, .refreshDetails, id: "refresh", action: refresh)
                    .disabled(isRefreshing)
                icon(.accountsControlsSignInAgain, .signIn, id: "signin") {
                    if let selected {
                        send(.reconnectAccount(selected.id))
                    }
                }.disabled(selected == nil)
                icon(.accountsControlsDeleteAccount, .deleteAccount, id: "delete", destructive: true) {
                    if let selected {
                        delete(selected.id)
                    }
                }.disabled(selected == nil)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .frame(
                width: expanded
                    ? actionStripWidth
                    : 0, alignment: .trailing
            )
            .opacity(
                expanded
                    ? 1
                    : 0
            )
            .clipped()
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
            FocusButton {
                pinned = true
                focused = focusTargets.last
            } label: {
                HStack(spacing: 10) {
                    if let selected {
                        AccountAvatar(data: selected.avatarData, name: selected.name)
                        if !layout.isCompact {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(selected.name).font(.headline).lineLimit(1)
                                Text(cloudText)
                                    .font(.caption2).foregroundStyle(cloudColor)
                                    .lineLimit(1)
                                    .requires(.cloud, of: selected)
                            }.frame(maxWidth: 156, alignment: .leading)
                                .fixedSize(horizontal: true, vertical: false)
                                .help(cloudTooltip)
                        }
                    } else {
                        Text(.accountsControlsTitle).font(.headline)
                    }
                }.padding(.leading, pillInsets.leading).padding(.trailing, pillInsets.trailing)
                    .padding(.vertical, pillInsets.top)
            }
            .buttonStyle(.plain)
            .focusHighlightShape(.capsule)
            .focusWithoutGrowth()
            .menuFocused($navigationFocus, equals: .profile)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                profileCenterX = midX
            }
            .help(Text(.accountsControlsHelp))
            .accessibilityLabel(accountSummary)
        }
        .environment(\.menuMove, moveFocus)
        .symbolRenderingMode(.monochrome)
        .modifier(AccountControlsSurface())
        .overlay(alignment: .topLeading) {
            if layout.hoverAffordances, expanded, let action = hoveredAction ?? shownFocus,
               action != "account" {
                Text(actionDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassPanel(.small)

                    .offset(x: tooltipPosition.x, y: tooltipPosition.y)
                    .allowsHitTesting(false).accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .zIndex(1)
        .preference(key: AccountControlsExpansion.self, value: expanded)
        .background(
            DismissOnOutsideClick(active: expanded && !choosingAccount) {
                pinned = false
                hovering = false
                focused = nil
                pointer = nil
                hoveredAction = nil
            }
        )
        .contentShape(.capsule)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovering = true
                pointer = location
            case .ended:
                hovering = false
                pointer = nil
                hoveredAction = nil
            }
        }
        .onMenuExitCommand {
            if choosingAccount {
                closeAccountChooser()
            } else {
                returnToProfile()
            }
        }
        .onChange(of: focused) { previous, current in
            if current == nil, navigationFocus == nil, !choosingAccount, let previous {
                recoverFocus(from: previous)
            }
        }
        .onChange(of: focusTargets) { _, _ in
            if let focused {
                recoverFocus(from: focused)
            }
        }
        .onChange(of: choosingAccount) { previous, current in
            if previous, !current {
                focusedAccount = nil
                pinned = true
                focused = "switch"
            }
        }
        .animation(
            reduceMotion
                ? nil
                : .spring(duration: 0.3, bounce: 0.05), value: expanded
        )

        .frame(
            width: layout.isCompact
                ? nil
                : 430,
            alignment: .trailing
        )
    }
}

extension AccountControls {
    /// The cloud status help text for the profile pill, empty when the profile cannot use cloud play.
    var cloudTooltip: Text {
        guard selected.permits(.cloud) else {
            return Text(verbatim: "")
        }
        return Text(cloudHelp)
    }

    /// The profile pill's accessibility label: the account name, the cloud status when the profile
    /// permits cloud play, and the hint that it shows the account controls.
    var accountSummary: LocalizedStringResource {
        let name = selected?.name ?? String(localized: .accountsControlsTitle)
        guard selected.permits(.cloud) else {
            return .accountsControlsSummary(name: name)
        }
        return .accountsControlsSummaryWithCloud(name: name, cloud: String(localized: cloudText))
    }
}

/// Reports up the view tree whether any account controls strip is expanded, so the library bar
/// stays visible while it is open.
struct AccountControlsExpansion: PreferenceKey {
    /// Collapsed when no account controls report a value.
    static let defaultValue = false

    /// Combines siblings so the result is expanded when any of them is.
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension AccountControls {
    /// The hit area of one action: a finger-sized square on touch, wider when its title sits under the icon,
    /// and a pointer-sized one otherwise.
    var actionSize: CGSize {
        if actionsTitled {
            return CGSize(width: 60, height: layout.controlSize)
        }
        return layout.touch
            ? CGSize(width: layout.controlSize, height: layout.controlSize)
            : CGSize(width: 34, height: 40)
    }

    /// Whether each action shows its title under its icon: on touch, where no hover tooltip can name it,
    /// when the strip has the room for five titles.
    var actionsTitled: Bool {
        !layout.hoverAffordances && !layout.isCompact
    }

    /// The horizontal distance between neighbouring action icons, used to place the tooltip.
    var actionStride: CGFloat {
        layout.touch
            ? actionSize.width + 6
            : 36
    }

    /// The width the action strip opens to when the controls expand.
    var actionStripWidth: CGFloat {
        layout.touch
            ? 5 * actionSize.width + 4 * 6 + 16
            : 210
    }

    /// The padding inside the profile pill, tight around the avatar on a compact screen.
    var pillInsets: EdgeInsets {
        guard layout.isCompact else {
            return EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        }
        return selected == nil
            ? EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14)
            : EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
    }

    /// How far below the controls the action tooltip sits when placed by focus.
    var tooltipDrop: CGFloat {
        layout.isCompact
            ? 52
            : 66
    }
}

/// The capsule behind the account controls: a tinted, rimmed capsule on a compact screen and
/// Liquid Glass otherwise.
struct AccountControlsSurface: ViewModifier {
    @Environment(\.screenLayout) private var layout

    /// Draws the capsule background that suits the screen size behind `content`.
    func body(content: Content) -> some View {
        if layout.isCompact {
            content
                .background(Color.primary.opacity(0.05), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(CompactRim.color, lineWidth: CompactRim.width)
                        .allowsHitTesting(false)
                }
        } else {
            content.glassEffect(AppGlass.control, in: .capsule)
        }
    }
}

extension AccountControls {
    /// Moves focus to the nearest available target to the left when `stale` is no longer available,
    /// falling back to the profile pill.
    func recoverFocus(from stale: String) {
        guard !focusTargets.contains(stale),
              let position = Self.targetOrder.firstIndex(of: stale) else {
            return
        }
        let fallback = Self.targetOrder[..<position].last { focusTargets.contains($0) } ?? "account"
        if fallback == "account" {
            focused = nil
            navigationFocus = .profile
        } else {
            focused = fallback
        }
    }

    /// Handles a controller move: steps between action icons, leaves down to the consoles, or from
    /// the pill opens the strip, goes to the library tabs, or hands focus to the control on the right.
    func moveFocus(_ direction: MenuMoveDirection) {
        if choosingAccount {
            moveAccountFocus(direction)
            return
        }
        if let focused, let index = focusTargets.firstIndex(of: focused) {
            guard direction == .left || direction == .right else {
                return
            }
            let nextIndex = index + (direction == .left
                ? -1
                : 1)
            if nextIndex > 0, focusTargets.indices.contains(nextIndex) {
                self.focused = focusTargets[nextIndex]
            }
            return
        }
        if direction == .down {
            focused = nil
            pinned = false
            moveToConsole(profileCenterX)
            return
        }
        if navigationFocus == .profile {
            if direction == .left {
                if expanded {
                    focused = focusTargets.last
                } else {
                    moveToLibraryTab()
                }
                return
            }
            if direction == .right {
                NotificationCenter.default.post(
                    name: liveLogButtonShown
                        ? .focusLiveLogButton
                        : .focusSettingsControl,
                    object: WindowFocus.keyWindow
                )
                return
            }
            if direction == .up, focused == nil {
                return
            }
        }
    }

    /// Steps the chooser's focus to the previous or next account.
    func moveAccountFocus(_ direction: MenuMoveDirection) {
        guard direction == .left || direction == .right,
              let index = profiles.firstIndex(where: { $0.id == focusedAccount }) else {
            return
        }
        let next = index + (direction == .left
            ? -1
            : 1)
        if profiles.indices.contains(next) {
            focusedAccount = profiles[next].id
        }
    }

    /// Collapses the strip and puts focus back on the profile pill, retrying if it does not land.
    func returnToProfile() {
        pinned = false
        hovering = false
        focused = nil
        navigationFocus = .profile
        navigator?.ensureFocus(in: WindowFocus.keyWindow) {
            focused = nil
            navigationFocus = nil
        } apply: {
            navigationFocus = .profile
        }
    }

    /// Closes the chooser and returns focus to the switch account icon.
    func closeAccountChooser() {
        choosingAccount = false
        focusedAccount = nil
        pinned = true
        focused = "switch"
        navigator?.ensureFocus(in: WindowFocus.keyWindow) {
            focused = nil
        } apply: {
            pinned = true
            focused = "switch"
        }
    }

    /// Where the tooltip sits: beside the pointer, or under the focused icon for a controller.
    var tooltipPosition: CGPoint {
        if let pointer {
            return CGPoint(x: max(0, min(pointer.x + 12, 218)), y: pointer.y + 22)
        }
        let index =
            ["switch", "add", "refresh", "signin", "delete"].firstIndex(of: focused ?? "") ?? 0
        return CGPoint(x: CGFloat(index) * actionStride + 8, y: tooltipDrop)
    }
    /// The tooltip text for the hovered or focused action.
    var actionDescription: LocalizedStringResource {
        switch hoveredAction ?? shownFocus {
        case "switch":
            profiles.count > 1
                ? .accountsControlsSwitchAccount
                : .accountsControlsSwitchNeedsAnother
        case "add":
            .accountsControlsAddAccount
        case "refresh":
            .accountsControlsRefreshDetails
        case "signin":
            .accountsControlsSignInAgain
        case "delete":
            .accountsControlsDeleteFromDevice
        default:
            .accountsControlsHelp
        }
    }

    /// The one-word title shown under an action's icon on touch.
    ///
    /// - Parameter id: The action's focus id.
    /// - Returns: The title, or `nil` for an id that has none.
    static func shortTitle(of id: String) -> LocalizedStringResource? {
        switch id {
        case "switch":
            .accountsControlsShortSwitch
        case "add":
            .accountsControlsShortAdd
        case "refresh":
            .commonRefresh
        case "signin":
            .accountsControlsShortSignIn
        case "delete":
            .commonDelete
        default:
            nil
        }
    }

    /// One round action icon with hover glass, controller focus and an accessibility label, titled under the
    /// icon where no tooltip can appear.
    ///
    /// - Parameters:
    ///   - title: The accessibility label.
    ///   - symbol: The icon shown.
    ///   - id: The focus and hover id of the icon.
    ///   - destructive: Whether the action is destructive, which colours it red.
    ///   - action: What the icon does.
    func icon(
        _ title: LocalizedStringResource, _ symbol: AppIcon, id: String, destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        FocusButton(
            role: destructive
                ? .destructive
                : nil, action: action
        ) {
            VStack(spacing: 0) {
                symbol.image.font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .hoverGlass(hoveredAction == id || inputMode.shows(focused == id), in: .circle)
                if actionsTitled, let shortTitle = Self.shortTitle(of: id) {
                    Text(shortTitle)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: actionSize.width, height: actionSize.height).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.circle)
        .foregroundStyle(
            destructive
                ? Color.red
                : Color.primary
        )
        .menuFocused($focused, equals: id)
        .onHover {
            hoveredAction =
                $0
                    ? id
                    : (hoveredAction == id
                        ? nil
                        : hoveredAction)
        }
        .accessibilityLabel(title)
    }
}

extension View {
    /// Draws an interactive glass backing behind the view while it is active and enabled, animating it in and
    /// out.
    ///
    /// - Parameters:
    /// - active: Whether the glass is shown, typically while the pointer hovers.
    /// - shape: The shape the glass fills.
    public func hoverGlass<S: Shape>(_ active: Bool, in shape: S) -> some View {
        modifier(HoverGlass(active: active, shape: shape))
    }
}

private struct HoverGlass<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: shape)
            .animation(animation, value: shown)
    }

    private var shown: Bool {
        active && isEnabled
    }

    private var glass: Glass {
        guard shown else {
            return .identity
        }
        return AppGlass.control.interactive()
    }

    private var animation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .spring(duration: 0.22, bounce: 0.2)
    }
}
