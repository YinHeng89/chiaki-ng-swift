import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI

/// The library's arrangement: the compact header above the shown section, or the rail on the chosen window
/// edge beside it, dimming the section while the rail is expanded.
struct LibraryLayout: View {
    /// The library.
    @Bindable var store: StoreOf<LibraryFeature>

    /// What the console shelf shows and how focus moves across it.
    let shelf: LibraryShelf

    /// The rail's stops.
    let rail: LibraryRail

    /// The library's controller focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding

    /// The horizontal centre of each section tab in the compact header.
    @Binding var tabCenters: [LibrarySection: CGFloat]

    /// The width of the console grid.
    @Binding var gridWidth: CGFloat

    /// What the rail, header and shelf ask the library to do.
    let actions: LibraryLayoutActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    @Environment(\.libraryRailEdge) private var railEdge
    @Environment(\.cloudLibraryHeight) private var cloudHeight
    @State private var railExpanded = false
    @State private var libraryCovered = false

    /// The rail or compact header beside the shown section, inset from the window's edges and, on a compact
    /// touch screen, kept below the status bar and clear of the screen's side insets, which the root leaves to
    /// each screen.
    var body: some View {
        arrangement
            .padding(.horizontal, horizontalInset)
            .padding(.top, topInset)
            .padding(
                .bottom,
                layout.isCompact
                    ? 4
                    : 24
            )
    }

    private var horizontalInset: CGFloat {
        layout.isCompact
            ? layout.sideInset
            : 16
    }

    private var topInset: CGFloat {
        layout.isCompact
            ? layout.topChromeInset
            : 24
    }

    @ViewBuilder private var arrangement: some View {
        if layout.isCompact {
            VStack(alignment: .leading, spacing: 0) {
                LibraryHeaderBar(
                    store: store,
                    shelf: shelf,
                    focus: focus,
                    tabCenters: $tabCenters,
                    apply: actions.apply,
                    joinGame: actions.joinGame
                )
                .opacity(
                    libraryCovered
                        ? 0
                        : 1
                )
                .allowsHitTesting(!libraryCovered)
                .animation(.easeOut(duration: 0.15), value: libraryCovered)
                sectionContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(maxWidth: contentWidth)
            .onChange(of: store.section) { _, _ in
                libraryCovered = false
            }
        } else if railEdge.isVertical {
            HStack(alignment: .top, spacing: 24) {
                if railEdge == .left {
                    railSpace
                }
                column
                    .padding(
                        railEdge == .left
                            ? .trailing
                            : .leading,
                        12
                    )
                if railEdge == .right {
                    railSpace
                }
            }
            .overlay {
                Color.black
                    .opacity(
                        railExpanded
                            ? 0.32
                            : 0
                    )
                    .padding(-80)
                    .allowsHitTesting(false)
                    .animation(AppMotion.animation(reduced: reduceMotion), value: railExpanded)
            }
            .overlay(
                alignment: railEdge == .left
                    ? .leading
                    : .trailing
            ) {
                libraryRail
                    .padding(.vertical, 20)
            }
        } else {
            VStack(spacing: 20) {
                if railEdge == .top {
                    libraryRail
                }
                column
                    .padding(.horizontal, 12)
                if railEdge == .bottom {
                    libraryRail
                        .padding(.trailing, bottomBarLogoClearance)
                }
            }
        }
    }

    private var bottomBarLogoClearance: CGFloat {
        max(0, RootCornerLogo.trailingExtent(for: layout) + 12 - horizontalInset)
    }

    private var railSpace: some View {
        Color.clear
            .frame(width: LibraryRailView<EmptyView, EmptyView>.collapsedWidth(for: layout))
    }

    private var column: some View {
        sectionContent
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity)
    }

    private var contentWidth: CGFloat {
        store.section == .cloud
            ? 1760
            : 1440
    }

    private var sectionContent: some View {
        ZStack(alignment: .topLeading) {
            if store.section == .cloud {
                CloudLibraryView(
                    store: store.scope(state: \.cloudLibrary, action: \.cloudLibrary),
                    height: cloudHeight
                )
                .environment(\.libraryRailShown, !layout.isCompact)
                .requires(.cloud, of: store.selectedProfile)
                .transition(sectionTransition)
                .onPreferenceChange(LibraryCoverKey.self) { covered in
                    MainActor.assumeIsolated {
                        libraryCovered = covered
                    }
                }
            } else if store.section == .trophies {
                TrophiesView(store: store.scope(state: \.trophies, action: \.trophies))
                    .environment(\.libraryRailShown, !layout.isCompact)
                    .requires(.trophies, of: store.selectedProfile)
                    .transition(sectionTransition)
                    .onPreferenceChange(LibraryCoverKey.self) { covered in
                        MainActor.assumeIsolated {
                            libraryCovered = covered
                        }
                    }
            } else {
                consoleShelf
                    .transition(sectionTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var consoleShelf: some View {
        if layout.isCompact {
            CompactConsoleShelfView(
                store: store,
                shelf: shelf,
                focus: focus,
                gridWidth: $gridWidth,
                apply: actions.apply,
                playTitle: actions.playTitle
            )
        } else {
            ConsoleShelfView(
                store: store,
                shelf: shelf,
                focus: focus,
                gridWidth: $gridWidth,
                apply: actions.apply,
                playTitle: actions.playTitle
            )
        }
    }

    private var sectionTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        if store.section != .consoles {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
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

    private var libraryRail: some View {
        LibraryRailView(
            rail: rail,
            selected: store.section,
            account: store.selectedProfile,
            focus: focus,
            accountSheet: $store.scope(state: \.accountSheet, action: \.accountSheet),
            activate: actions.activateRail,
            move: actions.moveRail,
            shownExpanded: $railExpanded,
            unseenAlerts: store.alerts.unseen,
            alertsShown: alertsShown,
            alerts: alertsPanel,
            sheet: accountSheet
        )
    }

    private func alertsPanel() -> PSNAlertsPanel {
        PSNAlertsPanel(
            store: store.scope(state: \.alerts, action: \.alerts),
            consoles: store.partyConsoles,
            cloudPlayable: store.cloudPlayableAlerts
        ) {
            store.send(.alertsPanelClosed)
        }
    }

    private func accountSheet(_ sheet: StoreOf<LibraryAccountSheetFeature>) -> LibraryAccountSheet {
        LibraryAccountSheet(
            store: sheet,
            profiles: store.accounts,
            selected: store.selectedProfile,
            cloud: AccountCloudSummary(store: store),
            isRefreshing: store.isRefreshing
        )
    }
}

/// Reports whether a cloud screen cover, such as the game detail or search, is open, so the library can hide
/// what it covers.
public struct LibraryCoverKey: PreferenceKey {
    /// Creates a library cover key.
    public init() {
    }

    /// No cover is open until a view says otherwise.
    public static let defaultValue = false

    /// Combines the reports of several views, treating the library as covered when any of them is.
    ///
    /// - Parameters:
    ///   - value: The combined report so far.
    ///   - nextValue: The next view's report.
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// What the library's rail, compact header and console shelf ask the library screen to do.
struct LibraryLayoutActions {
    /// Applies a focus move the shelf graph decided.
    let apply: (ConsoleShelfFocusGraph.Move) -> Void

    /// Joins a friend's game.
    let joinGame: () -> Void

    /// Plays a recently played title on a console.
    let playTitle: (UUID, RecentTitle) -> Void

    /// Activates a rail stop.
    let activateRail: (ConsoleLibraryFocus) -> Void

    /// Moves focus from a rail stop in a direction.
    let moveRail: (ConsoleLibraryFocus, MenuMoveDirection) -> Void
}
