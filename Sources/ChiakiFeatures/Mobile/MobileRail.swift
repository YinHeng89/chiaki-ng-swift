import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch library's floating Liquid Glass rail: Back while something is open, the sections, Join and Alerts,
/// and the account, which opens Account and Settings.
///
/// It lies along `LibraryRailEdge`: down a side edge it stacks its stops, along the top or bottom it lays them
/// in a row. Every stop sends an action to the library; the rail keeps no state of its own.
struct MobileRail: View {
    /// The library.
    let store: StoreOf<LibraryFeature>

    /// The window edge the rail lies along.
    let edge: LibraryRailEdge

    /// The width of a stop, and the rail's thickness without its padding.
    static let stopSize: CGFloat = 40

    /// The rail's thickness.
    static let thickness: CGFloat = stopSize + 12

    var body: some View {
        stack {
            if store.mobileCanGoBack {
                stop(.commonBack, symbol: "chevron.left", selected: false) {
                    store.send(.mobileBackTapped)
                }
                divider
            }
            ForEach(store.availableSections, id: \.self) { section in
                stop(Self.title(for: section), symbol: Self.symbol(for: section),
                     selected: sectionSelected(section)) {
                    store.send(.mobileSectionTapped(section))
                }
                .disabled(section == .cloud && store.cloudUnavailable)
            }
            divider
            if KakusanBuild.included {
                stop(.mobileRailJoinGame, symbol: "person.2", selected: false) {
                    store.send(.requested(.joinGame))
                }
            }
            stop(.mobileRailNotifications, symbol: "bell", selected: store.alerts.panel == .open) {
                store.send(.alertsTapped)
            }
            .overlay(alignment: .topTrailing) {
                if store.alerts.unseen > 0 {
                    AlertsBadge(count: store.alerts.unseen)
                        .offset(x: 4, y: -2)
                        .allowsHitTesting(false)
                }
            }
            .popover(isPresented: alertsShown, arrowEdge: arrowEdge) {
                PSNAlertsPanel(
                    store: store.scope(state: \.alerts, action: \.alerts),
                    consoles: store.partyConsoles,
                    cloudPlayable: store.cloudPlayableAlerts
                ) {
                    store.send(.alertsPanelClosed)
                }
                .presentationCompactAdaptation(.popover)
            }
            divider
            account
        }
        .padding(6)
        .glassEffect(AppGlass.control.interactive(), in: .capsule)
    }

    @ViewBuilder private func stack(@ViewBuilder _ content: () -> some View) -> some View {
        if edge.isVertical {
            VStack(spacing: 4, content: content)
        } else {
            HStack(spacing: 4, content: content)
        }
    }

    private var alertsShown: Binding<Bool> {
        Binding(
            get: {
                store.alerts.panel == .open
            },
            set: { shown in
                if !shown {
                    store.send(.alertsPanelClosed)
                }
            }
        )
    }

    private var arrowEdge: Edge {
        switch edge {
        case .left:
            .leading
        case .right:
            .trailing
        case .top:
            .top
        case .bottom:
            .bottom
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(
                width: edge.isVertical
                    ? 24
                    : 0.5,
                height: edge.isVertical
                    ? 0.5
                    : 24
            )
            .padding(edge.isVertical
                ? .vertical
                : .horizontal, 2)
    }

    private var accountSelected: Bool {
        switch store.mobile.page {
        case .account, .settings:
            true
        case .home, .console:
            false
        }
    }

    private var account: some View {
        Button {
            store.send(.mobile(.accountOpened))
        } label: {
            AccountAvatar(
                data: store.selectedProfile?.avatarData,
                name: store.selectedProfile?.name ?? String(localized: .mobileRailAccount)
            )
            .frame(width: 30, height: 30)
            .clipShape(.circle)
            .overlay {
                Circle().strokeBorder(
                    accountSelected
                        ? Palette.accent
                        : .clear,
                    lineWidth: 2
                )
            }
            .frame(width: Self.stopSize, height: Self.stopSize)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.mobileAccountTitle))
    }

    private func sectionSelected(_ section: LibrarySection) -> Bool {
        guard section == store.section else {
            return false
        }
        switch store.mobile.page {
        case .home, .console:
            return true
        case .account, .settings:
            return false
        }
    }

    private func stop(
        _ title: LocalizedStringResource,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    selected
                        ? Palette.accent
                        : .primary
                )
                .frame(width: Self.stopSize, height: Self.stopSize)
                .background {
                    if selected {
                        Circle().fill(.white.opacity(0.16))
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    /// The name a section's stop is read by.
    ///
    /// - Parameter section: The section.
    /// - Returns: The section's name.
    static func title(for section: LibrarySection) -> LocalizedStringResource {
        switch section {
        case .consoles:
            .mobileConsolesTitle
        case .cloud:
            .mobileRailCloud
        case .trophies:
            .mobileTrophiesTitle
        }
    }

    /// The symbol a section's stop shows.
    ///
    /// - Parameter section: The section.
    /// - Returns: An SF Symbol name.
    static func symbol(for section: LibrarySection) -> String {
        switch section {
        case .consoles:
            "gamecontroller"
        case .cloud:
            "cloud"
        case .trophies:
            "trophy"
        }
    }
}

extension EnvironmentValues {
    /// Whether the open cloud game is closed from the touch rail's Back, so the detail draws no Close button.
    @Entry var gameDetailClosesFromRail = false
}
