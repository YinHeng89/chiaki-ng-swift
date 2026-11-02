import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The application: where the user is, what is presented over it, and the app data that outlives a screen.
///
/// ``State/route`` is the one navigation value; ``State/destination`` is what is presented over it. The
/// accounts, the console catalog, the selected account and console, discovery, the lifecycle, automatic
/// connection, wake resume and title launch live here because they outlive every screen. The accounts, the
/// console pairings and the selected account are the `@Shared` values the library reads. Children talk to the
/// root through their delegates, and every console or cloud stream starts through `RootStreamReducer`,
/// which shows `Route/State/stream`. The stream session itself is ``State/stream``: it outlives the stream
/// screen, which is left at once while the session closes.
@Reducer
public struct RootFeature {
    /// What asked to quit, so focus can return to it when the user stays.
    public enum QuitOrigin: Equatable, Sendable {
        /// The quit button beside Settings.
        case button

        /// Back on a home screen.
        case screen
    }

    /// The screen shown.
    public typealias Route = RootRoute

    /// What is presented over the screen.
    public typealias Destination = RootDestination

    /// The application's state.
    @ObservableState
    public struct State: Equatable {
        /// The screen shown.
        public var route: Route.State

        /// What is presented over the screen.
        @Presents public var destination: Destination.State?

        /// The known accounts, shared with the library.
        @Shared(.accounts) public var profiles

        /// Every console pairing of a known account, shared with the library.
        @Shared(.consoleCatalog) public var registrations

        /// The selected account, shared with the library.
        @Shared(.selectedAccount) public var selectedAccount

        /// The selected console.
        public var selectedConsole: RegistrationFlow.ConsoleTarget?

        /// Whether the console pairings have been read.
        public var catalogStatus = LaunchFlow.Catalog.pending

        /// The account selection being restored after the accounts loaded, until the user picks one.
        public var restoringSelection: OperationID?

        /// Why the console pairings could not be read.
        public var registrationFailure: RegistrationFailure?

        /// Why the last pairing could not start or ended without a console, shown on the add-console screen.
        public var pairingFailure: PairingFailure?

        /// What the add-console screen held when it started the running pairing, restored when the pairing
        /// returns there.
        public var addConsoleDraft: AddConsoleFeature.Draft?

        /// Quitting, sleep and wake.
        public var lifecycle = LifecycleFeature.State()

        /// The accounts the app knows.
        public var accounts = AccountsFeature.State()

        /// The saved console pairings.
        public var consoleCatalog = ConsoleCatalogFeature.State()

        /// The one local-network discovery.
        public var discovery = DiscoveryFeature.State()

        /// The console or cloud stream session, kept while it closes after the stream screen is left.
        public var stream = StreamFeature.State()

        /// The recently played titles and their launch.
        public var recentlyPlayed = RecentlyPlayedReducer.State()

        /// The artwork of recently played titles.
        public var consoleArt = ConsoleArtReducer.State()

        /// The automatic connection.
        public var autoConnection = AutoConnectFeature.State()

        /// The resume after the Mac wakes.
        public var wakeResumption = WakeResumeFeature.State()

        /// The library screen's state, kept while other screens are shown.
        public var library = LibraryFeature.State()

        /// Every settings pane, kept while the panel is closed.
        public var settings = SettingsFeature.State()

        /// The live log.
        public var liveLog = LiveLogReducer.State()

        /// The stream chrome.
        public var streamChrome = StreamChromeReducer.State()

        /// The on-screen gamepad for touch play.
        public var virtualGamepad = VirtualGamepadFeature.State()

        /// A stream asked for on the command line or by a file.
        public var launch = LaunchFeature.State()

        /// Creates the state.
        ///
        /// - Parameters:
        ///   - route: The screen to start on.
        ///   - destination: What to present over it.
        public init(route: Route.State = .launching, destination: Destination.State? = nil) {
            self.route = route
            self.destination = destination
        }

        /// The accounts, pairings and selection as one value, written back to the shared values.
        public var appData: RegistrationFlow {
            get {
                RegistrationFlow(
                    profiles: profiles,
                    registrations: registrations,
                    selectedProfileID: selectedAccount,
                    selectedConsole: selectedConsole
                )
            }
            set {
                if profiles != newValue.profiles {
                    $profiles.withLock {
                        $0 = newValue.profiles
                    }
                }
                if registrations != newValue.registrations {
                    $registrations.withLock {
                        $0 = newValue.registrations
                    }
                }
                if selectedAccount != newValue.selectedProfileID {
                    $selectedAccount.withLock {
                        $0 = newValue.selectedProfileID
                    }
                }
                selectedConsole = newValue.selectedConsole
            }
        }

        /// The selected account.
        public var selectedProfile: RegistrationFlow.Profile? {
            appData.selectedProfile
        }

        /// The screen the app returns to: the library once an account exists, else the welcome screen.
        public var home: Route.State {
            profiles.isEmpty
                ? .welcome
                : .library
        }

        /// Whether any saved account is signed in to PlayStation Network.
        public var psnReach: PSNReach {
            profiles.contains { profile in
                profile.kind.permits(.cloud)
            }
                ? .signedIn
                : .localOnly
        }

        /// Whether a console, cloud or Kakusan guest stream is playing, so its chrome may hide and its
        /// stream menu dock holds Settings.
        public var streamPlaying: Bool {
            if case .kakusanGuest(let guest) = route, guest.playing {
                return true
            }
            return route == .stream && stream.status == .playing
        }

        /// The system uptime when the open settings panel opened, which tells a press that began before it
        /// and a settling notice from an earlier opening apart; `nil` while the panel is closed.
        public internal(set) var settingsOpenedAt: TimeInterval?

        /// Whether the settings panel is open.
        public var settingsPresented: Bool {
            if case .settings = destination {
                return true
            }
            return false
        }

        /// Whether the app is quitting.
        public var termination: Termination {
            lifecycle.termination
        }

        /// Whether the accounts or the console pairings are being read.
        public var loadingConsoles: Bool {
            if case .loading = accounts.operation {
                return true
            }
            if case .loading = consoleCatalog.load {
                return true
            }
            return false
        }

        /// What the loading screen of a title launch or a connecting console stream shows.
        var loadingStage: ConsoleLoadingStage? {
            ConsoleLoadingStage(status: stream.status, launching: recentlyPlayed.launch.title)
        }

        /// The artwork of the title being launched, once all its layers are known.
        var titleLoadingArt: GameArtLayers? {
            recentlyPlayed.launch.title.flatMap { consoleArt.layers(for: $0.conceptID) }
        }

        /// Whether a guest join is shown.
        public var guestPresented: Bool {
            guard case .kakusanGuest(let guest) = route else {
                return false
            }
            return guest.presented
        }
    }

    /// Everything the application reacts to.
    public enum Action: Equatable {
        /// Something the user did, or a change of the root view's lifecycle.
        case view(View)

        /// The screen shown.
        case route(Route.Action)

        /// What is presented over the screen.
        case destination(PresentationAction<Destination.Action>)

        /// The user asked to quit from the platform.
        case terminationRequested

        /// The Mac is going to sleep after the notification with this number.
        case systemWillSleep(Int)

        /// The Mac woke.
        case systemDidWake

        /// The network the Mac uses changed.
        case networkChanged

        /// A Kakusan invitation or reply file was opened.
        case kakusanFileOpened(KakusanBlock)

        /// A stream was asked for on the command line or by a file.
        case launchRequested(LaunchRequest)

        /// The account remembered as selected was read after the accounts loaded with this id.
        case activeAccountRestored(OperationID, UUID)

        /// Quitting, sleep and wake.
        case lifecycle(LifecycleFeature.Action)

        /// The accounts.
        case accounts(AccountsFeature.Action)

        /// The saved console pairings.
        case consoleCatalog(ConsoleCatalogFeature.Action)

        /// The local-network discovery.
        case discovery(DiscoveryFeature.Action)

        /// The console stream.
        case stream(StreamFeature.Action)

        /// The recently played titles.
        case recentlyPlayed(RecentlyPlayedReducer.Action)

        /// The artwork of recently played titles.
        case consoleArt(ConsoleArtReducer.Action)

        /// The automatic connection.
        case autoConnect(AutoConnectFeature.Action)

        /// The resume after the Mac wakes.
        case wakeResume(WakeResumeFeature.Action)

        /// The library screen.
        case library(LibraryFeature.Action)

        /// The settings panes.
        case settings(SettingsFeature.Action)

        /// The live log.
        case liveLog(LiveLogReducer.Action)

        /// The stream chrome.
        case streamChrome(StreamChromeReducer.Action)

        /// The on-screen gamepad.
        case virtualGamepad(VirtualGamepadFeature.Action)

        /// A stream asked for on the command line or by a file.
        case launch(LaunchFeature.Action)

        /// What the user did, or a change of the root view's lifecycle.
        @CasePathable
        public enum View: Equatable {
            /// The root view appeared.
            case appeared

            /// The scene became active.
            case sceneActivated

            /// The scene stopped being active.
            case sceneDeactivated

            /// The root view went away: everything stops.
            case disappeared

            /// Sign in with a PlayStation account from the welcome screen.
            case chooseSignIn

            /// Add an account by account id from the welcome screen.
            case chooseAccountID

            /// Return from the welcome screen to the library.
            case showLibrary

            /// Read the saved accounts again after they could not be read.
            case reloadAccounts

            /// Abandon saving an account.
            case cancelAccountWork

            /// Join someone else's game.
            case joinGame

            /// Select an account.
            case selectAccount(UUID)

            /// Add another account.
            case addAccount

            /// Sign an account in again.
            case reconnectAccount(UUID)

            /// Add a console.
            case addConsole

            /// Select a paired console.
            case selectConsole(RegistrationFlow.ConsoleTarget)

            /// Stream the selected console.
            case play(PlaybackRoute)

            /// Launch a recently played title on a console.
            case playTitle(UUID, RecentTitle)

            /// Leave the console stream or the title launch.
            case leaveStream

            /// Edit a console.
            case editConsole(ConsoleDraft)

            /// Ask to delete a console.
            case deleteConsole(UUID)

            /// Open the settings panel.
            case openSettings

            /// Close the settings panel.
            case closeSettings

            /// Open the settings panel when it is closed, and close it when it is open.
            case toggleSettings

            /// Ask whether to quit.
            case quitRequested(QuitOrigin)
        }
    }

    /// Creates the reducer.
    public init() {}

    /// What the root view watches PSN alerts for: the account and the watch's generation, so a new account or
    /// generation replaces the running watch.
    public struct AlertsWatch: Hashable, Sendable {
        /// The account watched, or `nil` when the selected account cannot be watched.
        public let profile: ProfileID?

        /// The watch's generation.
        public let generation: Int
    }

    /// The alerts watch the root view keeps running.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The account and generation to watch.
    public static func alertsWatch(in state: State) -> AlertsWatch {
        AlertsWatch(profile: alertsProfile(in: state), generation: state.library.alerts.generation)
    }

    /// The account whose PSN alerts are watched: the selected account when it signed in on the web.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The profile, or `nil` when the selected account cannot be watched.
    public static func alertsProfile(in state: State) -> ProfileID? {
        guard let profile = state.selectedProfile, profile.kind.permits(.cloud) else {
            return nil
        }
        return ProfileID(uuid: profile.id)
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        core
            .requires(
                .cloud,
                of: \.selectedProfile,
                entering: \.library.cloudLibrary.account, \.library.cloudLibrary.refresh,
                \.library.cloudLibrary.refreshTitle, \.library.cloudLibrary.delegate.play, \.stream.start,
                \.stream.retry
            )
            .requires(
                .cloud,
                of: \.selectedProfile,
                entering: \.library.cloudStatus.select, \.library.cloudStatus.refresh,
                otherwise: .library(.cloudStatus(.stop))
            )
            .requires(.psnConsoles, of: \.selectedProfile) { action in
                switch action {
                case .view(.play(.remote)), .view(.playTitle):
                    true
                default:
                    false
                }
            }
            .onChange(of: { RootControllerLights.wanted(in: $0) }, { _, lights in
                RootControllerLights(lightbars: lights)
            })
            .onChange(of: \.psnReach) { _, reach in
                Reduce { _, _ in
                    .send(.settings(.psnReach(reach)))
                }
            }
            .onChange(of: \.guestPresented) { _, presented in
                Reduce { state, _ in
                    RootRouter.followGuest(presented, state: &state)
                }
            }
            .onChange(of: \.settings.logSettings.showLiveLogButton) { _, shown in
                Reduce { _, _ in
                    shown
                        ? .none
                        : .send(.liveLog(.close))
                }
            }
            .onChange(of: { RootLaunchObserver.consoles($0) }, { _, consoles in
                Reduce { state, _ in
                    RootLaunchObserver.observe(.consolesChanged(consoles), state: &state)
                }
            })
            .onChange(of: { RootLaunchObserver.activity($0) }, { _, activity in
                Reduce { state, _ in
                    RootLaunchObserver.observe(.stream(activity), state: &state)
                }
            })
    }

    @ReducerBuilder<State, Action>
    private var core: some ReducerOf<Self> {
        RootSessionServices()
        RootRouter()
        CombineReducers {
            RootNavigationReducer()
            RootPresentationReducer()
            RootAccountsReducer()
            RootPairingReducer()
            RootStreamReducer()
            RootLifecycleRelay()
            RootDiscoveryRelay()
            RootLaunchObserver()
        }
        .ifLet(\.$destination, action: \.destination)
        RootSurfaces()
        RootLibraryMirror()
    }
}

/// What ``RootFeature`` presents over the screen it shows.
@Reducer
public enum RootDestination {
    /// The settings panel; its panes live in `RootFeature.State.settings`.
    case settings

    /// Editing or deleting a console.
    case consoleEditor(ConsoleEditorFeature)

    /// A question such as whether to quit.
    case alert(AlertState<Alert>)

    /// What an alert's buttons do.
    public enum Alert: Equatable, Sendable {
        /// Quit the app.
        case quit

        /// Stay, returning focus to what asked to quit.
        case stay(RootFeature.QuitOrigin)
    }
}

extension RootDestination.State: Equatable {}

extension RootDestination.Action: Equatable {}

/// The screen ``RootFeature`` shows: the one navigation value of the application.
@Reducer
public enum RootRoute {
    /// The saved accounts are being read.
    case launching

    /// No account yet, or adding another one.
    case welcome

    /// Signing in on the web.
    case signIn(SignInFeature)

    /// Adding an account by account id.
    case accountIDEntry(AccountIDEntryFeature)

    /// The library.
    case library

    /// Finding a console to pair.
    case addConsole(AddConsoleFeature)

    /// Pairing a console.
    case pairing(PairingFeature)

    /// The stream of `RootFeature.State.stream`, or a title launch waiting for its stream.
    case stream

    /// Joining someone else's game.
    case kakusanGuest(KakusanGuestFeature)
}

extension RootRoute.State: Equatable {}

extension RootRoute.Action: Equatable {}

/// Shares the one local-network discovery between the library and automatic connection.
///
/// The library acquires and releases discovery through its delegate, and every discovery report reaches both
/// the library and automatic connection.
private struct RootDiscoveryRelay: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// Reacts to discovery reports and the library's discovery requests.
    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .discovery(.delegate(.updated(let snapshot))):
                return .merge(
                    .send(.autoConnect(.discovered(snapshot))),
                    .send(.library(.discoveryUpdated(snapshot)))
                )
            case .discovery(.delegate(.searched(let searched))):
                return .send(.library(.discoverySearched(searched)))
            case .discovery(.delegate(.failed)):
                return .merge(.send(.autoConnect(.discoveryFailed)), .send(.library(.discoveryFailed)))
            case .library(.delegate(.acquireDiscovery)):
                return .send(.discovery(.acquire(.library)))
            case .library(.delegate(.releaseDiscovery)):
                return .send(.discovery(.release(.library)))
            default:
                return .none
            }
        }
    }
}

/// The children of ``RootFeature`` whose state is kept while they are hidden: the launch notice, the library
/// screen, the live log, the settings panes, the stream chrome and the on-screen gamepad.
///
/// They run after the root has reacted to an action, so that what the root sends them arrives with the
/// application's state already settled.
private struct RootSurfaces: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// Runs every kept surface for its own actions.
    var body: some ReducerOf<Self> {
        Scope(state: \.launch, action: \.launch) {
            LaunchFeature()
        }
        Scope(state: \.library, action: \.library) {
            LibraryFeature()
        }
        Scope(state: \.liveLog, action: \.liveLog) {
            LiveLogReducer()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Scope(state: \.streamChrome, action: \.streamChrome) {
            StreamChromeReducer()
        }
        Scope(state: \.virtualGamepad, action: \.virtualGamepad) {
            VirtualGamepadFeature()
        }
    }
}

/// The children of ``RootFeature`` that outlive every screen: the stream session, discovery, the console
/// catalog, recently played titles and their artwork, the accounts, automatic connection, wake resume and the
/// lifecycle.
///
/// They run before the root reacts to an action, so that the root sees their delegates with their state
/// already updated. Automatic connection is told whether a stream runs before it handles each action.
private struct RootSessionServices: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// Runs every long-lived child for its own actions.
    var body: some ReducerOf<Self> {
        Scope(state: \.stream, action: \.stream) {
            StreamFeature()
        }
        Scope(state: \.discovery, action: \.discovery) {
            DiscoveryFeature()
        }
        Scope(state: \.consoleCatalog, action: \.consoleCatalog) {
            ConsoleCatalogFeature()
        }
        Scope(state: \.recentlyPlayed, action: \.recentlyPlayed) {
            RecentlyPlayedReducer()
        }
        Scope(state: \.consoleArt, action: \.consoleArt) {
            ConsoleArtReducer()
        }
        Scope(state: \.accounts, action: \.accounts) {
            AccountsFeature()
        }
        Reduce { state, action in
            RootStreamReducer.syncAutoConnectActivity(before: action, state: &state)
        }
        Scope(state: \.autoConnection, action: \.autoConnect) {
            AutoConnectFeature()
        }
        Scope(state: \.wakeResumption, action: \.wakeResume) {
            WakeResumeFeature()
        }
        Scope(state: \.lifecycle, action: \.lifecycle) {
            LifecycleFeature()
        }
    }
}

/// Passes quitting, sleep and wake to ``LifecycleFeature`` and carries out what it asks of the application.
///
/// Quitting and a sleep that stopped a stream stop the stream and leave a guest session; going to sleep
/// remembers the console that streamed so that wake resume can return to it.
private struct RootLifecycleRelay: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// Reacts to the platform's lifecycle events and the lifecycle's requests.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .terminationRequested:
                return .send(.lifecycle(.terminationRequested))
            case .systemWillSleep(let notification):
                return .send(.lifecycle(.systemWillSleep(
                    notification,
                    consoleStreaming: RootStreamReducer.consoleStreaming(state),
                    stream: state.stream.session.id,
                    guestJoin: shownGuestJoin(state)
                )))
            case .systemDidWake:
                return .send(.lifecycle(.systemDidWake))
            case .networkChanged:
                return .send(.lifecycle(.networkChanged))
            case .lifecycle(.delegate(let delegate)):
                return lifecycleReported(delegate, state: state)
            default:
                return .none
            }
        }
    }

    private func lifecycleReported(_ delegate: LifecycleFeature.Action.Delegate,
                                   state: State) -> Effect<Action> {
        switch delegate {
        case .terminating:
            return .merge(.send(.stream(.stop)), leaveGuestSession(state), .send(.liveLog(.close)))
        case .sleeping:
            let active: StreamTarget? = RootStreamReducer.consoleStreaming(state)
                ? state.stream.target
                : nil
            return .merge(.send(.autoConnect(.interrupted)), .send(.wakeResume(.sleeping(active: active))))
        case let .sleepStoppedStream(stream, guestJoin):
            return .merge(
                stopStream(openAtSleep: stream, state: state),
                leaveGuestSession(shownAtSleep: guestJoin, state: state)
            )
        case .woke:
            return .send(.wakeResume(.woke))
        }
    }

    private func shownGuestJoin(_ state: State) -> UUID? {
        guard case .kakusanGuest(let guest) = state.route, guest.presented else {
            return nil
        }
        return guest.joinID
    }

    private func stopStream(openAtSleep stream: StreamSessionID?, state: State) -> Effect<Action> {
        guard let stream, state.stream.session.id == stream else {
            return .none
        }
        return .send(.stream(.stop))
    }

    private func leaveGuestSession(shownAtSleep guestJoin: UUID?, state: State) -> Effect<Action> {
        guard let guestJoin, shownGuestJoin(state) == guestJoin else {
            return .none
        }
        return .send(.route(.kakusanGuest(.leave)))
    }

    private func leaveGuestSession(_ state: State) -> Effect<Action> {
        state.guestPresented
            ? .send(.route(.kakusanGuest(.leave)))
            : .none
    }
}

/// Tells a command-line or file launch what the application's consoles and stream are doing.
///
/// A launch request is passed to ``LaunchFeature`` with the consoles and the stream activity of that moment,
/// and every later change of either is reported to it so that it can connect, wait or give up.
private struct RootLaunchObserver: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// Passes launch requests to the launch with the application's current consoles and activity.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard case .launchRequested(let request) = action else {
                return .none
            }
            return .send(.launch(.requested(request, Self.consoles(state), Self.activity(state))))
        }
    }

    /// Reports a change of the consoles or the stream to the launch.
    ///
    /// - Parameters:
    ///   - event: The change.
    ///   - state: The application's state.
    /// - Returns: The effects the launch asks for.
    static func observe(_ event: LaunchFlow.Event, state: inout State) -> Effect<Action> {
        LaunchFeature().observe(event, state: &state.launch).map(Action.launch)
    }

    /// The consoles a launch can connect to.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The pairings, the selected account and whether the pairings have been read.
    static func consoles(_ state: State) -> LaunchFlow.Consoles {
        LaunchFlow.Consoles(
            registrations: state.registrations,
            selectedProfileID: state.selectedAccount,
            catalog: state.catalogStatus
        )
    }

    /// What the console stream, automatic connection and wake resume are doing, as a launch sees it.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The stream activity.
    static func activity(_ state: State) -> LaunchFlow.StreamActivity {
        let console = state.stream.target?.consoleID
        switch state.stream.kind == .console
            ? state.stream.status
            : .idle {
        case .connecting:
            return .connecting(console)
        case .playing:
            return .playing(console)
        case .stopping:
            return .closing(console)
        case .idle, .failed:
            break
        }
        switch state.autoConnection.machine {
        case .failed:
            return .preparationFailed
        case .awaitingLibrary, .checkingLaunchSetting, .discovering, .waking, .awaitingWake:
            return .preparing(state.autoConnection.machine.consoleID)
        case .idle:
            return state.wakeResumption.machine == .idle
                ? .idle
                : .resuming
        }
    }
}

/// Keeps the library screen's copy of the recently played titles, their artwork and the application's
/// activity in step with the root.
///
/// The activity is derived from the accounts' refresh and removal, the console editor and the loading of the
/// consoles, and the library is told whenever it changes.
private struct RootLibraryMirror: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// Copies the root's library data into the library after every action.
    var body: some ReducerOf<Self> {
        Reduce { state, _ in
            if state.library.recentlyPlayed != state.recentlyPlayed {
                state.library.recentlyPlayed = state.recentlyPlayed
            }
            if state.library.consoleArt != state.consoleArt {
                state.library.consoleArt = state.consoleArt
            }
            let activity = Self.activity(state)
            guard activity != state.library.activity else {
                return .none
            }
            return LibraryFeature().changeActivity(to: activity, state: &state.library).map(Action.library)
        }
    }

    private static func activity(_ state: State) -> LibraryActivity {
        let refresh: LibraryActivity.Refresh =
            switch state.accounts.refresh {
            case .idle:
                .idle
            case .refreshing:
                .refreshing
            case .failed:
                .failed
            }
        let removal: LibraryActivity.Removal =
            switch state.accounts.operation {
            case .deleting:
                .removing
            case .failed(.deleteFailed):
                .failed
            case .idle, .loading, .saving, .confirmingDeletion, .failed:
                .idle
            }
        let editing: Bool =
            if case .consoleEditor = state.destination {
                true
            } else {
                false
            }
        return LibraryActivity(
            refresh: refresh,
            removal: removal,
            signInNeeded: state.accounts.needingSignIn,
            catalog: state.loadingConsoles
                ? .loading
                : .loaded,
            consoleOperation: editing
                ? .busy
                : .idle
        )
    }
}

/// Shows lightbar colours on the connected controllers when the colours the application wants change.
///
/// A newer change cancels a show that has not reached the controllers yet.
struct RootControllerLights: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    private enum CancelID {
        case show
    }

    /// The colours to show.
    let lightbars: ControllerLightbars

    @Dependency(\.controllers) private var controllers

    /// The lightbar colours the application wants: an unsaved couch or Controls edit while it is being made,
    /// else the saved ones.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The colours to show.
    static func wanted(in state: State) -> ControllerLightbars {
        let couch = state.stream.couch.controls
        if let couch, couch.draft.lightbars != couch.configuration.lightbars {
            return couch.draft.lightbars
        }
        let controls = state.settings.controls
        let editing = state.settingsPresented && state.settings.route == .controls
        if editing || controls.setting.isBusy,
           controls.draft.lightbars != controls.configuration.lightbars {
            return controls.draft.lightbars
        }
        return controls.configuration.lightbars
    }

    /// Shows ``lightbars`` on the main actor.
    var body: some ReducerOf<Self> {
        Reduce { _, _ in
            .run { [controllers, lightbars] _ in
                await MainActor.run {
                    guard !Task.isCancelled else {
                        return
                    }
                    controllers.showLights(lightbars)
                }
            }
            .cancellable(id: CancelID.show, cancelInFlight: true)
        }
    }
}
