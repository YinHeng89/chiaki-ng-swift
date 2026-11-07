import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus

/// The direction the cloud library grid last turned its page, which picks the page slide's direction.
public enum CloudPageTurn: Equatable, Sendable {
    /// The grid moved to a later page.
    case forward
    /// The grid moved to an earlier page.
    case backward
}

/// The cloud library: the account's cloud games, the open game detail and the launch hand-off.
///
/// The feature loads the catalog and the recently played history, keeps the grid's tab, platform, query and
/// page, runs the store page check of the game a detail opens on, runs the launch checks and hands a cleared
/// launch to its parent through ``Action/Delegate/play(_:)``. The hand-off runs in the reducer, so it no longer
/// depends on the detail view being on screen. The game detail and the compact search field are presented
/// through ``State/destination``; the website warning is a separate alert shown over the open detail.
@Reducer public struct CloudLibraryFeature {
    /// Where the catalog load is.
    public typealias Phase = CloudLibraryPhase

    /// Whether the tab was chosen by the person or by the library.
    public typealias FilterChoice = CloudLibraryFilterChoice

    /// Where the refresh of one title is.
    public typealias TitleRefresh = CloudTitleRefresh

    /// The notice shown under a title after it was refreshed.
    public typealias TitleNotice = CloudTitleNotice

    /// What the library presents over its grid.
    @Reducer public enum Destination {
        /// The detail of one game.
        case gameDetail(GameDetailFeature)
        /// The full-screen search field.
        case search(CloudSearchFeature)
    }

    /// The cloud library's state.
    @ObservableState public struct State: Equatable {
        /// The account whose library is shown.
        public var accountID: UUID?
        /// Where the catalog load is.
        public var phase: Phase = .idle
        /// The catalog narrowed to the grid's tab, platform, query and page.
        public var listing = CloudLibraryListing()
        /// The search text the grid is narrowed by, as typed in the search field.
        public var query = ""
        /// The load whose recently played history is accepted.
        public var recentAttempt: UUID?
        /// Whether the tab was picked by the person.
        public var filterChoice = FilterChoice.automatic
        /// The store page check of each game, by product id.
        public var cardChecks: [String: CloudCardCheck] = [:]
        /// The launch checks of the open game, if any ran.
        public var launchChecks: CloudLaunchChecks?
        /// The product id of the bundle whose picker is open.
        public var bundlePicker: String?
        /// Where the refresh of one title is.
        public var titleRefresh = TitleRefresh.idle
        /// Whether the Refresh button may reload the library, or how long it waits after the last reload.
        public var libraryRefresh = CloudLibraryRefresh.ready
        /// The notice shown under each refreshed title, by product id.
        public var titleNotice: [String: TitleNotice] = [:]
        /// The titles whose store page was opened to add them to the library.
        public var storeOpened: Set<String> = []
        /// The titles whose store page is being looked up and handed to the browser; their store buttons show
        /// it opening and ignore further presses until it has.
        public var storeOpening: Set<String> = []
        /// What earlier details learned about each game, by product id.
        public var knownDetails: [ProductID: GameDetailFeature.Known] = [:]
        /// The game detail or search field shown over the grid.
        @Presents public var destination: Destination.State?
        /// The warning shown before playing a game the PlayStation website list marks as not streamable.
        @Presents public var websiteWarning: AlertState<Action.WebsiteWarning>?
        /// The grid's measured columns and rows.
        public var gridShape = CloudGridShape.unmeasured
        /// The direction of the last page turn.
        public var pageTurn = CloudPageTurn.forward
        /// The page bar's typing and holding state.
        public var pageControl = CloudPageControl()
        /// A request that focus enter the library's content, waiting for the view to apply it.
        public var contentFocus: LibraryContentFocus?
        /// The stop that last held focus, which the view takes again when it is shown after a stream.
        public internal(set) var heldFocus: CloudLibraryFocus?

        /// Creates an empty library.
        public init() {
        }

        /// The product id of the game whose detail is open.
        ///
        /// Setting it opens or closes the detail without loading it, which is how tests and previews start on
        /// an open game.
        public var selection: String? {
            get {
                detail?.requested?.rawValue
            }
            set {
                guard let newValue else {
                    closeDetail()
                    return
                }
                destination = .gameDetail(GameDetailFeature.State(
                    known: knownDetails,
                    requested: ProductID(rawValue: newValue)
                ))
            }
        }

        /// The open game detail's state.
        public var detail: GameDetailFeature.State? {
            guard case .gameDetail(let detail) = destination else {
                return nil
            }
            return detail
        }

        /// Whether the search field is shown.
        public var isSearching: Bool {
            guard case .search = destination else {
                return false
            }
            return true
        }

        /// Tells whether a title's refresh is running.
        ///
        /// - Parameter game: The title.
        /// - Returns: Whether the refresh of this title is being checked.
        public func isRefreshing(_ game: CloudGame) -> Bool {
            if case .checking(game.id, _) = titleRefresh {
                return true
            }
            return false
        }

        /// The loaded catalog.
        public var snapshot: CloudLibrarySnapshot? {
            get {
                listing.snapshot
            }
            set {
                listing.snapshot = newValue
            }
        }

        /// The tab the grid shows.
        public var filter: CloudLibraryFilter {
            get {
                listing.filter
            }
            set {
                listing.filter = newValue
            }
        }

        /// The platform the grid is narrowed to.
        public var platform: CloudPlatformFilter {
            get {
                listing.platform
            }
            set {
                listing.platform = newValue
            }
        }

        /// The page shown.
        public var page: Int {
            listing.page
        }

        /// The number of pages.
        public var pageCount: Int {
            listing.pageCount
        }

        /// The games on the next page, prefetched before it is shown.
        public var upcomingGames: [CloudGame] {
            listing.games(onPage: listing.page + 1)
        }

        /// The games on the previous page, or none on the first page.
        public var previousGames: [CloudGame] {
            listing.games(onPage: listing.page - 1)
        }

        /// How focus moves across the grid's cards and pages.
        public var gridNavigation: CloudGridNavigation {
            CloudGridNavigation(
                shape: gridShape, count: listing.visible.count, page: listing.page,
                pageCount: listing.pageCount
            )
        }

        /// The listed games before the tab, platform and query narrow them.
        public var listedGames: [CloudGame] {
            listing.listed
        }

        /// The game whose detail is open.
        public var selectedGame: CloudGame? {
            listing.game(selection)
        }

        /// The open bundle's games, or none when the picker is closed.
        public var bundleChoices: [CloudBundleChoice] {
            guard let bundlePicker, let bundle = listing.game(bundlePicker) else {
                return []
            }
            return bundle.bundleChoices(among: snapshot?.games ?? [])
        }

        /// The games matching the tab, platform and query.
        public var matchingGames: [CloudGame] {
            listing.matching
        }

        /// The games on the shown page.
        public var visibleGames: [CloudGame] {
            listing.visible
        }

        /// The product ids of the games on the shown page.
        public var visibleGameIDs: [String] {
            listing.visibleIDs
        }

        /// The tabs shown; Recently played only when there is history to show, and Pre-orders only when a
        /// listed game is still waiting for its release.
        public var filters: [CloudLibraryFilter] {
            CloudLibraryFilter.allCases.filter { filter in
                switch filter {
                case .recent:
                    listing.hasRecentlyPlayed
                case .preorders:
                    listing.hasPreorders
                case .all, .owned, .plus, .browse:
                    true
                }
            }
        }

        /// Whether the title refresh is offered for a game: once its store page was opened here, or at once
        /// where the detail shows a code to add it from a phone.
        ///
        /// - Parameter id: The game's product id.
        /// - Returns: True when a refresh of the title may start.
        public func mayRefreshTitle(_ id: String) -> Bool {
            CloudGameActions.showsStoreCode || storeOpened.contains(id)
        }

        /// What the detail offers for a game.
        ///
        /// - Parameter game: The game the detail shows.
        /// - Returns: The detail's buttons and focus order for the game.
        public func actions(for game: CloudGame) -> CloudGameActions {
            CloudGameActions(
                game: game,
                accountID: accountID,
                check: cardChecks[game.id],
                bundleChoices: bundlePicker == game.id
                    ? bundleChoices
                    : nil,
                titleRefreshIdle: titleRefresh == .idle,
                mayRefreshTitle: mayRefreshTitle(game.id),
                otherVersion: game.otherVersion.flatMap { listing.game($0.productId) }
            )
        }

        /// Shows a page of the grid, clamped to the pages that exist, and records which way the page turned
        /// so the grid slides the right way.
        ///
        /// - Parameter wanted: The page to show, counted from zero.
        public mutating func show(page wanted: Int) {
            let before = listing.page
            listing.show(page: wanted)
            if listing.page != before {
                pageTurn = listing.page > before
                    ? .forward
                    : .backward
            }
        }

        /// Narrows the grid to a search text and shows its first page.
        ///
        /// - Parameter text: The search text.
        public mutating func search(_ text: String) {
            query = text
            listing.query = text
            show(page: 0)
        }

        /// Records a game's store page check and hides the game from the library filters when the check says
        /// it cannot stream.
        ///
        /// - Parameters:
        ///   - check: The check's answer.
        ///   - id: The game's identifier.
        public mutating func note(_ check: CloudCardCheck, for id: String) {
            cardChecks[id] = check
            noteConfirmed()
        }

        /// Recomputes the games hidden from the library filters from the store page checks that refused
        /// streaming.
        public mutating func noteConfirmed() {
            listing.unstreamable = Set(
                cardChecks.filter { $0.value == .notStreamable || $0.value == .refused }.keys
            )
        }

        /// Closes the game detail, keeping the details it learned so reopening the game does not fetch them
        /// again.
        public mutating func closeDetail() {
            if let detail {
                knownDetails.merge(detail.known) { _, learned in
                    learned
                }
            }
            if self.detail != nil {
                destination = nil
            }
        }
    }

    /// What the cloud library can do.
    public enum Action: BindableAction, Equatable {
        /// The query field changed.
        case binding(BindingAction<State>)
        /// The selected account changed; `nil` when no account is selected.
        case account(UUID?)
        /// The Refresh button was pressed.
        case refresh
        /// The library left the screen.
        case stop
        /// A page turn by this many pages was asked for.
        case turnPage(Int)
        /// This page was asked for.
        case showPage(Int)
        /// The grid measured a new shape; the game to keep on screen, if any.
        case gridShape(CloudGridShape, keeping: String?)
        /// The page bar was typed into, held or focused.
        case pageControl(CloudPageControl.Event)
        /// The load with this account and id fetched the catalog.
        case loaded(UUID, UUID, CloudLibrarySnapshot)
        /// The load with this account and id fetched the recently played history.
        case recentlyPlayed(UUID, UUID, [CloudRecentlyPlayed])
        /// The load with this account and id failed.
        case failed(UUID, UUID, CloudLibraryFailure)
        /// The core's fetch for the load with this account and id reached a new state.
        case fetchState(UUID, UUID, CloudLibraryFetchState)
        /// The scheduled release the load with this account and id waited for is due.
        case releaseDue(UUID, UUID)
        /// A tab was picked.
        case filter(CloudLibraryFilter)
        /// A platform was picked.
        case platform(CloudPlatformFilter)
        /// The search button was pressed on a compact screen.
        case searchTapped
        /// Focus is asked to enter the cloud content.
        case focusRequested(LibraryContentFocus)
        /// The view applied the pending content focus.
        case contentFocusHandled
        /// A stop of the library took focus.
        case focusMoved(CloudLibraryFocus)
        /// Focus left the cloud content in a direction, from a filter chip or another control.
        case leaveContent(MenuMoveDirection, fromFilter: Bool)
        /// Back asked for the rail.
        case backToRail
        /// A game was opened, or the detail was closed with `nil`.
        case select(String?)
        /// The detail's Close button was pressed.
        case closeTapped
        /// The Refresh button under a title added in the store was pressed.
        case refreshTitle(String)
        /// The store page check started for this account and product finished.
        case cardChecked(UUID, String, CloudCardCheck)
        /// The store page check for this account and game said whether the store still offers the account a
        /// trial of it.
        case trialChecked(UUID, String, Bool)
        /// The play button was pressed.
        case checkAndPlay(CloudLaunchRequest)
        /// The play button of a bundle was pressed.
        case openBundlePicker(String)
        /// A game in the open bundle picker was chosen.
        case playBundleGame(String)
        /// The launch checks with this id reported an event.
        case launchChecked(UUID, CloudLaunchClearanceEvent)
        /// A store page button was pressed.
        case storePageTapped(String)
        /// The add to library button was pressed.
        case addToLibraryTapped(String)
        /// The store page of this title, looked up for this account, was handed to the browser, or could not be.
        case storePageOpened(UUID?, String)
        /// The title refresh with this account and id finished.
        case titleRefreshed(UUID, UUID, CloudTitleRefreshOutcome)
        /// The cooldown after the title refresh with this id ended.
        case titleRefreshCooled(UUID)
        /// The cooldown of the library refresh started by the load with this id was read from the developer
        /// settings.
        case libraryRefreshCooldownRead(UUID, Duration)
        /// The cooldown after the library refresh started by the load with this id ended.
        case libraryRefreshCooled(UUID)
        /// The game detail or search field acted.
        case destination(PresentationAction<Destination.Action>)
        /// The website warning was answered.
        case websiteWarning(PresentationAction<WebsiteWarning>)
        /// Tells the parent about a cleared launch.
        case delegate(Delegate)

        /// The website warning's button.
        @CasePathable public enum WebsiteWarning: Equatable, Sendable {
            /// Play anyway, as the store page allows.
            case play
        }

        /// What the library reports to its parent.
        @CasePathable public enum Delegate: Equatable, Sendable {
            /// The launch checks cleared this request; the parent starts the stream.
            case play(CloudLaunchRequest)
            /// Focus left the cloud content in a direction, from a filter chip or another control.
            case leftContent(MenuMoveDirection, fromFilter: Bool)
            /// Back asks to move focus to the rail.
            case backToRail
        }
    }

    /// How long a finished title refresh blocks the next one.
    public static let titleRefreshCooldown = Duration.seconds(20)

    /// How long history may lag behind the catalog and still open the library on Recently played.
    public static let historyWait = Duration.seconds(2)

    /// How long after a scheduled release the library reloads, so the cloud catalog has unlocked the title.
    public static let unlockMargin = Duration.seconds(5)

    /// How long the store page lookup may take before the button opens the catalog's own store page.
    public static let storePageWait = Duration.seconds(5)

    /// Creates the feature.
    public init() {
    }

    /// Runs the library through its browsing, loading, launching and title refresh reducers.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        CombineReducers {
            CloudLibraryBrowsing()
            CloudLibraryLoader()
            CloudLibraryLauncher()
            CloudTitleRefresher()
        }
        .ifLet(\.$destination, action: \.destination)
        .ifLet(\.$websiteWarning, action: \.websiteWarning)
    }
}

extension CloudLibraryFeature.Destination.State: Equatable {}
extension CloudLibraryFeature.Destination.Action: Equatable {}

/// Where the cloud library's catalog load is.
public enum CloudLibraryPhase: Equatable, Sendable {
    /// Nothing has been asked for.
    case idle
    /// The load with this id is running, with the latest state the core reported for its fetch, if any.
    case loading(UUID, fetch: CloudLibraryFetchState?)
    /// The catalog is shown.
    case ready
    /// The catalog could not be loaded.
    case failed(CloudLibraryFailure)

    /// The id of the running load, or `nil` when no load is running.
    public var loadingAttempt: UUID? {
        guard case .loading(let attempt, _) = self else {
            return nil
        }
        return attempt
    }

    /// The words the loading view shows for the core's fetch, or `nil` when no fetch line is shown.
    public var fetchProgress: CloudLibraryFetchProgress? {
        guard case .loading(_, let fetch?) = self else {
            return nil
        }
        return CloudLibraryFetchProgress(fetch)
    }
}

/// Where the cloud library's refresh of one title is.
public enum CloudTitleRefresh: Equatable, Sendable {
    /// No refresh is running.
    case idle
    /// The title with this product id is being checked by the refresh with this id.
    case checking(String, UUID)
    /// The refresh with this id finished; another can start at the time given, after
    /// ``CloudLibraryFeature/titleRefreshCooldown``.
    case coolingDown(UUID, until: Date)

    /// When the next refresh may start, or `nil` when none is waiting for a cooldown.
    public var availableAt: Date? {
        guard case .coolingDown(_, let until) = self else {
            return nil
        }
        return until
    }
}

/// Whether the cloud library's Refresh button may reload the library.
public enum CloudLibraryRefresh: Equatable, Sendable {
    /// A refresh may start.
    case ready
    /// The refresh started by the load with this id blocks the next one until the time given, or for an
    /// unknown time while the cooldown is read from the developer settings.
    case coolingDown(UUID, until: Date?)

    /// Whether a refresh may start.
    public var isReady: Bool {
        self == .ready
    }

    /// When the next refresh may start, or `nil` when one may start now or the time is not known yet.
    public var availableAt: Date? {
        guard case .coolingDown(_, let until) = self else {
            return nil
        }
        return until
    }
}

/// The notice the cloud library shows under a title after it was refreshed.
public enum CloudTitleNotice: Equatable, Sendable {
    /// The title is now in the library.
    case added
    /// The title is still not in the library.
    case notInLibrary
    /// The refresh failed, with the message to show.
    case failed(LocalizedStringResource)

    /// The notice's text.
    public var message: LocalizedStringResource {
        switch self {
        case .added:
            .libraryTitleNoticeAdded
        case .notInLibrary:
            .libraryTitleNoticeNotInLibrary
        case .failed(let message):
            message
        }
    }
}

/// Whether the cloud library's tab was chosen by the person or by the library.
public enum CloudLibraryFilterChoice: Equatable, Sendable {
    /// The library may switch to Recently played once history arrives.
    case automatic
    /// The person picked a tab, so the library keeps it.
    case picked
}

/// The work of the cloud library that a later request or leaving the library cancels.
enum CloudLibraryCancelID {
    /// The catalog and history load.
    case load

    /// The refresh of one title.
    case title

    /// The cooldown after a title refresh.
    case cooldown

    /// The cooldown after a library refresh.
    case libraryCooldown

    /// The launch checks of the open game.
    case launchChecks

    /// The store page checks of the opened games.
    case cardChecks

    /// The wait for the next scheduled release.
    case unlock
}

/// Moves through the cloud library: the search text, the tab and platform, the grid's pages and shape, focus
/// entering and leaving the content, and opening and closing a game's detail.
///
/// Opening a game starts its store page check, closing it first shrinks enlarged media or closes the bundle
/// picker, and choosing another game stops the launch checks of the one before.
private struct CloudLibraryBrowsing: Reducer {
    /// The cloud library's state.
    typealias State = CloudLibraryFeature.State

    /// What the cloud library can do.
    typealias Action = CloudLibraryFeature.Action

    /// Reacts to searching, paging, focus and the detail being opened or closed.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                state.search(state.query)
                return .none
            case .destination(.presented(.search(.delegate(.queryChanged(let query))))):
                state.search(query)
                return .none
            case .searchTapped:
                state.destination = .search(CloudSearchFeature.State(query: state.query))
                return .none
            case .turnPage, .showPage, .gridShape, .pageControl, .filter, .platform:
                Self.page(action, state: &state)
                return .none
            case .focusRequested, .contentFocusHandled, .focusMoved, .leaveContent, .backToRail:
                return Self.focus(action, state: &state)
            case .select(let id):
                return select(&state, id)
            case .closeTapped:
                return closeTapped(&state)
            default:
                return .none
            }
        }
    }

    private static func page(_ action: Action, state: inout State) {
        switch action {
        case .turnPage(let pages):
            state.show(page: state.page + pages)
        case .showPage(let page):
            state.show(page: page)
        case let .gridShape(shape, keeping):
            guard shape != state.gridShape else {
                return
            }
            state.gridShape = shape
            state.listing.resize(to: shape.size, keeping: keeping ?? state.selection)
        case .pageControl(let event):
            if let page = state.pageControl.handle(event, pageCount: state.pageCount) {
                state.show(page: page)
            }
        case .filter(let filter):
            state.filterChoice = .picked
            state.filter = filter
            state.show(page: 0)
        case .platform(let platform):
            state.platform = platform
            state.show(page: 0)
        default:
            return
        }
    }

    private static func focus(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case .focusRequested(let request):
            state.contentFocus = request
            return .none
        case .contentFocusHandled:
            state.contentFocus = nil
            return .none
        case .focusMoved(let focus):
            state.heldFocus = focus
            return .none
        case let .leaveContent(direction, fromFilter):
            return .send(.delegate(.leftContent(direction, fromFilter: fromFilter)))
        case .backToRail:
            return .send(.delegate(.backToRail))
        default:
            return .none
        }
    }

    private func select(_ state: inout State, _ id: String?) -> Effect<Action> {
        let wanted = state.listing.game(id)
        if state.bundlePicker != wanted?.id {
            state.bundlePicker = nil
        }
        let stopChecks = state.launchChecks.map { $0.gameID != wanted?.id } == true
            ? CloudLibraryLauncher.stopLaunchChecks(&state)
            : .none
        guard let game = wanted else {
            state.closeDetail()
            return stopChecks
        }
        if state.selection != game.id {
            state.closeDetail()
            state.destination = .gameDetail(
                GameDetailFeature.State(known: state.knownDetails, requested: game.product)
            )
        }
        guard let product = game.product else {
            return .merge(stopChecks, CloudLibraryLoader().runCardCheck(&state, game: game))
        }
        return .merge(
            stopChecks,
            .send(.destination(.presented(.gameDetail(.open(state.accountID, product))))),
            CloudLibraryLoader().runCardCheck(&state, game: game)
        )
    }

    private func closeTapped(_ state: inout State) -> Effect<Action> {
        guard let game = state.selectedGame else {
            return select(&state, nil)
        }
        if state.detail?.viewed(for: game.product) != nil {
            state.destination?.modify(\.gameDetail) { detail in
                detail.media = .idle
            }
            return .none
        }
        if state.bundlePicker == game.id {
            state.bundlePicker = nil
            guard let checks = state.launchChecks, checks.gameID == game.id, checks.phase != .launched else {
                return .none
            }
            return CloudLibraryLauncher.stopLaunchChecks(&state)
        }
        return select(&state, nil)
    }
}

/// Opens a game's store page, and refreshes a title the person added to the library there.
///
/// Only a title whose store page was opened to add it can be refreshed. One refresh runs at a time, and a
/// finished refresh blocks the next one for ``CloudLibraryFeature/titleRefreshCooldown``.
private struct CloudTitleRefresher: Reducer {
    /// The cloud library's state.
    typealias State = CloudLibraryFeature.State

    /// What the cloud library can do.
    typealias Action = CloudLibraryFeature.Action

    @Dependency(\.catalog) private var catalog
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date) private var date
    @Dependency(\.logger) private var logger
    @Dependency(\.openURL) private var openURL
    @Dependency(\.uuid) private var uuid

    /// Reacts to the store page buttons and the title refresh's answers.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refreshTitle(let id):
                guard state.mayRefreshTitle(id) else {
                    return .none
                }
                return refreshTitle(&state, id: id)
            case .storePageTapped(let id):
                return openStore(&state, id: id)
            case .addToLibraryTapped(let id):
                state.storeOpened.insert(id)
                return openStore(&state, id: id)
            case let .storePageOpened(account, id):
                guard state.accountID == account else {
                    return .none
                }
                state.storeOpening.remove(id)
                return .none
            case .titleRefreshed(let account, let attempt, let outcome):
                return titleRefreshed(&state, account: account, attempt: attempt, outcome: outcome)
            case .titleRefreshCooled(let attempt):
                guard case .coolingDown(attempt, _) = state.titleRefresh else {
                    return .none
                }
                state.titleRefresh = .idle
                state.titleNotice = state.titleNotice.filter {
                    $0.value != .added
                }
                return .none
            default:
                return .none
            }
        }
    }

    private func openStore(_ state: inout State, id: String) -> Effect<Action> {
        guard !state.storeOpening.contains(id) else {
            return .none
        }
        guard let game = state.listing.game(id) else {
            return .run { [logger] _ in
                await logger.log(.diagnostic(
                    .cloudLibrary,
                    .warning,
                    "Store page for \(id) not opened: the game is not listed"
                ))
            }
        }
        let account = state.accountID
        let fallback = CloudGameActions.storeURL(game.conceptUrl)
        state.storeOpening.insert(id)
        return .run { send in
            await open(game, account: account, fallback: fallback)
            await send(.storePageOpened(account, id))
        }
    }

    private func open(_ game: CloudGame, account: UUID?, fallback: URL?) async {
        var resolved: URL?
        if let account, let product = game.product {
            resolved = await withTaskGroup(of: URL?.self) { group in
                group.addTask { [catalog] in
                    await catalog.storePage(account, product)
                }
                group.addTask { [clock] in
                    try? await clock.sleep(for: CloudLibraryFeature.storePageWait)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
        }
        guard let url = resolved.flatMap({ CloudGameActions.storeURL($0.absoluteString) }) ?? fallback else {
            await logger.log(.diagnostic(
                .cloudLibrary,
                .warning,
                "Store page for \(game.productId) not opened: no store page is known"
            ))
            return
        }
        let opened = await openURL(url)
        let source = resolved == nil
            ? "from the catalog"
            : "from the store"
        let outcome = opened
            ? "opened"
            : "could not be opened"
        await logger.log(.diagnostic(
            .cloudLibrary,
            opened
                ? .info
                : .warning,
            "Store page for \(game.productId) \(source) \(outcome)"
        ))
    }

    private func refreshTitle(_ state: inout State, id: String) -> Effect<Action> {
        guard state.titleRefresh == .idle, let account = state.accountID, state.snapshot != nil,
              let game = state.listing.game(id), game.canBeAddedToLibrary else {
            return .none
        }
        let attempt = uuid()
        state.titleRefresh = .checking(id, attempt)
        state.titleNotice[id] = nil
        return .run { [catalog] send in
            let outcome = await catalog.refreshTitle(account, game)
            await send(.titleRefreshed(account, attempt, outcome))
        }
        .cancellable(id: CloudLibraryCancelID.title, cancelInFlight: true)
    }

    private func titleRefreshed(
        _ state: inout State, account: UUID, attempt: UUID, outcome: CloudTitleRefreshOutcome
    ) -> Effect<Action> {
        guard state.accountID == account, case .checking(let id, attempt) = state.titleRefresh else {
            return .none
        }
        let seconds = TimeInterval(CloudLibraryFeature.titleRefreshCooldown.components.seconds)
        state.titleRefresh = .coolingDown(attempt, until: date.now.addingTimeInterval(seconds))
        switch outcome {
        case .owned(let game):
            if let snapshot = state.snapshot, game.id == id, snapshot.games.contains(where: { $0.id == id }) {
                state.snapshot = snapshot.replacing(game)
                state.titleNotice[id] = .added
                if state.selection != nil, state.selectedGame == nil {
                    state.closeDetail()
                }
                CloudLibraryLoader.settleFilter(&state, choosing: false)
            } else {
                state.titleNotice[id] = .failed(.libraryTitleNoticeLibraryChanged)
            }
        case .notOwned:
            state.titleNotice[id] = .notInLibrary
        case .failed(let failure):
            state.titleNotice[id] = .failed(failure.message)
        }
        let cooldown = Effect<Action>.run { [clock] send in
            try await clock.sleep(for: CloudLibraryFeature.titleRefreshCooldown)
            await send(.titleRefreshCooled(attempt))
        }
        .cancellable(id: CloudLibraryCancelID.cooldown, cancelInFlight: true)
        guard case .owned = outcome, state.titleNotice[id] == .added, let load = state.recentAttempt else {
            return cooldown
        }
        return .merge(cooldown, .send(.releaseDue(account, load)))
    }
}
