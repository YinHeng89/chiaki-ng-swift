import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The cloud library: its header controls, the paged grid of games, the game detail and the search field.
///
/// Focus that leaves the content, or Back towards the rail, is reported to the store, which hands it to the
/// library; focus entering from the library arrives as `CloudLibraryFeature/State/contentFocus`.
struct CloudLibraryView: View {
    /// A focus stop of the cloud library.
    typealias FocusItem = CloudLibraryFocus

    /// The app's menu navigator, which carries the focus, activation and Back handlers and the input gate.
    @Environment(\.menuNavigator) var navigator
    /// Asks the app to quit, used when Back leaves the library with no rail to return to.
    @Environment(\.requestQuit) var requestQuit
    /// The cloud library.
    let store: StoreOf<CloudLibraryFeature>
    /// The height the game detail fills.
    var height: CGFloat = 820

    /// The account the library lists games for.
    var accountID: UUID? {
        store.accountID
    }
    /// Whether Reduce Motion is on, which turns slides and growth into fades.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Whether the library is interactive; its handlers are registered only while it is.
    @Environment(\.isEnabled) var isEnabled
    /// Whether input is coming from a controller, the keyboard or the pointer, which decides when focus is
    /// drawn.
    @Environment(\.inputMode) var inputMode
    /// The screen's layout traits: a compact window covers the whole window with the detail and search and
    /// drops the heading.
    @Environment(\.screenLayout) var layout
    /// Whether the library's rail is shown, so Back returns to it instead of quitting.
    @Environment(\.libraryRailShown) var libraryRailShown
    /// The last item that held focus, restored when the library becomes interactive or is shown again.
    var lastFocus: FocusItem? {
        store.heldFocus
    }
    /// Whether the debug sample pre-orders are mixed into the library, which reloads it when toggled.
    @AppStorage(DeveloperPreviewSetting.samplePreorders) var showsSamplePreorders = false
    /// The library's controller focus.
    @MenuFocusState var focus: FocusItem?
    /// The game whose card should take focus once it appears.
    @State var pendingGameFocus: String?
    /// The order of the matching games last shown, used to keep focus on a game when the listing reorders.
    @State var shownOrder = CloudListingOrder()
    /// The position the open game held in the listing before it dropped out, so focus can return to that slot
    /// when the detail closes.
    @State var openedSlot: Int?
    /// The game to return to when focus leaves the header controls for the grid.
    @State var toolbarReturnGameID: String?
    /// The position on the page that focus returns to when it leaves the page bar.
    @State var pageBarReturnIndex = 0
    /// Paces page turns while left or right is held on the page bar.
    @State var pageHold = CloudPageHold()
    /// Turns trackpad and wheel scrolling into page turns.
    @State var pageSwipe = CloudPageSwipe()
    /// Whether the pointer is over the grid, which lets scrolling turn pages.
    @State var gridHovered = false
    /// The local scroll wheel monitor that turns pages, while it is installed.
    @State var scrollMonitor: Any?
    /// The grid's width in global coordinates, used to map header controls onto columns.
    @State var gridWidth: CGFloat = 0
    /// The grid's leading edge in global coordinates.
    @State var gridMinX: CGFloat = 0
    /// The horizontal centre of each header control in global coordinates, so focus can move to the nearest
    /// control.
    @State var headerCenters = [FocusItem: CGFloat]()
    /// The registration of the focus move handler, while it is installed.
    @State var focusMoveHandlerID: MenuHandlerID?
    /// The registration of the activation handler that swallows presses while the detail loads or checks,
    /// while it is installed.
    @State var loadingActivationHandlerID: MenuHandlerID?
    /// The registration of the Back handler, while it is installed.
    @State var backHandlerID: MenuHandlerID?
    /// The window hosting the library, so handlers act only on events from it.
    @State var hostWindow: PlatformWindow?
    /// The library's origin in global coordinates, used to centre a screen cover on the window.
    @State var origin = CGPoint.zero
    var body: some View {
        ZStack {
            libraryContent
                .padding(
                    .vertical,
                    layout.isCompact
                        ? 10
                        : 28
                )
                .background {
                    if store.selectedGame != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.send(.select(nil))
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(store.selectedGame != nil)

            if let game = store.selectedGame {
                Dimming.light.color
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.select(nil))
                    }
                    .transition(.opacity)
                    .zIndex(1)

                coveringScreen(detail(game))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(2)
            }

            if let search = store.scope(state: \.destination?.search, action: \.destination.search) {
                coveringScreen(CloudSearchOverlay(store: search))
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGPoint.self) { geometry in
            geometry.frame(in: .global).origin
        } action: { point in
            origin = point
        }
        .preference(
            key: LibraryCoverKey.self,
            value: screenCover != nil && (store.selectedGame != nil || store.isSearching)
        )
        .appConfirmation(store.websiteWarning.map(Self.confirmation), confirm: {
            store.send(.websiteWarning(.presented(.play)))
        }, cancel: {
            store.send(.websiteWarning(.dismiss))
        })
        .background(WindowAccessor { hostWindow = $0 })
        .background(CloudFocusWatch(focus: $focus, changed: focusChanged))
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.selection)
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.isSearching)
        .onChange(of: inputMode) { _, _ in
            focusChanged(focus)
        }
        .onChange(of: store.selectedGame?.id) { previous, game in
            if game == nil, let previous {
                returnFocus(toGame: previous)
            }
        }
        .onChange(of: store.listing.derivations.matches, initial: true) { _, _ in
            let current = CloudListingOrder(store.state)
            if shownOrder.sameListing(as: current) {
                followFocusedGame(from: shownOrder.ids, to: current.ids)
                noteOpenedSlot(from: shownOrder.ids, to: current.ids)
            }
            shownOrder = current
        }
        .onChange(of: store.visibleGameIDs, initial: true) { _, _ in
            focusFirstVisibleGame()
        }
        .onChange(of: store.isSearching) { _, searching in
            if !searching {
                focusFirstVisibleGame()
            }
        }
        .onAppear {
            if isEnabled {
                registerFocusMoveHandler()
                registerQuitBackHandler()
                registerPageScroll()
                if lastFocus != nil {
                    restoreFocus()
                }
            }
        }
        .onMenuKeyPress(keys: [.pageUp, .pageDown], phases: [.down, .repeat]) { press in
            guard store.selectedGame == nil, focus != .search, focus != .pageNumber else {
                return .ignored
            }
            turnPage(press.key == .pageDown
                ? 1
                : -1)
            return .handled
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                registerFocusMoveHandler()
                registerQuitBackHandler()
                registerPageScroll()
                restoreFocus()
            } else {
                unregisterFocusMoveHandler()
                unregisterQuitBackHandler()
                unregisterPageScroll()
            }
        }
        .onDisappear {
            unregisterFocusMoveHandler()
            unregisterQuitBackHandler()
            unregisterPageScroll()
        }
        .onMenuCommand([.previous]) { event in
            cycleFilter(by: -1, from: event)
        }
        .onMenuCommand([.next]) { event in
            cycleFilter(by: 1, from: event)
        }
        .onChange(of: store.contentFocus, initial: true) { _, request in
            enterContent(request)
        }
    }

    private func enterContent(_ request: LibraryContentFocus?) {
        guard let request, isEnabled, !(navigator?.inputGate.isBlocking ?? false), store.selectedGame == nil
        else {
            return
        }
        store.send(.contentFocusHandled)
        if let midX = request.horizontalPosition,
           let target = headerGraph.control(nearest: CGFloat(midX), centers: headerCenters) {
            focus = target
            return
        }
        switch request.entry {
        case .resume:
            restoreFocus()
        case .firstFilter:
            focus = .filter(.all)
        case .browse:
            focus = .filter(.browse)
        case .platform:
            focus = .platform(store.platform)
        case .selectedFilter:
            focus = .filter(store.filter)
        }
    }
}

extension CloudLibraryView {
    /// Turns the store's warning about playing on the website into the app's confirmation dialog.
    ///
    /// - Parameter alert: The warning's title, message and buttons.
    /// - Returns: The confirmation, titled from the alert with its confirming button's label.
    static func confirmation(_ alert: AlertState<CloudLibraryFeature.Action.WebsiteWarning>)
        -> AppConfirmation {
        AppConfirmation(
            title: .verbatim(String(state: alert.title)),
            message: alert.message.map { .verbatim(String(state: $0)) },
            systemImage: "exclamationmark.triangle",
            confirmTitle: alert.buttons.first { $0.role != .cancel }
                .map { .verbatim(String(state: $0.label)) } ?? .commonOk
        )
    }

    /// The heading on regular screens, the controls row and the paged grid, wired to the library's focus and
    /// paging.
    var libraryContent: some View {
        VStack(
            alignment: .leading,
            spacing: layout.isCompact
                ? 10
                : 24
        ) {
            Group {
                if !layout.isCompact {
                    heading
                }
                controls
            }
            CloudGameGrid(
                store: store,
                accountID: accountID,
                focus: CloudFocusRelay(binding: $focus),
                interaction: CloudGridInteraction(
                    move: { id, direction in
                        moveGame(id, direction: direction)
                    },
                    appeared: { id in
                        if pendingGameFocus == id {
                            focus = .game(id)
                            pendingGameFocus = nil
                        }
                    },
                    measured: { minX, width in
                        gridMinX = minX
                        gridWidth = width
                    },
                    turn: { pages in
                        turnPage(pages)
                    },
                    hovered: { inside in
                        gridHovered = inside
                    },
                    kept: {
                        keptGameID
                    },
                    movePageBar: movePageBar
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .tint(Palette.accent)
        .onChange(of: showsSamplePreorders) { _, _ in
            store.send(.refresh)
        }
    }
}

extension CloudLibraryView {
    /// Installs the Back handler, which closes the search pop-up first, then leaves the page bar, then returns
    /// to the rail when it is shown, and otherwise asks to quit while a game or header control has focus.
    func registerQuitBackHandler() {
        guard backHandlerID == nil else {
            return
        }
        backHandlerID = navigator?.handlers.registerBack { window in
            if window === hostWindow, store.isSearching {
                store.send(.destination(.dismiss))
                Task { @MainActor in
                    await Task.yield()
                    focus = .search
                }
                return true
            }
            if window === hostWindow, store.selectedGame == nil, leavePageBar() {
                return true
            }
            guard window === hostWindow, QuitBack.available(in: window, navigator: navigator),
                  store.selectedGame == nil,
                  focusAllowsQuit else {
                return false
            }
            if libraryRailShown {
                store.send(.backToRail)
                return true
            }
            requestQuit(.screen)
            return true
        }
    }

    /// Removes the Back handler.
    func unregisterQuitBackHandler() {
        guard let backHandlerID else {
            return
        }
        navigator?.handlers.unregister(backHandlerID)
        self.backHandlerID = nil
    }

    /// Whether Back may leave the library from the focused item, which it may from the games and header
    /// controls only.
    var focusAllowsQuit: Bool {
        switch focus {
        case .game, .filter, .search, .refresh, .platform:
            true
        case .play, .close, .store, .purchaseCode, .addToLibrary, .refreshTitle, .otherVersion, .media,
             .bundleGame, .pageBar, .pageNumber, nil:
            false
        }
    }
}

extension CloudGridMove {
    /// Maps a controller direction onto a grid move.
    ///
    /// - Parameter direction: The direction the controller moved in.
    init?(_ direction: MenuMoveDirection) {
        switch direction {
        case .left:
            self = .left
        case .right:
            self = .right
        case .up:
            self = .up
        case .down:
            self = .down
        @unknown default:
            return nil
        }
    }
}

#if os(macOS)
    extension CloudPageSwipe.Sample {
        /// Classifies a scroll event as the start, end, momentum, trackpad movement or wheel step of a swipe,
        /// using its dominant axis.
        ///
        /// - Parameter event: The scroll wheel event.
        init(_ event: NSEvent) {
            let amount = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? -event.scrollingDeltaX
                : -event.scrollingDeltaY
            if !event.momentumPhase.isEmpty {
                self = .momentum
            } else if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                self = .began
            } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                self = .ended
            } else if event.phase.contains(.changed) {
                self = .moved(amount)
            } else {
                self = .wheel(amount)
            }
        }
    }
#endif

extension CloudLibraryView {
    /// The game whose position the grid keeps when its shape changes: the focused game, or the last focused
    /// one.
    var keptGameID: String? {
        if case .game(let id) = focus {
            return id
        }
        if case .game(let id) = lastFocus {
            return id
        }
        return nil
    }

    /// Turns the grid by pages and moves focus to the matching row on the new page when a card had focus or a
    /// row was given.
    ///
    /// - Parameters:
    ///   - pages: The number of pages to turn, negative to go back.
    ///   - row: The row to land on, or `nil` to use the focused card's row.
    func turnPage(_ pages: Int, row: Int? = nil) {
        let before = store.page
        let focused: Int? =
            if case .game(let id) = focus {
                store.visibleGameIDs.firstIndex(of: id)
            } else {
                nil
            }
        store.send(.turnPage(pages))
        guard store.page != before, row != nil || focused != nil else {
            return
        }
        let shape = store.gridShape
        let games = store.visibleGames
        if let index = CloudGridNavigation.landing(
            row: row ?? (focused ?? 0) / shape.columns, forward: store.page > before, shape: shape,
            count: games.count
        ) {
            focusGame(games[index].id)
        }
    }

    /// Moves controller focus from the page bar: left and right turn pages, faster while held; up returns to
    /// the games; down leaves the library.
    ///
    /// - Parameter direction: The direction the controller moved in.
    func movePageBar(_ direction: MenuMoveDirection) {
        switch direction {
        case .left, .right:
            let forward = direction == .right
            let pages = pageHold.step(forward: forward, at: ProcessInfo.processInfo.systemUptime)
            store.send(.turnPage(forward
                    ? pages
                    : -pages))
        case .up:
            leavePageBar()
        case .down:
            store.send(.leaveContent(.down, fromFilter: false))
        @unknown default:
            break
        }
    }

    /// Leaves the page bar: cancels typing a page number, or returns focus to the games or, when the page is
    /// empty, the filter.
    ///
    /// - Returns: `true` when focus was on the page bar or its number.
    @discardableResult
    func leavePageBar() -> Bool {
        switch focus {
        case .pageNumber:
            store.send(.pageControl(.cancel))
            Task { @MainActor in
                await Task.yield()
                focus = .pageBar
            }
            return true
        case .pageBar:
            let games = store.visibleGames
            guard !games.isEmpty else {
                focus = .filter(store.filter)
                return true
            }
            focusGame(games[min(pageBarReturnIndex, games.count - 1)].id)
            return true
        default:
            return false
        }
    }

    /// Installs the scroll wheel monitor that turns pages while the pointer is over the grid, on macOS.
    func registerPageScroll() {
        #if os(macOS)
            guard scrollMonitor == nil else {
                return
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.window === hostWindow, gridHovered, isEnabled, store.selectedGame == nil,
                      store.pageCount > 1, !(navigator?.inputGate.isBlocking ?? false) else {
                    return event
                }
                if let pages = pageSwipe.turn(for: CloudPageSwipe.Sample(event), at: event.timestamp) {
                    turnPage(pages)
                }
                return nil
            }
        #endif
    }

    /// Removes the scroll wheel monitor.
    func unregisterPageScroll() {
        #if os(macOS)
            guard let scrollMonitor else {
                return
            }
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        #endif
    }
}

/// The cloud library's search field, floating over a dimmed library, focused on appearance and dismissed by
/// Done, submit or a tap outside.
private struct CloudSearchOverlay: View {
    /// The search feature that holds the query and handles Clear and Done.
    @Bindable public var store: StoreOf<CloudSearchFeature>

    /// Creates a cloud search overlay.
    ///
    /// - Parameter store: The search feature that holds the query and handles Clear and Done.
    init(store: StoreOf<CloudSearchFeature>) {
        self.store = store
    }

    var body: some View {
        SearchOverlay(
            prompt: .libraryCloudSearchGames,
            query: $store.query,
            identifier: "cloud-search-overlay"
        ) {
            store.send(.doneTapped)
        }
    }
}
