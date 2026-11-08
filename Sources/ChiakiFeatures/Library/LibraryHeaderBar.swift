import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The compact window's header: Join a game, Notifications, Add console, the section tabs, the account menu and
/// Settings, in a bar that hides while the content scrolls.
struct LibraryHeaderBar: View {
    /// The library.
    let store: StoreOf<LibraryFeature>
    /// What the shelf shows.
    let shelf: LibraryShelf
    /// The library's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// The measured horizontal centre of each section tab.
    @Binding var tabCenters: [LibrarySection: CGFloat]
    /// Applies a focus move.
    let apply: (ConsoleShelfFocusGraph.Move) -> Void
    /// Opens Join a game.
    let joinGame: () -> Void
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.topControlsLayout) private var topControlsLayout
    @State private var headerMaxX: CGFloat?

    var body: some View {
        AutoHidingLibraryBar {
            CompactLibraryBar(trailingReserve: trailingReserve) {
                if KakusanBuild.included {
                    barButton(
                        .libraryBarJoinGame,
                        symbol: "person.2",
                        stop: .joinGame,
                        action: joinGame
                    ) { direction in
                        apply(shelf.graph.header.moveJoin(direction))
                    }
                }
                alertsButton
                if shelf.graph.barAddConsole {
                    barButton(.libraryShelfAddConsole, symbol: AppIcon.add.rawValue, stop: .addConsole) {
                        store.send(.requested(.addConsole))
                    } move: { direction in
                        apply(shelf.graph.moveConsole(from: .addConsole, direction))
                    }
                }
            } sections: {
                sections
            } account: {
                AccountMenu(
                    store: store,
                    focus: focus,
                    moveToContent: { midX in
                        apply(shelf.graph.trailingContent(horizontalPosition: midX, waiting: shelf.waiting))
                    },
                    moveToSections: {
                        apply(.focus(.librarySection(store.availableSections.last ?? .consoles)))
                    }
                )
            } settings: {
                CompactSettingsButton {
                    apply(.focus(.profile))
                } moveDown: {
                    apply(shelf.graph.trailingContent(horizontalPosition: nil, waiting: shelf.waiting))
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).maxX
            } action: { maxX in
                headerMaxX = maxX
            }
            .zIndex(10)
        }
    }

    private var trailingReserve: CGFloat {
        guard let headerMaxX, let logMinX = topControlsLayout?.logMinX else {
            return 0
        }
        return max(0, headerMaxX - logMinX + CompactLibraryBarMetrics.spacing)
    }

    private var sections: some View {
        HStack(spacing: 0) {
            ForEach(store.availableSections, id: \.self) { section in
                let unavailable = section == .cloud && store.cloudUnavailable
                FocusButton {
                    select(section)
                } label: {
                    sectionLabel(section)
                }
                .buttonStyle(.plain)
                .focusHighlightShape(.capsule)
                .focusWithoutGrowth()
                .disabled(unavailable)
                .opacity(
                    unavailable
                        ? 0.4
                        : 1
                )
                .menuFocused(focus, equals: .librarySection(section))
                .environment(\.menuMove) { direction in
                    apply(shelf.graph.header.moveSection(from: section, direction))
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .global).midX
                } action: { midX in
                    tabCenters[section] = midX
                }
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(
                    store.section == section
                        ? .isSelected
                        : []
                )
            }
        }
        .glassEffect(AppGlass.control, in: .capsule)
    }

    private func sectionLabel(_ section: LibrarySection) -> some View {
        ViewThatFits(in: .horizontal) {
            Label(section.title, systemImage: section.icon.rawValue)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
            Image(systemName: section.icon.rawValue)
                .padding(.horizontal, 14)
        }
        .font(.callout.weight(.medium))
        .frame(height: CompactLibraryBarMetrics.control - 8)
        .background(
            store.section == section
                ? Color.primary.opacity(0.14)
                : .clear,
            in: .capsule
        )
        .padding(4)
        .contentShape(.capsule)
    }

    private func select(_ section: LibrarySection) {
        guard section != store.section, section != .cloud || !store.cloudUnavailable else {
            return
        }
        navigator?.endEditing()
        withAnimation(AppMotion.animation(reduced: reduceMotion)) {
            _ = store.send(.sectionSelected(section))
        }
    }

    private var alertsButton: some View {
        barButton(
            store.alerts.unseen > 0
                ? .libraryBarNotificationsNew(count: store.alerts.unseen)
                : .libraryBarNotifications,
            symbol: "bell",
            stop: .notifications,
            badge: store.alerts.unseen
        ) {
            store.send(.alertsTapped)
        } move: { direction in
            apply(shelf.graph.header.moveNotifications(direction))
        }
        .popover(
            isPresented: Binding(
                get: {
                    store.alerts.panel == .open
                },
                set: { shown in
                    if !shown {
                        store.send(.alertsPanelClosed)
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            PSNAlertsPanel(
                store: store.scope(state: \.alerts, action: \.alerts),
                consoles: store.partyConsoles,
                cloudPlayable: store.cloudPlayableAlerts
            ) {
                store.send(.alertsPanelClosed)
            }
        }
    }

    private func barButton(
        _ title: LocalizedStringResource,
        symbol: String,
        stop: ConsoleLibraryFocus,
        badge: Int = 0,
        action: @escaping () -> Void,
        move: @escaping @MainActor (MenuMoveDirection) -> Void
    ) -> some View {
        FocusButton(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: CompactLibraryBarMetrics.control, height: CompactLibraryBarMetrics.control)
                .glassEffect(AppGlass.control, in: .circle)
                .contentShape(.circle)
                .overlay(alignment: .topTrailing) {
                    AlertsBadge(count: badge)
                }
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.circle)
        .focusWithoutGrowth()
        .menuFocused(focus, equals: stop)
        .environment(\.menuMove, move)
        .accessibilityLabel(title)
    }
}

/// The compact header's account menu, wired to the library: the accounts, their cloud line and the requests
/// its buttons send.
private struct AccountMenu: View {
    /// The library.
    let store: StoreOf<LibraryFeature>
    /// The library's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// Moves focus down into the content, below the control at this horizontal centre.
    let moveToContent: (CGFloat?) -> Void
    /// Moves focus left to the section tabs.
    let moveToSections: () -> Void

    var body: some View {
        let cloud = AccountCloudSummary(store: store)
        AccountControls(
            profiles: store.accounts,
            selected: store.selectedProfile,
            cloudText: cloud.text,
            cloudHelp: cloud.help,
            cloudColor: cloud.color,
            isRefreshing: store.isRefreshing,
            refresh: {
                store.send(.requested(.refreshAccounts))
            },
            send: send,
            delete: { id in
                store.send(.requested(.removeAccount(id)))
            },
            navigationFocus: focus,
            moveToConsole: moveToContent,
            moveToLibraryTab: moveToSections
        )
    }

    private func send(_ request: LibraryRequest) {
        store.send(.requested(request))
    }
}

/// Shows the library bar and slides it away after a quiet spell, leaving a grab handle that brings it back.
///
/// Touching the bar restarts the countdown; the bar stays pinned while a controller drives the app or the
/// account controls are expanded.
private struct AutoHidingLibraryBar<Bar: View>: View {
    /// Whether the bar is on screen or collapsed to its handle.
    enum Presence: Hashable {
        /// The bar is visible.
        case shown
        /// Only the grab handle is visible.
        case hidden
    }

    /// The inputs that restart the hide countdown whenever any of them changes.
    struct Rest: Hashable {
        /// Whether the bar is currently shown.
        let presence: Presence
        /// A counter bumped on every touch of the bar.
        let activity: Int
        /// Whether the bar is held open and must not hide.
        let pinned: Bool
    }

    /// How long the bar stays visible without activity before it hides.
    static var delay: Duration {
        .seconds(6)
    }

    /// The bar content that is shown and hidden.
    @ViewBuilder let bar: Bar
    @State private var presence = Presence.shown
    @State private var activity = 0
    @State private var expanded = false
    @State private var settingsHostID = UUID()
    @Environment(\.inputMode) private var inputMode
    @Environment(\.topControlsLayout) private var topControlsLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinned: Bool {
        inputMode == .controller || expanded
    }

    var body: some View {
        VStack(spacing: 0) {
            switch presence {
            case .shown:
                bar
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in
                                activity &+= 1
                            }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            case .hidden:
                handle
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(AccountControlsExpansion.self) { value in
            MainActor.assumeIsolated {
                expanded = value
            }
        }
        .task(id: Rest(presence: presence, activity: activity, pinned: pinned)) {
            guard presence == .shown, !pinned else {
                return
            }
            try? await Task.sleep(for: Self.delay)
            if !Task.isCancelled {
                presence = .hidden
            }
        }
        .onChange(of: pinned) { _, pinned in
            if pinned {
                presence = .shown
            }
        }
        .onAppear {
            topControlsLayout?.hostSettings(settingsHostID, true)
        }
        .onDisappear {
            topControlsLayout?.hostSettings(settingsHostID, false)
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: presence)
    }

    private var handle: some View {
        Button {
            presence = .shown
        } label: {
            Capsule()
                .fill(Color.primary.opacity(0.4))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(.libraryBarShowLibraryBar)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height > 8 {
                        presence = .shown
                    }
                }
        )
    }
}
