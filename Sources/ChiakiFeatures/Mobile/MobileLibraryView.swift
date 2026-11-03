import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The library on a touch screen: the shown section or the page pushed over it, with the floating rail on the
/// chosen edge.
///
/// What is shown follows the library's state alone: ``MobileShellFeature`` for the pushed pages, the library's
/// section, the cloud library's open game and the trophies' open title. The view runs the library the way
/// ``LibraryView`` does, so the same reducers start and stop with the screen.
struct MobileLibraryView: View {
    /// The library.
    @Bindable var store: StoreOf<LibraryFeature>

    /// The settings, which Account and Settings shows.
    let settings: StoreOf<SettingsFeature>

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.screenLayout) private var layout
    @Environment(\.libraryRailEdge) private var railEdge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        layers
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.mobile.page)
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.section)
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.cloudLibrary.selection)
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.trophies.opened?.title.id)
            .task {
                await store.send(.task).finish()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                scenePhaseChanged(phase)
            }
            .onChange(of: inSettings) { _, shown in
                settingsShown(shown)
            }
            .onDisappear {
                store.send(.disappeared)
            }
    }

    private var layers: some View {
        GeometryReader { proxy in
            screen(size: proxy.size)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: railAlignment) {
            MobileRail(store: store, edge: railEdge)
                .padding(railEdgeInsets)
                .ignoresSafeArea(.keyboard)
        }
        .overlay {
            CloudToastLayer(toasts: store.scope(state: \.toasts, action: \.toasts))
        }
    }

    private func screen(size: CGSize) -> some View {
        ZStack {
            page(size: size)
                .padding(contentInsets)
                .id(store.mobile.page)
                .transition(pageTransition)
                .opacity(
                    openCloudGame == nil
                        ? 1
                        : 0
                )
                .allowsHitTesting(openCloudGame == nil)
            if let game = openCloudGame {
                MobileCloudDetail(
                    store: store.scope(state: \.cloudLibrary, action: \.cloudLibrary),
                    game: game,
                    height: size.height
                )
                .frame(width: size.width, height: size.height)
                .environment(\.screenLayout, detailLayout)
                .environment(\.gameDetailClosesFromRail, true)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
        .mobileSwipeBack(enabled: store.mobileCanGoBack) {
            store.send(.mobileBackTapped)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        let forward = store.mobile.forward
        return .asymmetric(
            insertion: .move(edge: forward
                ? .trailing
                : .leading).combined(with: .opacity),
            removal: .move(edge: forward
                ? .leading
                : .trailing).combined(with: .opacity)
        )
    }

    private var detailLayout: ScreenLayout {
        ScreenLayout(
            room: layout.room,
            stature: layout.stature,
            touch: layout.touch,
            sideInset: max(layout.sideInset, railOffset + MobileRail.thickness + 12),
            bottomInset: layout.bottomInset
        )
    }

    private var openCloudGame: CloudGame? {
        guard store.mobile.page == .home, store.section == .cloud else {
            return nil
        }
        return store.cloudLibrary.selectedGame
    }

    private func scenePhaseChanged(_ phase: ScenePhase) {
        store.send(.scenePhaseChanged(
            phase == .active
                ? .active
                : .inactive
        ))
    }

    private func settingsShown(_ shown: Bool) {
        settings.send(
            shown
                ? .launched
                : .closed
        )
    }

    private var inSettings: Bool {
        switch store.mobile.page {
        case .account, .settings:
            true
        case .home, .console:
            false
        }
    }

    @ViewBuilder private func page(size: CGSize) -> some View {
        switch store.mobile.page {
        case .home:
            section
        case .console(let id):
            if let console = store.linkedConsoles.first(where: { $0.id == id }) {
                MobileConsolePage(store: store, console: console)
            }
        case .account:
            MobileAccountView(store: store, settings: settings)
        case .settings(let route):
            MobileSettingsPage(settings: settings, route: route)
        }
    }

    @ViewBuilder private var section: some View {
        switch store.section {
        case .consoles:
            MobileConsolesView(store: store)
        case .cloud:
            MobileCloudView(store: store.scope(state: \.cloudLibrary, action: \.cloudLibrary))
                .requires(.cloud, of: store.selectedProfile)
        case .trophies:
            MobileTrophiesView(store: store.scope(state: \.trophies, action: \.trophies))
                .requires(.trophies, of: store.selectedProfile)
        }
    }

    private var railAlignment: Alignment {
        switch railEdge {
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

    private var railOffset: CGFloat {
        max(16, layout.sideInset + 4)
    }

    private var railEdgeInsets: EdgeInsets {
        switch railEdge {
        case .left:
            EdgeInsets(top: 0, leading: railOffset, bottom: 0, trailing: 0)
        case .right:
            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: railOffset)
        case .top:
            EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)
        case .bottom:
            EdgeInsets(top: 0, leading: 0, bottom: max(10, layout.bottomInset), trailing: 0)
        }
    }

    private var contentInsets: EdgeInsets {
        let side = max(16, layout.sideInset)
        let beside = railOffset + MobileRail.thickness + 24
        var insets = EdgeInsets(top: 0, leading: side, bottom: layout.bottomInset, trailing: side)
        switch railEdge {
        case .left:
            insets.leading = max(side, beside)
        case .right:
            insets.trailing = max(side, beside)
        case .top:
            insets.top = 10 + MobileRail.thickness + 8
        case .bottom:
            insets.bottom = max(10, layout.bottomInset) + MobileRail.thickness + 8
        }
        return insets
    }
}
