import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus

/// The library screen: the section shown, the features that run while it is on screen, the account sheet and
/// the focus hand-offs between its parts.
///
/// The accounts, the console catalog and the selected account outlive the screen, so the app owns them and
/// the library reads them through `@Shared`. The app also publishes what it is doing with them
/// (``State/activity``) and the recently played titles and console art it loads (``State/recentlyPlayed``,
/// ``State/consoleArt``). The screen sends one lifecycle action for each change it sees (``Action/task``,
/// ``Action/scenePhaseChanged(_:)``, ``Action/disappeared``), and the feature starts and stops discovery, the
/// cloud status, the cloud library and the recently played titles from them; views never drive those
/// directly. Everything the library asks of the app leaves through ``Action/Delegate``.
@Reducer public struct LibraryFeature {
    /// Whether the app is in the foreground.
    public enum ScenePhase: Equatable, Sendable {
        /// The app is active; the library's features run.
        case active
        /// The app is in the background or the screen is gone; the library's features are stopped.
        case inactive
    }

    /// The library's state.
    @ObservableState public struct State: Equatable {
        /// The section shown.
        public var section: LibrarySection
        /// Whether the library's features run.
        public var scenePhase = ScenePhase.inactive
        /// The account the library is shown for.
        @SharedReader(.selectedAccount) public var selectedAccount
        /// The saved accounts.
        @SharedReader(.accounts) public var accounts
        /// The paired consoles of every account.
        @SharedReader(.consoleCatalog) public var consoleCatalog
        /// Nearby consoles, as the root's discovery reports them.
        public internal(set) var discovery = LibraryDiscovery.idle
        /// The selected account's cloud status.
        public var cloudStatus = CloudStatusFeature.State()
        /// The selected account's cloud games.
        public var cloudLibrary = CloudLibraryFeature.State()
        /// The selected account's trophies.
        public var trophies = TrophiesFeature.State()
        /// What the app is doing with the accounts and consoles.
        public var activity = LibraryActivity()
        /// Whether the shelf waits for the console catalog.
        public var consoleLoad = ConsoleShelfLoad.loaded
        /// The recently played titles the app loaded for the selected account.
        public var recentlyPlayed = RecentlyPlayedReducer.State()
        /// The layered art the app loaded for the console cards.
        public var consoleArt = ConsoleArtReducer.State()
        /// The recently played selection last asked of the app, so it is asked again only when it changes.
        public var recentlyPlayedShown: RecentlyPlayedReducer.Selection?
        /// A focus hand-off waiting for the screen to apply it.
        var focusRequest: LibraryFocusRequest?
        /// The stop that last held focus, which the screen takes again when it is shown after a stream.
        public internal(set) var heldFocus: ConsoleLibraryFocus?
        /// The account sheet, when it is open.
        @Presents public var accountSheet: LibraryAccountSheetFeature.State?
        /// What PSN tells the selected account as it happens, listed in the Notifications panel.
        public var alerts = PSNAlertsFeature.State()
        /// The alerts shown over the library while no stream runs.
        public var toasts = CloudToastsReducer.State()

        /// Creates the library.
        ///
        /// - Parameter section: The section shown first.
        public init(
            section: LibrarySection = ProcessInfo.processInfo.arguments.contains("--show-cloud")
                ? .cloud
                : .consoles
        ) {
            self.section = section
        }

        /// The account the library is shown for.
        public var selectedProfile: RegistrationFlow.Profile? {
            accounts.first { $0.id == selectedAccount }
        }

        /// The consoles paired with the selected account.
        public var linkedConsoles: [RegistrationFlow.ConsoleTarget] {
            consoleCatalog.filter { $0.profileID == selectedAccount }.map(\.console)
        }

        /// The selected account's PS5s that can join a party through PSN, as the Notifications panel offers them;
        /// none when the account may not reach its consoles through PSN.
        public var partyConsoles: [PSNAlertsFeature.PartyConsole] {
            guard selectedProfile.permits(.psnConsoles) else {
                return []
            }
            return linkedConsoles.compactMap { console in
                guard console.kind == .ps5, let hex = console.hardwareID,
                      let hardwareID = HardwareID(hex: hex) else {
                    return nil
                }
                return PSNAlertsFeature.PartyConsole(
                    hardwareID: hardwareID,
                    name: console.name ?? console.address
                )
            }
        }

        /// The cloud game a game invitation can be played with: a listed game the account can stream for the
        /// invitation's title, the PS5 version for a SessionManager session and the PS4 version on PS Now for an old
        /// NP session.
        ///
        /// - Parameter invitation: The invitation.
        /// - Returns: The game, or `nil` when the cloud library lists none or the account cannot stream.
        public func cloudGame(joining invitation: CloudGameInvitation) -> CloudGame? {
            guard invitation.kind == .game, !cloudUnavailable else {
                return nil
            }
            let candidates = cloudLibrary.listing.listed.filter { game in
                !game.isStoreOnly && !game.isBundle && game.launchRefusal == nil
                    && ProductID(rawValue: game.productId).map(invitation.isFor) == true
            }
            let wantsPS5 = CloudInvitationsFeature.joinsByGameIntent(invitation)
            return candidates.first {
                ($0.platform.lowercased() == "ps5") == wantsPS5
            } ?? candidates.first
        }

        /// The Notifications entries whose game invitation can be played in the cloud.
        public var cloudPlayableAlerts: Set<String> {
            Set(alerts.items.compactMap { item in
                guard case .invitation(let invitation) = item.kind, invitation.joining == .joinable,
                      cloudGame(joining: invitation) != nil else {
                    return nil
                }
                return item.id
            })
        }

        /// Whether the cloud section cannot be shown for the selected account.
        public var cloudUnavailable: Bool {
            !selectedProfile.permits(.cloud) || cloudStatus.unavailable(for: selectedAccount)
        }

        /// The sections the selected account can show.
        public var availableSections: [LibrarySection] {
            LibrarySection.allCases.filter { selectedProfile.permits($0.feature) }
        }

        /// Whether the account details are being refreshed.
        public var isRefreshing: Bool {
            activity.refresh == .refreshing
        }

        /// Whether the selected account must sign in again.
        public var needsSignIn: Bool {
            selectedAccount.map(activity.signInNeeded.contains) ?? false
        }

        /// Whether a status line above the shelf has a button.
        public var hasStatusAction: Bool {
            needsSignIn || activity.refresh == .failed
        }

        /// Whether the console cards may start anything.
        public var consolesBusy: Bool {
            activity.consoleOperation == .busy
        }

        /// The recently played titles the library asks for, or `nil` when no account is selected.
        public var recentlyPlayedSelection: RecentlyPlayedReducer.Selection? {
            guard let profile = selectedProfile else {
                return nil
            }
            return RecentlyPlayedReducer.Selection(
                profileID: profile.id,
                eligible: selectedProfile.permits(.psnConsoles) && linkedConsoles.contains { $0.kind == .ps5 }
            )
        }

        /// The recently played rows shown below the shelf.
        ///
        /// - Parameter continuing: The consoles whose card already shows their last title.
        /// - Returns: The rows with titles, in console order.
        func recentRows(continuing: Set<UUID>) -> [RecentlyPlayedSection.Row] {
            RecentlyPlayedSection.rows(recentlyPlayed, consoles: linkedConsoles, continuing: continuing)
                .filter {
                    $0.titles?.isEmpty == false
                }
        }

        /// The title last played on a console.
        ///
        /// - Parameter consoleID: The console's id.
        /// - Returns: The title, or `nil` when none is known.
        func lastPlayed(on consoleID: UUID?) -> RecentTitle? {
            recentlyPlayed.rail(for: consoleID)?.titles.first
        }

        /// The rail for the selected account.
        ///
        /// - Parameters:
        ///   - edge: The window edge the rail sits on.
        ///   - showsQuit: Whether the rail ends with Quit.
        ///   - showsLog: Whether the rail has a live log stop after Settings.
        /// - Returns: The rail's stops.
        func rail(edge: LibraryRailEdge, showsQuit: Bool, showsLog: Bool = false) -> LibraryRail {
            LibraryRail(
                edge: edge,
                sections: availableSections,
                unavailableSections: cloudUnavailable
                    ? [.cloud]
                    : [],
                showsQuit: showsQuit,
                showsLog: showsLog
            )
        }
    }

    /// What the library can do.
    public enum Action: Equatable {
        /// The screen appeared; the library follows the selected account until it disappears.
        case task
        /// The app moved to or from the foreground.
        case scenePhaseChanged(ScenePhase)
        /// The screen disappeared.
        case disappeared
        /// The app selected another account.
        case selectedAccountChanged(UUID?)
        /// The app's accounts or console catalog changed.
        case catalogChanged
        /// The accounts were refreshed, so the cloud status is read again.
        case accountsRefreshed
        /// The app's activity changed.
        case activityChanged(LibraryActivity)
        /// The shelf waited for the console catalog long enough.
        case consoleLoadElapsed
        /// A section was chosen.
        case sectionSelected(LibrarySection)
        /// Focus is asked to enter the shown section's content.
        case contentFocusRequested(LibraryContentFocus)
        /// The screen moved focus, so the pending request is done.
        case focusRequestHandled
        /// A stop of the screen took focus.
        case focusMoved(ConsoleLibraryFocus)
        /// The rail's account stop was activated.
        case accountTapped
        /// The account sheet acted.
        case accountSheet(PresentationAction<LibraryAccountSheetFeature.Action>)
        /// The Notifications stop was activated.
        case alertsTapped
        /// The Notifications panel closed.
        case alertsPanelClosed
        /// The account's alerts acted.
        case alerts(PSNAlertsFeature.Action)
        /// The alert toasts over the library acted.
        case toasts(CloudToastsReducer.Action)
        /// Something was asked of the app.
        case requested(LibraryRequest)
        /// The root's discovery sees these consoles now.
        case discoveryUpdated(DiscoverySnapshot)

        /// Whether the scan has listened long enough that a console it does not see is away changed.
        case discoverySearched(Bool)
        /// The root's discovery stopped.
        case discoveryFailed
        /// The cloud status acted.
        case cloudStatus(CloudStatusFeature.Action)
        /// The cloud library acted.
        case cloudLibrary(CloudLibraryFeature.Action)
        /// The trophies section acted.
        case trophies(TrophiesFeature.Action)
        /// What the library tells the app.
        case delegate(Delegate)

        /// What the library tells the app.
        @CasePathable public enum Delegate: Equatable {
            /// The library asks the app to do something.
            case requested(LibraryRequest)
            /// The library needs the root's discovery and holds its lease.
            case acquireDiscovery
            /// The library no longer needs the root's discovery.
            case releaseDiscovery
            /// The library shows these recently played titles; `nil` when no account is selected.
            case showRecentlyPlayed(RecentlyPlayedReducer.Selection?)
            /// An alert should show in the running stream, when there is one.
            case showAlert(CloudSystemNotice)
        }
    }

    /// Takes in what the rest of the app is doing that the library reflects.
    ///
    /// The root calls this directly whenever its mirrored activity changes, so the library follows in the same
    /// reduction.
    ///
    /// - Parameters:
    ///   - activity: The activity now.
    ///   - state: The library's state.
    /// - Returns: The effects that follow the catalog and report a finished account refresh.
    public func changeActivity(to activity: LibraryActivity, state: inout State) -> Effect<Action> {
        let finished = state.activity.refresh == .refreshing && activity.refresh == .idle
        state.activity = activity
        return .merge(
            LibraryCatalogWait().follow(&state),
            finished
                ? .send(.accountsRefreshed)
                : .none
        )
    }

    /// Creates the feature.
    public init() {
    }

    /// Runs the library.
    public var body: some ReducerOf<Self> {
        Scope(state: \.cloudStatus, action: \.cloudStatus) {
            CloudStatusFeature()
        }
        Scope(state: \.cloudLibrary, action: \.cloudLibrary) {
            CloudLibraryFeature()
        }
        Scope(state: \.trophies, action: \.trophies) {
            TrophiesFeature()
        }
        Scope(state: \.alerts, action: \.alerts) {
            PSNAlertsFeature()
        }
        Scope(state: \.toasts, action: \.toasts) {
            CloudToastsReducer()
        }
        CombineReducers {
            LibraryFocusRelay()
            LibraryCatalogWait()
            LibraryDiscoveryRelay()
            Reduce { state, action in
                switch action {
                case .task:
                    state.focusRequest = state.heldFocus.map(LibraryFocusRequest.resume) ?? .firstConsole
                    return .merge(
                        .publisher {
                            state.$selectedAccount.publisher.map(Action.selectedAccountChanged)
                        },
                        .publisher {
                            state.$consoleCatalog.publisher.map { _ in Action.catalogChanged }
                        },
                        .publisher {
                            state.$accounts.publisher.map { _ in Action.catalogChanged }
                        }
                    )
                case .scenePhaseChanged(let phase):
                    guard phase != state.scenePhase else {
                        return .none
                    }
                    state.scenePhase = phase
                    return phase == .active
                        ? start(&state)
                        : stop(&state)
                case .disappeared:
                    state.scenePhase = .inactive
                    return stop(&state)
                case .selectedAccountChanged:
                    return followAccount(&state)
                case .catalogChanged:
                    return showRecentlyPlayed(&state)
                case .accountsRefreshed:
                    guard state.scenePhase == .active, let account = state.selectedAccount else {
                        return .none
                    }
                    return .send(.cloudStatus(.select(account)))
                case .activityChanged(let activity):
                    return changeActivity(to: activity, state: &state)
                case .sectionSelected(let section):
                    guard section != state.section, section != .cloud || !state.cloudUnavailable else {
                        return .none
                    }
                    state.section = section
                    return showSection(&state)
                case .requested(.refreshAccounts):
                    return .merge(
                        .send(.delegate(.requested(.refreshAccounts))),
                        .send(.cloudStatus(.refresh))
                    )
                case .requested(let request):
                    return .send(.delegate(.requested(request)))
                case .cloudStatus:
                    return leaveUnavailableSection(&state)
                case .consoleLoadElapsed, .contentFocusRequested, .focusMoved, .focusRequestHandled,
                     .accountTapped, .alertsTapped, .alertsPanelClosed, .alerts, .toasts,
                     .accountSheet, .discoveryUpdated, .discoverySearched, .discoveryFailed, .cloudLibrary,
                     .trophies, .delegate:
                    return .none
                }
            }
        }
        .ifLet(\.$accountSheet, action: \.accountSheet) {
            LibraryAccountSheetFeature()
        }
    }

    private func start(_ state: inout State) -> Effect<Action> {
        .merge(LibraryDiscoveryRelay.acquire(&state), followStatus(state), showSection(&state))
    }

    private func stop(_ state: inout State) -> Effect<Action> {
        state.recentlyPlayedShown = nil
        return .merge(
            LibraryDiscoveryRelay.release(&state),
            .send(.cloudStatus(.stop)),
            .send(.cloudLibrary(.stop)),
            .send(.trophies(.show(nil)))
        )
    }

    private func followAccount(_ state: inout State) -> Effect<Action> {
        guard state.scenePhase == .active else {
            return .none
        }
        return .merge(followStatus(state), showSection(&state), leaveUnavailableSection(&state))
    }

    private func followStatus(_ state: State) -> Effect<Action> {
        guard let account = state.selectedAccount else {
            return .send(.cloudStatus(.stop))
        }
        return .concatenate(.send(.cloudStatus(.select(account))), .send(.cloudStatus(.watch)))
    }

    private func showSection(_ state: inout State) -> Effect<Action> {
        guard state.scenePhase == .active else {
            return .none
        }
        switch state.section {
        case .cloud:
            state.recentlyPlayedShown = nil
            return .merge(
                .send(.trophies(.show(nil))),
                .send(.cloudLibrary(.account(state.selectedAccount)))
            )
        case .consoles:
            return .merge(
                .send(.cloudLibrary(.stop)),
                .send(.trophies(.show(nil))),
                showRecentlyPlayed(&state, again: true)
            )
        case .trophies:
            state.recentlyPlayedShown = nil
            return .merge(
                .send(.cloudLibrary(.stop)),
                .send(.trophies(.show(state.selectedAccount.map(ProfileID.init(uuid:)))))
            )
        }
    }

    private func showRecentlyPlayed(_ state: inout State, again: Bool = false) -> Effect<Action> {
        guard state.scenePhase == .active, state.section == .consoles else {
            return .none
        }
        let selection = state.recentlyPlayedSelection
        guard again || selection != state.recentlyPlayedShown else {
            return .none
        }
        state.recentlyPlayedShown = selection
        return .send(.delegate(.showRecentlyPlayed(selection)))
    }

    private func leaveUnavailableSection(_ state: inout State) -> Effect<Action> {
        let unavailable = switch state.section {
        case .cloud:
            state.cloudUnavailable
        case .trophies:
            !state.selectedProfile.permits(.trophies)
        case .consoles:
            false
        }
        guard unavailable else {
            return .none
        }
        state.section = .consoles
        return .merge(
            .send(.cloudLibrary(.stop)),
            .send(.trophies(.show(nil))),
            showRecentlyPlayed(&state, again: true)
        )
    }
}

/// What the library sees of the root's local-network discovery while it holds the
/// `DiscoveryLease.library` lease.
public enum LibraryDiscovery: Equatable, Sendable {
    /// The library holds no lease.
    case idle

    /// The library holds the lease and the scan sees these consoles.
    case watching(DiscoverySnapshot)

    /// The scan sees these consoles and has listened long enough that a console it does not see is away.
    case searched(DiscoverySnapshot)

    /// The library holds the lease but the scan stopped; these are the consoles it last saw.
    case failed(DiscoverySnapshot)

    /// The consoles the scan last reported, empty while idle.
    public var snapshot: DiscoverySnapshot {
        switch self {
        case .idle:
            DiscoverySnapshot()
        case .watching(let snapshot), .searched(let snapshot), .failed(let snapshot):
            snapshot
        }
    }

    /// Whether a console the scan does not see is known to be away.
    public var hasSearched: Bool {
        if case .searched = self {
            return true
        }
        return false
    }

    /// Whether the library asked for the scan.
    public var isRequested: Bool {
        self != .idle
    }
}

/// Holds the library's lease on the root's discovery and follows what it reports.
///
/// The library asks for discovery once while it runs and gives it back when it stops. Reports that arrive
/// while the library holds no lease are ignored.
private struct LibraryDiscoveryRelay: Reducer {
    /// The library's state.
    typealias State = LibraryFeature.State

    /// What the library can do.
    typealias Action = LibraryFeature.Action

    /// Reacts to the root's discovery reports.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard state.discovery.isRequested else {
                return .none
            }
            switch action {
            case .discoveryUpdated(let snapshot):
                state.discovery = state.discovery.hasSearched
                    ? .searched(snapshot)
                    : .watching(snapshot)
            case .discoverySearched(let searched):
                let snapshot = state.discovery.snapshot
                state.discovery = searched
                    ? .searched(snapshot)
                    : .watching(snapshot)
            case .discoveryFailed:
                state.discovery = .failed(state.discovery.snapshot)
            default:
                break
            }
            return .none
        }
    }

    /// Takes a lease on the root's discovery unless the library holds one.
    ///
    /// - Parameter state: The library's state.
    /// - Returns: The effect that asks the app for discovery, or none.
    static func acquire(_ state: inout State) -> Effect<Action> {
        guard !state.discovery.isRequested else {
            return .none
        }
        state.discovery = .watching(DiscoverySnapshot())
        return .send(.delegate(.acquireDiscovery))
    }

    /// Gives back the library's lease on the root's discovery.
    ///
    /// - Parameter state: The library's state.
    /// - Returns: The effect that tells the app, or none when the library held no lease.
    static func release(_ state: inout State) -> Effect<Action> {
        guard state.discovery.isRequested else {
            return .none
        }
        state.discovery = .idle
        return .send(.delegate(.releaseDiscovery))
    }
}

/// Routes the library's focus hand-offs and runs its account sheet.
///
/// Focus asked into the content goes to the cloud library or to the first console card. Closing the account
/// sheet hands focus back to the account stop, and a choice made in it becomes a request to the app.
private struct LibraryFocusRelay: Reducer {
    /// The library's state.
    typealias State = LibraryFeature.State

    /// What the library can do.
    typealias Action = LibraryFeature.Action

    /// Reacts to focus requests, the cloud library's focus delegates and the account sheet.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .contentFocusRequested(let request):
                switch state.section {
                case .cloud:
                    return .send(.cloudLibrary(.focusRequested(request)))
                case .trophies:
                    return .send(.trophies(.focusRequested(request)))
                case .consoles:
                    state.focusRequest = .firstConsole
                    return .none
                }
            case .focusMoved(let focus):
                state.heldFocus = focus
                return .none
            case .focusRequestHandled:
                state.focusRequest = nil
                return .none
            case .cloudLibrary(.delegate(.leftContent(let direction, let fromFilter))):
                state.focusRequest = .leftCloud(direction, fromFilter: fromFilter)
                return .none
            case .cloudLibrary(.delegate(.backToRail)), .trophies(.delegate(.backToRail)):
                state.focusRequest = .rail
                return .none
            case .trophies(.delegate(.leftContent(let direction))):
                state.focusRequest = .leftSection(direction)
                return .none
            case .accountTapped:
                state.accountSheet = LibraryAccountSheetFeature.State()
                return .none
            case .accountSheet(.presented(.chose(let choice))):
                state.accountSheet = nil
                state.focusRequest = .returnToAccount
                return .send(.requested(Self.request(for: choice)))
            case .accountSheet(.dismiss):
                state.focusRequest = .returnToAccount
                return .none
            case .alertsTapped:
                guard state.alerts.panel == .closed else {
                    return .none
                }
                return .send(.alerts(.opened))
            case .alertsPanelClosed:
                guard state.alerts.panel == .open else {
                    return .none
                }
                state.focusRequest = .stop(.notifications)
                return .send(.alerts(.closed))
            case .alerts(.delegate(.show(let notice))):
                return .send(.delegate(.showAlert(notice)))
            case .alerts(.delegate(.playInCloud(let invitation))):
                guard let accountID = state.selectedAccount, let game = state.cloudGame(joining: invitation),
                      let request = try? CloudLaunchRequest(
                          accountID: accountID,
                          game: game,
                          joining: invitation
                      )
                else {
                    return .none
                }
                return .concatenate(
                    .send(.alertsPanelClosed),
                    .send(.sectionSelected(.cloud)),
                    .send(.cloudLibrary(.select(game.id))),
                    .send(.cloudLibrary(.checkAndPlay(request)))
                )
            case .alerts(.delegate(.playOn(let hardwareID))):
                guard let console = state.linkedConsoles.first(where: {
                    $0.hardwareID.flatMap(HardwareID.init(hex:)) == hardwareID
                }) else {
                    return .none
                }
                let presence = ConsolePresence.of(
                    console,
                    in: state.discovery.snapshot,
                    searched: state.discovery.hasSearched
                )
                let route: PlaybackRoute = presence == .notNearby
                    ? .remote
                    : .local
                return .merge(
                    .send(.alertsPanelClosed),
                    .send(.requested(.startConsole(console, route)))
                )
            default:
                return .none
            }
        }
    }

    private static func request(for choice: LibraryAccountSheetFeature.Choice) -> LibraryRequest {
        switch choice {
        case .account(let id):
            .selectAccount(id)
        case .add:
            .addAccount
        case .refresh:
            .refreshAccounts
        case .signInAgain(let id):
            .reconnectAccount(id)
        case .remove(let id):
            .removeAccount(id)
        }
    }
}

/// Waits for the console catalog while the app loads it, and marks the wait slow once the shelf's patience
/// runs out.
///
/// When the catalog arrives the wait ends, and focus enters the first console card unless another hand-off is
/// pending.
private struct LibraryCatalogWait: Reducer {
    /// The library's state.
    typealias State = LibraryFeature.State

    /// What the library can do.
    typealias Action = LibraryFeature.Action

    private enum CancelID: Sendable {
        case consoleLoad
    }

    @Dependency(\.continuousClock) private var clock

    /// Marks a wait that ran out of patience as slow.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard case .consoleLoadElapsed = action, state.consoleLoad == .waiting else {
                return .none
            }
            state.consoleLoad = .slow
            return .none
        }
    }

    /// Starts or ends the wait as the app's catalog load starts or ends.
    ///
    /// - Parameter state: The library's state.
    /// - Returns: The effect that times the wait, cancels it, or none.
    func follow(_ state: inout State) -> Effect<Action> {
        switch (state.activity.catalog, state.consoleLoad) {
        case (.loading, .loaded):
            state.consoleLoad = .waiting
            return .run { [clock] send in
                try await clock.sleep(for: ConsoleShelfLoad.patience)
                await send(.consoleLoadElapsed)
            }
            .cancellable(id: CancelID.consoleLoad, cancelInFlight: true)
        case (.loaded, .waiting), (.loaded, .slow):
            state.consoleLoad = .loaded
            if state.section == .consoles, state.focusRequest == nil {
                state.focusRequest = .firstConsole
            }
            return .cancel(id: CancelID.consoleLoad)
        case (.loading, .waiting), (.loading, .slow), (.loaded, .loaded):
            return .none
        }
    }
}

/// A focus hand-off the library screen applies once its target can take focus.
///
/// The library keeps the request in ``LibraryFeature/State/focusRequest`` until the screen reports that
/// focus moved, so a request made while its target is still appearing is applied when it appears instead of
/// being retried on a timer.
enum LibraryFocusRequest: Equatable {
    /// The first console, or the stop that stands in for it.
    case firstConsole
    /// The stop that held focus when the screen was last shown, or the first console when it is gone.
    case resume(ConsoleLibraryFocus)
    /// A rail, header or shelf stop.
    case stop(ConsoleLibraryFocus)
    /// The account stop, unless something else took focus while the account sheet closed.
    case returnToAccount
    /// The rail stop of the shown section.
    case rail
    /// Focus left the cloud content in this direction; `fromFilter` tells whether it left from a filter chip.
    case leftCloud(MenuMoveDirection, fromFilter: Bool)
    /// Focus left another section's content in this direction.
    case leftSection(MenuMoveDirection)
}
