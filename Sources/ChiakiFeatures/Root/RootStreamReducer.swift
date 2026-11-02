import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Starts every console and cloud stream of the application and follows the stream session.
///
/// Every stream starts through ``startStream(_:state:)``, whether the library, a recently played title,
/// automatic connection, wake resume or a launch request asked for it. The stream screen is shown while the
/// session connects and plays, and left as soon as the session starts closing.
struct RootStreamReducer: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    /// What a stream is started for.
    enum Start: Equatable, Sendable {
        /// A paired console; `reselect` lets the stream select its account and console.
        case console(StreamTarget, reselect: Bool)

        /// A cloud title the library cleared to launch.
        case cloud(StreamSource)
    }

    /// Reacts to the stream session and to everything that asks for a stream.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .stream(.start), .route(.kakusanGuest(.open)):
                guard state.autoConnection.machine.isActive else {
                    return .none
                }
                return .send(.autoConnect(.cancel))
            case .stream(let stream):
                return streamReported(stream, state: &state)
            case .recentlyPlayed(.delegate(.startStream(let request))):
                return startTitleStream(request, state: &state)
            case .autoConnect(.delegate(let delegate)):
                return autoConnectReported(delegate, state: &state)
            case .wakeResume(.delegate(.resume(let target))):
                return startStream(.console(target, reselect: false), state: &state) ??
                    .send(.wakeResume(.refused))
            case .library(.cloudLibrary(.delegate(.play(let request)))):
                guard let source = StreamFeature.source(cloud: request) else {
                    return .none
                }
                return startStream(.cloud(source), state: &state) ?? .none
            case .launch(.delegate(.connect(let request))):
                state.stream.windowOwner = .launch
                return connect(request, state: &state)
            case .launch(.delegate(.releaseWindow)):
                state.stream.windowOwner = .stream
                return .none
            default:
                return .none
            }
        }
    }

    /// Starts a console or cloud stream: the one path every stream starts through.
    ///
    /// Shows `Route/State/stream`; a console stream also selects its account and console.
    ///
    /// - Parameters:
    ///   - start: What to stream.
    ///   - state: The application's state.
    /// - Returns: The effects that start the stream, or `nil` when a stream runs, the pairing is unknown, the
    ///   route is not available or the screen cannot show the stream.
    func startStream(_ start: Start, state: inout State) -> Effect<Action>? {
        guard Self.streamingIdle(state.stream.status),
              state.route == .library || state.route == .stream
        else {
            return nil
        }
        let begin: Effect<Action>
        switch start {
        case let .console(target, reselect):
            guard let started = startConsole(target, reselect: reselect, state: &state) else {
                return nil
            }
            begin = started
        case .cloud(let source):
            begin = .send(.stream(.start(source)))
        }
        state.route = .stream
        let dismissal: Effect<Action> = state.stream.status == .idle
            ? .none
            : .send(.stream(.dismissFailure))
        return .concatenate(dismissal, begin)
    }

    /// Launches a recently played title on a console, showing the stream screen while the title starts.
    ///
    /// - Parameters:
    ///   - consoleID: The console.
    ///   - title: The title.
    ///   - state: The application's state.
    /// - Returns: The effects that launch the title and fetch its artwork.
    func playTitle(_ consoleID: UUID, title: RecentTitle, state: inout State) -> Effect<Action> {
        guard state.route == .library, state.stream.status == .idle,
              state.recentlyPlayed.launch == .idle,
              let account = state.selectedAccount,
              let console = state.appData.linkedConsoles
              .first(where: { $0.id == consoleID && $0.kind == .ps5 }),
              let rail = state.recentlyPlayed.rail(for: consoleID),
              rail.titles.contains(title),
              state.appData.selectStream(profile: account, console: console)
        else {
            return .none
        }
        state.route = .stream
        return .concatenate(
            .send(.recentlyPlayed(.launch(.play(TitleLaunch(
                accountID: account, consoleID: consoleID, hardwareID: rail.hardwareID, title: title
            ))))),
            .send(.consoleArt(.want(ConsoleArtRequest(accountID: account, conceptID: title.conceptID))))
        )
    }

    /// Why a launch request cannot stream its console, if it cannot.
    ///
    /// - Parameters:
    ///   - request: The launch request.
    ///   - state: The application's state.
    /// - Returns: The reason, or `nil` when the request can go ahead.
    static func rejection(_ request: LaunchConnect, state: State) -> LaunchRejection? {
        switch state.stream.status {
        case .idle, .failed:
            break
        case .connecting, .playing:
            return .streamActive
        case .stopping:
            return .streamClosing
        }
        if case .deleting = state.accounts.operation {
            return .accountChanging
        }
        let linked = state.registrations.contains {
            $0.profileID == request.profileID && $0.console == request.console
        }
        guard linked else {
            return .consoleNotLinked
        }
        guard request.route == .remote else {
            return nil
        }
        guard request.console.remoteDeviceID != nil else {
            return .remoteUnavailable
        }
        let profile = state.profiles.first {
            $0.id == request.profileID
        }
        return profile.permits(.psnConsoles)
            ? nil
            : .remoteNeedsSignIn
    }

    /// Whether a stream phase leaves room to start another stream.
    ///
    /// - Parameter status: The stream's status.
    /// - Returns: `true` when nothing streams.
    static func streamingIdle(_ status: StreamStatus) -> Bool {
        switch status {
        case .idle, .failed:
            true
        case .connecting, .playing, .stopping:
            false
        }
    }

    /// Tells automatic connection whether a stream runs before it handles one of its own actions.
    ///
    /// - Parameters:
    ///   - action: The action about to reach automatic connection.
    ///   - state: The application's state.
    /// - Returns: No effect.
    static func syncAutoConnectActivity(before action: Action, state: inout State) -> Effect<Action> {
        guard case .autoConnect(let autoConnect) = action else {
            return .none
        }
        if case .delegate = autoConnect {
            return .none
        }
        let streaming = !streamingIdle(state.stream.status) || state.route == .stream
        state.autoConnection.activity = streaming
            ? .streaming
            : .free
        return .none
    }

    /// Whether a console stream connects or plays.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: `true` while a console stream is live.
    static func consoleStreaming(_ state: State) -> Bool {
        guard state.stream.kind == .console else {
            return false
        }
        switch state.stream.status {
        case .connecting, .playing:
            return true
        case .idle, .stopping, .failed:
            return false
        }
    }

    private func startConsole(_ target: StreamTarget, reselect: Bool, state: inout State) -> Effect<Action>? {
        guard let console = state.appData.console(target.consoleID, of: target.account) else {
            return nil
        }
        let selected = state.selectedAccount == target.account && state.selectedConsole == console
        guard selected || reselect else {
            return nil
        }
        if target.route == .remote {
            let profile = state.profiles.first { $0.id == target.account }
            guard console.remoteDeviceID != nil, profile.permits(.psnConsoles) else {
                return nil
            }
        }
        let previous = state.selectedAccount
        guard state.appData.selectStream(profile: target.account, console: console) else {
            return nil
        }
        let selection: Effect<Action> = previous == target.account
            ? .none
            : RootAccountsReducer().persist(target.account)
        return .merge(
            selection,
            .send(.stream(.startConsole(
                account: target.account,
                console: console,
                route: target.route,
                keepsRoute: target.played
            )))
        )
    }

    private func startTitleStream(_ request: TitleLaunch, state: inout State) -> Effect<Action> {
        let target = StreamTarget(account: request.accountID, consoleID: request.consoleID, route: .local)
        guard state.route == .stream,
              state.stream.status == .idle,
              let start = startStream(.console(target, reselect: false), state: &state)
        else {
            return .send(.recentlyPlayed(.launch(.cancel)))
        }
        return .merge(.send(.autoConnect(.interrupted)), start)
    }

    private func connect(_ request: LaunchConnect, state: inout State) -> Effect<Action> {
        if let reason = Self.rejection(request, state: state) {
            return .send(.launch(.connectRejected(request.id, reason)))
        }
        guard let consoleID = request.console.id else {
            return .send(.launch(.connectRejected(request.id, .consoleNotLinked)))
        }
        if request.route == .local {
            return .send(.autoConnect(.start(consoleID, .stream(.local))))
        }
        let target = StreamTarget(account: request.profileID, consoleID: consoleID, route: request.route)
        guard let start = startStream(.console(target, reselect: true), state: &state) else {
            return .send(.launch(.connectRejected(request.id, .screenBusy)))
        }
        return start
    }

    private func streamReported(_ action: StreamFeature.Action, state: inout State) -> Effect<Action> {
        switch action {
        case .delegate(.started(let session)):
            return .merge(
                .send(.autoConnect(.interrupted)),
                .send(.wakeResume(.streamStarted)),
                .send(.recentlyPlayed(.launch(.streamStarted(session.uuid))))
            )
        case .delegate(.loginPINRequested(let session)):
            return .send(.recentlyPlayed(.launch(.loginPINRequested(session.uuid))))
        case .delegate(.playing(let session)):
            return .send(.recentlyPlayed(.launch(.streamConnected(session.uuid))))
        case .delegate(.closing):
            return RootRouter.leaveStream(state: &state)
        case .delegate(.ended):
            return .merge(RootRouter.leaveStream(state: &state), .send(.recentlyPlayed(.streamEnded)))
        case .delegate(.pairAgain(let console)):
            return RootPairingReducer().pairAgain(console, state: &state)
        case let .couch(.delegate(.controlsCommitted(configuration))):
            state.settings.controls.adopt(configuration)
            return .none
        default:
            return .none
        }
    }

    private func autoConnectReported(
        _ delegate: AutoConnectFeature.Action.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .acquireDiscovery:
            return .send(.discovery(.acquire(.autoConnect)))
        case .releaseDiscovery:
            return .send(.discovery(.release(.autoConnect)))
        case let .play(plan, route):
            let target = StreamTarget(account: plan.account, consoleID: plan.consoleID, route: route)
            return startStream(.console(target, reselect: true), state: &state) ??
                .send(.autoConnect(.refused(plan)))
        }
    }
}
