import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// One stream, from any `ChiakiModels/StreamSource`: console, cloud or Kakusan guest.
///
/// The workflow is the `ChiakiModels/StreamSession` machine. The session's events arrive in order from
/// `ChiakiClients/StreamSessionClient` tagged with the session's id, and every completion carries the id of
/// the operation that started it, so a stopped session can never move the next one. Leaving stops the session
/// at once; the menu saves its settings alongside. Saving launch settings in the menu relaunches the same
/// source under a new session while the window stays as it is. Children: the stream menu, couch seats, the
/// microphone, Kakusan hosting and the PS5 cloud toasts. What the parent needs is reported through
/// ``Delegate``.
@Reducer
public struct StreamFeature {
    /// The account and registered console a console stream belongs to, kept for its login PIN and unpairing.
    public struct ConsolePairing: Equatable, Sendable {
        /// The account.
        public let account: UUID

        /// The registered console.
        public let console: RegistrationFlow.ConsoleTarget
    }

    /// The stream's state.
    @ObservableState
    public struct State: Equatable {
        /// Where the session is.
        public internal(set) var session = StreamSession.idle

        /// What the session plays.
        public internal(set) var source: StreamSource?

        /// The console pairing, for a console stream.
        public internal(set) var pairing: ConsolePairing?

        /// The route a console stream chose, once the launcher reported it.
        public internal(set) var playedRoute: ConsoleRoute?

        /// The player's video view, once presented.
        public internal(set) var surface: StreamSurface?

        /// Whether the console prohibits showing its picture.
        public internal(set) var displayProhibited = false

        /// Whether the playing stream hears from the console.
        public internal(set) var connection = StreamConnection.receiving

        /// Where a Go to Home screen request from the hidden-screen notice is.
        public internal(set) var homeRequest = HomeRequest.idle

        /// Whether the hidden-screen notice's Home button holds the controller, so Cross and Down act on the app.
        public internal(set) var homeHoldsController = false

        /// Whether the picture is switched off, so only sound plays.
        public internal(set) var videoDisabled = false

        /// How the picture fits the window, as the stream started.
        public internal(set) var videoFit = VideoFit()

        /// The last progress report from the start or a reconnection.
        public internal(set) var progress: TimedProgress?

        /// The cloud datacenter the stream connected to.
        public internal(set) var datacenter: CloudDatacenterSelection?

        /// The bandwidth the cloud launch measured.
        public internal(set) var bandwidth: CloudBandwidthReport?

        /// The code prompt.
        public internal(set) var access = StreamAccessPhase.idle

        /// What happens with the console's saved login PIN.
        public internal(set) var savedLoginPIN = SavedLoginPIN.available

        /// The notice that the console stayed on after a rest request.
        public internal(set) var restNotice = RestNotice.hidden

        /// Who sizes the window while the stream plays.
        public var windowOwner = StreamWindowOwner.stream

        /// The offer to unpair a console that rejected its pairing.
        public internal(set) var unpair: UnpairOffer?

        /// The cloud loading screen.
        public internal(set) var loading = StreamLoading.hidden

        /// The console's on-screen keyboard.
        public internal(set) var keyboard = ConsoleKeyboard()

        /// The cloud service's warning that it closes the game soon, while it shows.
        public internal(set) var closingNotice: CloudClosingNotice?

        /// The PS5 cloud console's notices and recording banner.
        public var toasts = CloudToastsReducer.State()

        /// The stream menu.
        public var menu = StreamMenuReducer.State(context: .console(.local))

        /// The couch seats.
        public var couch = CouchReducer.State()

        /// The microphone.
        public var microphone = MicrophoneReducer.State()

        /// The Invitations panel, for a cloud stream.
        public var invitations: CloudInvitationsFeature.State?

        /// The Trophies panel, for a cloud stream whose game names a title id.
        public var trophies: StreamTrophiesFeature.State?

        /// Kakusan hosting, for a console stream.
        public var kakusan = KakusanHostFeature.State()

        /// Creates an idle stream.
        public init() {}

        /// The kind of stream, once one started.
        public var kind: StreamKind? {
            source?.kind
        }

        /// Whether the stream screen is shown: a session is starting, playing, stopping or failed.
        public var isPresented: Bool {
            switch session {
            case .idle, .ended:
                false
            case .starting, .awaitingAccess, .playing, .reconnecting, .relaunching, .stopping, .failed:
                true
            }
        }

        /// Whether nothing is running and nothing failed, so a new stream may start.
        public var isIdle: Bool {
            switch session {
            case .idle, .ended:
                true
            case .starting, .awaitingAccess, .playing, .reconnecting, .relaunching, .stopping, .failed:
                false
            }
        }

        /// The session as its parent sees it.
        public var status: StreamStatus {
            switch session {
            case .idle, .ended:
                .idle
            case .starting, .awaitingAccess, .relaunching:
                .connecting
            case .playing, .reconnecting:
                .playing
            case .stopping:
                .stopping
            case .failed:
                .failed
            }
        }

        /// Whether controller input drives the stream's own screens rather than the game: while the stream
        /// connects or failed, and during play while the stream menu navigates or the hidden-screen notice's
        /// Home button holds the controller.
        public var controllerNavigationActive: Bool {
            switch status {
            case .connecting, .failed:
                true
            case .playing:
                menu.navigation.isActive || (homeHoldsController && displayProhibited)
            case .idle, .stopping:
                false
            }
        }

        /// The account, console and route of a console stream, to start it again after sleep: the route it
        /// played on once the launcher chose one, otherwise the route asked for.
        public var target: StreamTarget? {
            guard case .console(let target, let route) = source, let console = target.console else {
                return nil
            }
            return StreamTarget(
                account: target.profile.uuid,
                consoleID: console.uuid,
                route: (playedRoute ?? route) == .internet
                    ? .remote
                    : .local,
                played: playedRoute != nil
            )
        }

        /// The stored console a console stream plays.
        public var consoleID: UUID? {
            guard case .console(let target, _) = source else {
                return nil
            }
            return target.console?.uuid
        }

        /// The text of the failure, when the session failed.
        public var failureMessage: LocalizedStringResource? {
            guard let failure = session.failure, let kind else {
                return nil
            }
            let text = StreamFailureMessage(failure, kind: kind).text
            guard kind == .cloud, let datacenter else {
                return text
            }
            return .playbackFailureWithDatacenter(
                message: String(localized: text),
                datacenter: String(localized: datacenter.statisticsDescription)
            )
        }

        /// How the picture fits now: the menu's edit once it has loaded, else the fit the stream started with.
        public var currentVideoFit: VideoFit {
            menu.loaded
                ? menu.draft.videoFit
                : videoFit
        }

        /// The profile a cloud stream plays for.
        public var cloudProfile: UUID? {
            guard case .cloud(let request) = source else {
                return nil
            }
            return request.profile.uuid
        }

        /// The cloud title, for a cloud stream.
        public var cloudTitle: CloudStreamTitle? {
            guard case .cloud(let request) = source else {
                return nil
            }
            return request.title
        }

        /// The console and account the saved login PIN belongs to, for a stored console.
        var loginPINOwner: LoginPINOwner? {
            guard let pairing, let console = pairing.console.id else {
                return nil
            }
            return LoginPINOwner(consoleID: console, accountID: pairing.account)
        }
    }

    /// Everything the stream reacts to.
    public enum Action: Equatable {
        /// Starts a stream; a parent sends it.
        case start(StreamSource)

        /// Starts a console stream for a registered console; a parent sends it. With `keepsRoute` a local route is
        /// taken as it is, without asking the core, as a stream started again after sleep is.
        case startConsole(
            account: UUID,
            console: RegistrationFlow.ConsoleTarget,
            route: PlaybackRoute,
            keepsRoute: Bool = false
        )

        /// Leaves the stream with a plain disconnect, or dismisses a failure; a parent sends it.
        case stop

        /// Leaves the stream in the given way.
        case leave(StreamExitAction)

        /// Starts a failed cloud stream again.
        case retry

        /// Forgets a failure.
        case dismissFailure

        /// Something the user did on the stream screen.
        case view(Intent)

        /// An event from the session with this id.
        case event(StreamSessionID, StreamSessionEvent)

        /// The console or service ended the session with this id.
        case ended(StreamSessionID)

        /// The session with this id failed.
        case failed(StreamSessionID, StreamFailure)

        /// The stopping session with this id has closed.
        case stopped(StreamSessionID, StreamExitOutcome)

        /// A start stage stayed past its deadline.
        case deadlineElapsed(StreamSessionID, StreamDeadline)

        /// One second of the datacenter choice passed.
        case datacenterTick(StreamSessionID)

        /// The core answered a datacenter choice.
        case datacenterSent(StreamSessionID, String, accepted: Bool)

        /// The console answered a typed code.
        case accessSubmitted(UUID, Bool)

        /// No login PIN was saved for the console.
        case savedLoginPINMissing(UUID)

        /// The console answered the saved login PIN.
        case savedLoginPINSubmitted(UUID, Bool)

        /// The stream held long enough with a typed login PIN to remember it.
        case typedLoginPINVerified(UUID)

        /// The rest notice's time ran out.
        case restNoticeExpired(UUID)

        /// The wait for the console to leave its hidden screen after a Go to Home screen request ran out.
        case homeRequestExpired(UUID)

        /// The cloud title's layered artwork arrived.
        case loadingArtArrived(StreamSessionID, GameArtLayers)

        /// The cloud loading screen finished fading out.
        case loadingLeft(StreamSessionID)

        /// The rejected pairing offered by the failed session with this id was removed.
        case unpaired(StreamSessionID)

        /// The rejected pairing offered by the failed session with this id could not be removed.
        case unpairFailed(StreamSessionID)

        /// The closing warning shown for the session with this id ran its time.
        case closingNoticeExpired(StreamSessionID, CloudClosingNotice)

        /// The session with this id closed so its source can start again.
        case relaunchClosed(StreamSessionID)

        /// The PS5 cloud toasts.
        case toasts(CloudToastsReducer.Action)

        /// The stream menu.
        case menu(StreamMenuReducer.Action)

        /// The couch seats.
        case couch(CouchReducer.Action)

        /// The microphone.
        case microphone(MicrophoneReducer.Action)

        /// The Invitations panel.
        case invitations(CloudInvitationsFeature.Action)

        /// The Trophies panel.
        case trophies(StreamTrophiesFeature.Action)

        /// Kakusan hosting.
        case kakusan(KakusanHostFeature.Action)

        /// What the parent is told.
        case delegate(Delegate)
    }

    /// What the user did on the stream screen.
    public enum Intent: Equatable {
        /// Sends a typed code.
        case submitAccessCode(StreamAccessCode)

        /// Closes the code prompt.
        case cancelAccess

        /// Chooses an offered cloud datacenter.
        case chooseDatacenter(String)

        /// Asks the console to show its home screen.
        case goHome

        /// The hidden-screen notice's Home button took the controller from the game, or gave it back.
        case homeHoldsController(Bool)

        /// The text of the console keyboard changed.
        case keyboardEdited(UUID, String)

        /// The console keyboard was closed, with whether its text was accepted.
        case keyboardFinished(UUID, accepted: Bool)

        /// Removes the console's rejected pairing.
        case unpair

        /// Asks to leave the stream; a playing stream confirms first.
        case requestExit(String)
    }

    /// What the stream reports to its parent.
    public enum Delegate: Equatable {
        /// A session started.
        case started(StreamSessionID)

        /// The console asked for its login PIN.
        case loginPINRequested(StreamSessionID)

        /// The first frame was shown.
        case playing(StreamSessionID)

        /// The user or the parent left the stream.
        case closing

        /// The session is over, ended by the console or left.
        case ended(StreamSessionID)

        /// The console rejected the pairing and it was removed; pair again.
        case pairAgain(RegistrationFlow.ConsoleTarget)
    }

    /// The effects the stream cancels.
    enum CancelID: Hashable {
        /// The session and everything tied to it.
        case session
        /// The start stage deadline.
        case deadline
        /// The datacenter choice countdown.
        case datacenterTick
        /// The cloud loading artwork fetch.
        case loadingArt
        /// The rest notice timer.
        case restNotice
        /// The wait after a Go to Home screen request.
        case homeRequest
        /// Remembering a typed login PIN.
        case loginPINStore
        /// The window size change.
        case window
        /// The closing warning's timer.
        case closingNotice
    }

    /// How long the rest notice stays.
    static let restNoticeDuration: Duration = .seconds(8)
    /// How long the hidden-screen notice shows that it is going home before offering the button again.
    static let homeRequestPatience: Duration = .seconds(15)
    /// How long a stream must hold before a typed login PIN is remembered.
    static let typedLoginPINVerification: Duration = .seconds(5)

    /// Starts sessions and sends them commands.
    @Dependency(\.streamSession) var streamSession
    /// Makes session and operation ids.
    @Dependency(\.uuid) var uuid
    /// The time progress reports arrive.
    @Dependency(\.date.now) var now
    /// Times deadlines and notices.
    @Dependency(\.continuousClock) var clock
    /// The diagnostics log.
    @Dependency(\.logger) var logger
    /// The couch seat client.
    @Dependency(\.streamSession) var couchClient
    /// The consoles' saved login PINs, and removes a rejected pairing.
    @Dependency(\.consoles) var consoles
    /// Enters and leaves full screen.
    @Dependency(\.platform) var platform

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Scope(state: \.couch, action: \.couch) {
            CouchReducer()
        }
        Reduce(prepareInvite)
        Scope(state: \.kakusan, action: \.kakusan) {
            KakusanHostFeature()
        }
        Scope(state: \.microphone, action: \.microphone) {
            MicrophoneReducer()
        }
        Scope(state: \.toasts, action: \.toasts) {
            CloudToastsReducer()
        }
        Reduce { state, action in
            switch action {
            case .start, .startConsole, .stop, .leave, .retry, .dismissFailure:
                lifecycle(&state, action)
            case .view(let view):
                reduce(&state, view)
            case .event(let id, let event):
                receive(event, for: id, state: &state)
            case .ended, .failed, .stopped, .deadlineElapsed:
                conclude(&state, action)
            case .datacenterTick, .datacenterSent, .loadingArtArrived, .loadingLeft:
                reduceCloud(&state, action)
            case .accessSubmitted, .savedLoginPINMissing, .savedLoginPINSubmitted, .typedLoginPINVerified:
                reduceAccess(&state, action)
            case .restNoticeExpired(let id):
                restNoticeExpired(id, state: &state)
            case .homeRequestExpired(let id):
                homeRequestExpired(id, state: &state)
            case .unpaired(let id):
                unpairAnswered(id, removed: true, state: &state)
            case .unpairFailed(let id):
                unpairAnswered(id, removed: false, state: &state)
            case let .closingNoticeExpired(id, notice):
                closingNoticeExpired(notice, for: id, state: &state)
            case .relaunchClosed(let id):
                relaunchClosed(id, state: &state)
            case .menu(.delegate(.stopRequested(let exit))):
                stop(&state, exit: exit)
            case .menu(.delegate(.restartRequested)):
                relaunch(&state)
            case .menu(.delegate(.goHomeRequested)):
                goHome(&state)
            case .kakusan(let action):
                coordinate(action, in: &state)
            case .couch(.delegate(let delegate)):
                coordinate(delegate)
            case .couch:
                couchChanged(&state)
            case .invitations(.delegate(.joined)):
                .send(.menu(.returnToGameplay(save: true)))
            case .invitations(.delegate(.automaticJoinFailed(let failure))):
                toast(.received(CloudSystemNotice(
                    kind: .invitationJoinFailed,
                    detail: String(localized: StreamMenuInvitationsControls.message(failure))
                )), state: state)
            case .menu, .microphone, .invitations, .trophies, .toasts, .delegate:
                .none
            }
        }
        .onChange(of: \.session.isStreaming) { wasStreaming, streaming in
            Reduce { state, _ in
                streamingChanged(from: wasStreaming, to: streaming, state: &state)
            }
        }
        Scope(state: \.menu, action: \.menu) {
            StreamMenuReducer()
        }
        .ifLet(\.invitations, action: \.invitations) {
            CloudInvitationsFeature()
        }
        .ifLet(\.trophies, action: \.trophies) {
            StreamTrophiesFeature()
        }
    }
}

extension StreamFeature {
    private func lifecycle(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .start(let source):
            return begin(source, pairing: nil, state: &state)
        case let .startConsole(account, console, route, keepsRoute):
            return begin(
                Self.source(account: account, console: console, route: route, keepsRoute: keepsRoute),
                pairing: ConsolePairing(account: account, console: console),
                state: &state
            )
        case .stop:
            return stop(&state, exit: .disconnect)
        case .leave(let exit):
            return stop(&state, exit: exit)
        case .retry:
            guard case .failed = state.session, state.offersRetry, let source = state.source else {
                return .none
            }
            return begin(source.retried, pairing: state.pairing, state: &state)
        case .dismissFailure:
            guard case .failed = state.session else {
                return .none
            }
            state.session.dismiss()
            state.unpair = nil
            return .none
        default:
            return .none
        }
    }

    /// The source for a paired console.
    ///
    /// - Parameters:
    ///   - account: The profile that paired the console.
    ///   - console: The console.
    ///   - route: The route the user asked for.
    ///   - keepsRoute: Whether a local route is taken as it is rather than chosen by the core.
    /// - Returns: The console source.
    public static func source(
        account: UUID,
        console: RegistrationFlow.ConsoleTarget,
        route: PlaybackRoute,
        keepsRoute: Bool = false
    ) -> StreamSource {
        .console(
            ConsoleStreamTarget(
                profile: ProfileID(uuid: account),
                console: console.id.map(ConsoleID.init(uuid:)),
                address: console.address,
                kind: console.kind == .ps5
                    ? .ps5
                    : .ps4,
                name: console.name,
                remoteDeviceID: console.remoteDeviceID
            ),
            route: route == .remote
                ? .internet
                : keepsRoute
                    ? .homeOnly
                    : .home
        )
    }

    /// The source for a cloud title the library cleared to launch.
    ///
    /// - Parameter request: The library's launch request.
    /// - Returns: The cloud source, or `nil` when the title has no product id.
    public static func source(cloud request: CloudLaunchRequest) -> StreamSource? {
        guard let product = ProductID(rawValue: request.game.productId) else {
            return nil
        }
        let game = request.game
        return .cloud(CloudStreamRequest(
            profile: ProfileID(uuid: request.accountID),
            title: CloudStreamTitle(
                product: product,
                name: game.name,
                service: CloudService(rawValue: game.streamServiceType) ?? .psCloud,
                platform: game.platform,
                isOwned: game.isOwned,
                plusCatalog: game.plusCatalog,
                artwork: game.landscapeImageUrl ?? game.imageUrl,
                otherVersion: game.otherVersion?.product
            ),
            clearance: request.clearance,
            joining: request.joining
        ))
    }

    private func begin(_ source: StreamSource, pairing: ConsolePairing?,
                       state: inout State) -> Effect<Action> {
        let id = StreamSessionID(uuid: uuid())
        guard state.session.begin(id, source: source) else {
            return .none
        }
        return prepare(id, source: source, pairing: pairing, state: &state)
    }

    private func prepare(
        _ id: StreamSessionID,
        source: StreamSource,
        pairing: ConsolePairing?,
        state: inout State
    ) -> Effect<Action> {
        state.source = source
        state.pairing = pairing
        state.playedRoute = nil
        state.surface = nil
        state.displayProhibited = false
        state.connection = .receiving
        state.homeRequest = .idle
        state.homeHoldsController = false
        state.videoDisabled = false
        state.videoFit = VideoFit()
        state.progress = nil
        state.datacenter = nil
        state.bandwidth = nil
        state.access = .idle
        state.savedLoginPIN = .available
        state.restNotice = .hidden
        state.unpair = nil
        state.menu = Self.menu(for: source)
        state.menu.session = id
        state.invitations = Self.invitations(for: source)
        state.trophies = Self.trophies(for: source)
        if let console = Self.couchConsole(for: source) {
            state.couch.begin(
                console,
                hostAccount: pairing?.account,
                lights: couchClient.couchLights(),
                session: id
            )
        }
        let hosting: Effect<Action> = source.kind == .console && KakusanBuild.included
            ? KakusanHostFeature().arm(&state.kakusan).map(Action.kakusan)
            : .none
        return .merge(
            .send(.delegate(.started(id))),
            hosting,
            run(id, source: source),
            deadline(for: id, state: state),
            beginLoading(&state, id: id)
        )
    }

    private func run(_ id: StreamSessionID, source: StreamSource) -> Effect<Action> {
        .run { [streamSession] send in
            do {
                for try await event in streamSession.start(id, source) {
                    await send(.event(id, event))
                }
                await send(.ended(id))
            } catch is CancellationError {
            } catch let failure as StreamFailure {
                await send(.failed(id, failure))
            } catch {
                await send(.failed(id, .renderer))
            }
        }
        .cancellable(id: CancelID.session, cancelInFlight: true)
    }

    private static func menu(for source: StreamSource) -> StreamMenuReducer.State {
        switch source {
        case .console(let target, let route):
            return StreamMenuReducer.State(
                context: .console(PictureSettings.Route(remote: route == .internet), ps5: target.kind == .ps5)
            )
        case .cloud(let request):
            var menu = StreamMenuReducer.State(context: .cloud(request.title.service.rawValue))
            menu.offersSavedData = request.title.service == .psNow && request.title.platform.uppercased() == "PS4"
            return menu
        case .guest:
            return StreamMenuReducer.State(context: .guest)
        }
    }

    private static func couchConsole(for source: StreamSource) -> CouchConsole? {
        switch source {
        case .console(let target, _):
            target.kind == .ps4
                ? .ps4
                : .ps5
        case .cloud:
            .cloud
        case .guest:
            nil
        }
    }

    private func deadline(for id: StreamSessionID, state: State) -> Effect<Action> {
        guard case .starting(id, let stage) = state.session else {
            return .cancel(id: CancelID.deadline)
        }
        let deadline = StreamDeadline(stage)
        return .run { [clock] send in
            try await clock.sleep(for: deadline.duration)
            await send(.deadlineElapsed(id, deadline))
        }
        .cancellable(id: CancelID.deadline, cancelInFlight: true)
    }

    private func stop(_ state: inout State, exit requested: StreamExitAction) -> Effect<Action> {
        guard state.isPresented else {
            return .none
        }
        let wasStreaming = state.session.isStreaming
        let restAsked = requested == .restMode && state.kind == .console
        let exit: StreamExitAction = restAsked && wasStreaming
            ? .restMode
            : .disconnect
        guard let id = state.session.stop(exit) else {
            state.unpair = nil
            return .merge(close(&state), .send(.delegate(.closing)))
        }
        let refusedBeforePlaying = restAsked && !wasStreaming
        return .merge(
            close(&state),
            .send(.delegate(.closing)),
            .run { [streamSession] send in
                let outcome = await streamSession.leave(id, exit)
                await send(.stopped(
                    id,
                    refusedBeforePlaying
                        ? .restRefused
                        : outcome
                ))
            }
        )
    }

    private func close(_ state: inout State) -> Effect<Action> {
        state.access = .idle
        state.progress = nil
        state.menu.exitRequest = nil
        state.keyboard.send(.streamEnded)
        state.loading = .hidden
        state.closingNotice = nil
        let toasts: Effect<Action> = state.toasts.isEmpty
            ? .none
            : .send(.toasts(.clear))
        return .merge(
            toasts,
            state.invitations == nil
                ? .none
                : .send(.invitations(.streamEnded)),
            state.trophies == nil
                ? .none
                : .send(.trophies(.streamEnded)),
            .cancel(id: CancelID.closingNotice),
            .cancel(id: CancelID.deadline),
            .cancel(id: CancelID.datacenterTick),
            .cancel(id: CancelID.loadingArt),
            .send(.couch(.sessionEnded)),
            endHosting(&state)
        )
    }

    private func conclude(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .ended(let id):
            if state.kind == .cloud, state.session.isStarting {
                return fail(id, with: .stream(.finished, overInternet: true), state: &state)
            }
            guard state.session.end(id) else {
                return .none
            }
            return .merge(close(&state), .send(.delegate(.ended(id))))
        case let .failed(id, failure):
            return fail(id, with: failure, state: &state)
        case let .stopped(id, outcome):
            guard state.session.stopped(id, outcome: outcome) else {
                return .none
            }
            let ended = Effect<Action>.merge(.cancel(id: CancelID.session), .send(.delegate(.ended(id))))
            guard outcome == .restRefused else {
                return ended
            }
            return .merge(ended, showRestNotice(id, state: &state))
        case let .deadlineElapsed(id, deadline):
            guard let stage = state.session.stage, state.session.id == id, StreamDeadline(stage) == deadline,
                  !state.access.loginPINOpen else {
                return .none
            }
            let failing = fail(id, with: .timedOut(deadline), state: &state)
            guard case .startAttempt(let attempt) = deadline else {
                return .merge(failing, .cancel(id: CancelID.session))
            }
            return .merge(
                failing,
                .cancel(id: CancelID.session),
                .run { [logger] _ in
                    await logger.log(.videoStartupTimedOut(attempt: attempt))
                }
            )
        default:
            return .none
        }
    }

    private func fail(_ id: StreamSessionID, with failure: StreamFailure,
                      state: inout State) -> Effect<Action> {
        guard state.session.fail(id, with: failure) else {
            return .none
        }
        let closing = close(&state)
        let rejected = failure.rejectsPairing && state.kind == .console
        if rejected, let pairing = state.pairing {
            state.unpair = UnpairOffer(account: pairing.account, console: pairing.console)
        }
        return .merge(closing, logStartFailure(failure, state: state))
    }

    private func logStartFailure(_ failure: StreamFailure, state: State) -> Effect<Action> {
        guard case .console(_, let asked) = state.source, failure.outcome == nil else {
            return .none
        }
        let route = asked == .internet
            ? "Remote"
            : "Local"
        let text = StreamFailureMessage(failure, kind: .console).text.english
        return .run { [logger] _ in
            await logger.log(.diagnostic(.playback, .error, "\(route) play could not start: \(text)"))
        }
    }

    private func showRestNotice(_ session: StreamSessionID, state: inout State) -> Effect<Action> {
        let id = uuid()
        state.restNotice = .shown(id)
        return .merge(
            .run { [clock] send in
                try await clock.sleep(for: Self.restNoticeDuration)
                await send(.restNoticeExpired(id))
            }
            .cancellable(id: CancelID.restNotice, cancelInFlight: true),
            .run { [logger] _ in
                await logger.log(.diagnostic(
                    .playback, .warning,
                    "The console did not accept the rest mode request for session \(session.uuid); it was left on"
                ))
            }
        )
    }

    private func restNoticeExpired(_ id: UUID, state: inout State) -> Effect<Action> {
        if state.restNotice == .shown(id) {
            state.restNotice = .hidden
        }
        return .none
    }

    private func goHome(_ state: inout State) -> Effect<Action> {
        guard case .playing(let id) = state.session else {
            return .none
        }
        var waiting = Effect<Action>.none
        if state.displayProhibited {
            let request = uuid()
            state.homeRequest = .waiting(request)
            waiting = .run { [clock] send in
                try await clock.sleep(for: Self.homeRequestPatience)
                await send(.homeRequestExpired(request))
            }
            .cancellable(id: CancelID.homeRequest, cancelInFlight: true)
        }
        return .merge(waiting, .run { [streamSession, logger] _ in
            let sent = await streamSession.goHome(id)
            await logger.log(.diagnostic(
                .playback,
                sent
                    ? .info
                    : .warning,
                sent
                    ? "Asked the console to show its home screen"
                    : "The console home screen request was not sent because the stream is not active"
            ))
        })
    }

    private func homeRequestExpired(_ id: UUID, state: inout State) -> Effect<Action> {
        if state.homeRequest == .waiting(id) {
            state.homeRequest = .idle
        }
        return .none
    }

    private func streamingChanged(from wasStreaming: Bool, to streaming: Bool,
                                  state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if state.offersMicrophone, let id = state.session.id {
            let lifecycle: MicrophoneReducer.Action = streaming
                ? .streamStarted(id.uuid)
                : .streamEnded
            effects
                .append(MicrophoneReducer().apply(&state.microphone, action: lifecycle)
                    .map(Action.microphone))
        }
        if streaming, !wasStreaming, state.invitations?.pendingJoin != nil {
            effects.append(.send(.invitations(.streamStarted)))
        }
        if state.windowOwner == .stream, wasStreaming != streaming, !state.session.isRelaunching {
            effects.append(
                .run { [platform] _ in
                    if streaming {
                        await platform.enterFullScreen()
                    } else {
                        await platform.restoreWindow()
                    }
                }
                .cancellable(id: CancelID.window, cancelInFlight: true)
            )
        }
        return .merge(effects)
    }
}

extension StreamFeature {
    private func receive(_ event: StreamSessionEvent, for id: StreamSessionID,
                         state: inout State) -> Effect<Action> {
        guard state.session.accepts(id) else {
            return .none
        }
        switch event {
        case .presented, .pictureRoute, .videoFit, .videoDisabled, .displayProhibited:
            return receivePicture(event, state: &state)
        case .connectionWaiting(let waiting):
            state.connection = waiting
                ? .waiting
                : .receiving
            return .none
        case .route(let route):
            state.playedRoute = route
            return .none
        case .cloudStep, .datacenterOffered, .datacenterSelected, .closing, .cloudNotice, .recording,
             .captureThumbnail:
            return receiveCloud(event, for: id, state: &state)
        case .startRetried(let attempt):
            return retried(attempt, for: id, state: &state)
        case .progress(let progress):
            return report(progress, for: id, state: &state)
        case .accessRequested(let prompt):
            return accessRequested(prompt, for: id, state: &state)
        case .firstFrame:
            return firstFrame(id, state: &state)
        case .reconnecting(let attempt):
            return reconnecting(attempt, for: id, state: &state)
        case .reconnected:
            return reconnected(id, state: &state)
        case .couch(let couch):
            return .send(.couch(.event(couch)))
        case .lights(let lights):
            return .send(.couch(.lightsChanged(lights)))
        case .keyboard(let signal):
            return keyboardSignal(signal, state: &state)
        case .guest:
            return .none
        }
    }

    private func receivePicture(_ event: StreamSessionEvent, state: inout State) -> Effect<Action> {
        switch event {
        case .presented(let surface):
            state.surface = surface
            return .none
        case .pictureRoute(let route):
            return pictureRouteApplied(route, state: &state)
        case .videoFit(let fit):
            state.videoFit = fit
            return .none
        case .videoDisabled(let disabled):
            state.videoDisabled = disabled
            state.menu.videoDisabled = disabled
            return .none
        case .displayProhibited(let prohibited):
            state.displayProhibited = prohibited
            state.menu.displayProhibited = prohibited
            if !prohibited {
                state.homeHoldsController = false
            }
            guard !prohibited, state.homeRequest != .idle else {
                return .none
            }
            state.homeRequest = .idle
            return .cancel(id: CancelID.homeRequest)
        default:
            return .none
        }
    }

    private func receiveCloud(_ event: StreamSessionEvent, for id: StreamSessionID,
                              state: inout State) -> Effect<Action> {
        switch event {
        case .cloudStep(let step):
            let moved = state.session.updateStage(for: id) { stage in
                stage.advance(to: step)
            }
            return moved
                ? deadline(for: id, state: state)
                : .none
        case .datacenterOffered(let offer):
            return offered(offer, for: id, state: &state)
        case .datacenterSelected(let selection):
            state.datacenter = selection
            state.menu.datacenter = selection
            state.session.updateStage(for: id) { stage in
                stage.datacenterSelected()
            }
            return .cancel(id: CancelID.datacenterTick)
        case .closing(let notice):
            return showClosingNotice(notice, for: id, state: &state)
        case .cloudNotice(let notice):
            guard case .trophyEarned = notice.kind, state.trophies != nil else {
                return toast(.received(notice), state: state)
            }
            return .merge(toast(.received(notice), state: state), .send(.trophies(.earned)))
        case .recording(let banner):
            return toast(.recording(banner), state: state)
        case .captureThumbnail(let thumbnail):
            return toast(.thumbnail(thumbnail), state: state)
        default:
            return .none
        }
    }

    private func toast(_ action: CloudToastsReducer.Action, state: State) -> Effect<Action> {
        guard state.session.isStreaming else {
            return .none
        }
        return .send(.toasts(action))
    }

    private func showClosingNotice(
        _ notice: CloudClosingNotice,
        for id: StreamSessionID,
        state: inout State
    ) -> Effect<Action> {
        state.closingNotice = notice
        return .run { [clock] send in
            try await clock.sleep(for: CloudClosingNotice.shownFor)
            await send(.closingNoticeExpired(id, notice))
        }
        .cancellable(id: CancelID.closingNotice, cancelInFlight: true)
    }

    private func closingNoticeExpired(
        _ notice: CloudClosingNotice,
        for id: StreamSessionID,
        state: inout State
    ) -> Effect<Action> {
        guard state.session.accepts(id), state.closingNotice == notice else {
            return .none
        }
        state.closingNotice = nil
        return .none
    }

    private func relaunch(_ state: inout State) -> Effect<Action> {
        guard case .playing(let id) = state.session, state.source != nil, state.session.relaunch(id) else {
            return .none
        }
        return .merge(
            close(&state),
            .run { [streamSession] send in
                _ = await streamSession.leave(id, .disconnect)
                await send(.relaunchClosed(id))
            }
        )
    }

    private func relaunchClosed(_ id: StreamSessionID, state: inout State) -> Effect<Action> {
        guard let source = state.source else {
            return .none
        }
        let next = StreamSessionID(uuid: uuid())
        guard state.session.relaunched(id, as: next, source: source) else {
            return .none
        }
        return prepare(next, source: source, pairing: state.pairing, state: &state)
    }

    private func pictureRouteApplied(_ route: PictureSettings.Route, state: inout State) -> Effect<Action> {
        guard case .console(let current, let ps5) = state.menu.context, current != route else {
            return .none
        }
        let previous = state.menu
        state.menu = StreamMenuReducer.State(context: .console(route, ps5: ps5))
        state.menu.leaveAction = previous.leaveAction
        state.menu.session = previous.session
        state.menu.displayProhibited = previous.displayProhibited
        state.menu.videoDisabled = previous.videoDisabled
        state.menu.navigation = previous.navigation
        return .none
    }

    private func retried(_ attempt: Int, for id: StreamSessionID, state: inout State) -> Effect<Action> {
        let moved = state.session.updateStage(for: id) { stage in
            stage.retried(attempt)
        }
        guard moved else {
            return .none
        }
        guard !state.access.loginPINOpen else {
            return .cancel(id: CancelID.deadline)
        }
        return deadline(for: id, state: state)
    }

    private func offered(
        _ offer: CloudDatacenterLaunchOffer,
        for id: StreamSessionID,
        state: inout State
    ) -> Effect<Action> {
        let opened = state.session.updateStage(for: id) { stage in
            stage.offer(offer)
        }
        guard opened else {
            return .none
        }
        let seconds = offer.timeoutSeconds
        return .run { [clock] send in
            for _ in 0 ..< seconds {
                try await clock.sleep(for: .seconds(1))
                await send(.datacenterTick(id))
            }
        }
        .cancellable(id: CancelID.datacenterTick, cancelInFlight: true)
    }

    private func report(_ progress: StreamProgress, for id: StreamSessionID,
                        state: inout State) -> Effect<Action> {
        let starting = state.session.isStarting
        let reconnecting = state.session.isStreaming && progress.reconnecting
        guard starting || reconnecting else {
            return .none
        }
        if let detail = progress.detail(as: OperationProgress.self) {
            state.progress = TimedProgress(detail, at: now)
        }
        if let bandwidth = progress.bandwidth {
            state.bandwidth = bandwidth
            state.menu.bandwidth = bandwidth
        }
        if starting, state.kind == .cloud {
            state.session.updateStage(for: id) { stage in
                stage.queue(at: progress.queuePosition)
            }
        }
        return .none
    }

    private func firstFrame(_ id: StreamSessionID, state: inout State) -> Effect<Action> {
        guard state.session.firstFrame(for: id) else {
            return .none
        }
        state.progress = nil
        switch state.access {
        case .requested(.loginPIN), .recalling:
            state.access = .idle
        case .idle, .requested, .submitting, .failed:
            break
        }
        return .merge(
            .cancel(id: CancelID.deadline),
            .cancel(id: CancelID.datacenterTick),
            .send(.delegate(.playing(id))),
            leaveLoading(&state, id: id),
            rememberTypedLoginPIN(&state)
        )
    }

    private func reconnecting(_ attempt: Int, for id: StreamSessionID, state: inout State) -> Effect<Action> {
        let first = state.session.reconnectAttempt == nil
        guard state.session.reconnecting(attempt, for: id) else {
            return .none
        }
        state.connection = .receiving
        return first
            ? .send(.couch(.sessionReconnecting))
            : .none
    }

    private func reconnected(_ id: StreamSessionID, state: inout State) -> Effect<Action> {
        guard state.session.reconnected(for: id) else {
            return .none
        }
        state.progress = nil
        return .merge(.send(.couch(.sessionReconnected)), .send(.microphone(.streamReconnected)))
    }

    private func reduce(_ state: inout State, _ view: Intent) -> Effect<Action> {
        switch view {
        case .submitAccessCode(let code):
            return submit(code, state: &state)
        case .cancelAccess:
            let pad = state.access.passcodePad
            state.access = .idle
            if let pad {
                return .send(.couch(.cancel(pad: pad)))
            }
            return stop(&state, exit: .disconnect)
        case .chooseDatacenter(let name):
            return choose(name, state: &state)
        case .goHome:
            state.homeHoldsController = false
            return .send(.menu(.goHome))
        case .homeHoldsController(let held):
            state.homeHoldsController = held && state.displayProhibited && state.status == .playing
            return .none
        case let .keyboardEdited(id, text):
            return keyboard(.edited(id, text), state: &state)
        case let .keyboardFinished(id, accepted):
            return keyboard(
                accepted
                    ? .accepted(id)
                    : .rejected(id),
                state: &state
            )
        case .unpair:
            return unpair(&state)
        case .requestExit(let source):
            guard state.session.isStreaming else {
                return stop(&state, exit: .disconnect)
            }
            return .send(.menu(.requestExit(source)))
        }
    }

    private func choose(_ name: String, state: inout State) -> Effect<Action> {
        guard let id = state.session.liveID else {
            return .none
        }
        let chosen = state.session.updateStage(for: id) { stage in
            stage.updateDatacenterChoice { choice in
                choice.choose(name)
            }
        }
        guard chosen else {
            return .none
        }
        return .merge(
            .cancel(id: CancelID.datacenterTick),
            .run { [streamSession] send in
                let accepted = await streamSession.selectDatacenter(id, name)
                await send(.datacenterSent(id, name, accepted: accepted))
            }
        )
    }

    private func reduceCloud(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .datacenterTick(let id):
            let ticked = state.session.updateStage(for: id) { stage in
                stage.updateDatacenterChoice { choice in
                    choice.tick()
                }
            }
            guard ticked, state.session.stage?.datacenterChoice == .expired else {
                return .none
            }
            return .cancel(id: CancelID.datacenterTick)
        case let .datacenterSent(id, name, accepted):
            state.session.updateStage(for: id) { stage in
                stage.updateDatacenterChoice { choice in
                    choice.sent(name, accepted: accepted)
                }
            }
            return .none
        case let .loadingArtArrived(id, layers):
            guard state.session.id == id, state.session.isStarting, state.loading == .shown(.card) else {
                return .none
            }
            state.loading = .shown(.layered(layers))
            return .none
        case .loadingLeft(let id):
            guard state.session.id == id, state.loading.isLeaving else {
                return .none
            }
            state.loading = .hidden
            return .none
        default:
            return .none
        }
    }

    private func beginLoading(_ state: inout State, id: StreamSessionID) -> Effect<Action> {
        guard case .cloud(let request) = state.source else {
            state.loading = .hidden
            return .cancel(id: CancelID.loadingArt)
        }
        @Dependency(\.catalog) var catalog
        let product = request.title.product
        if let layers = catalog.knownArtLayers(product) {
            state.loading = .shown(.layered(layers))
            return .cancel(id: CancelID.loadingArt)
        }
        state.loading = .shown(.card)
        let account = request.profile.uuid
        return .run { [catalog] send in
            guard case .success(let found) = await catalog.gameDetails(account, product), let art = found.art,
                  let layers = await catalog.artLayers(art), !Task.isCancelled else {
                return
            }
            await send(.loadingArtArrived(id, layers))
        }
        .cancellable(id: CancelID.loadingArt, cancelInFlight: true)
    }

    private func leaveLoading(_ state: inout State, id: StreamSessionID) -> Effect<Action> {
        guard case .shown(let screen) = state.loading else {
            return .cancel(id: CancelID.loadingArt)
        }
        state.loading = .leaving(screen)
        return .merge(
            .cancel(id: CancelID.loadingArt),
            .run { [clock] send in
                try await clock.sleep(for: screen.exit)
                await send(.loadingLeft(id))
            }
        )
    }

    private func keyboardSignal(_ signal: ConsoleKeyboardSignal, state: inout State) -> Effect<Action> {
        switch signal {
        case .opened(let text):
            keyboard(.remoteOpened(uuid(), text), state: &state)
        case .textChanged(let text):
            keyboard(.remoteTextChanged(text), state: &state)
        case .closed:
            keyboard(.remoteClosed, state: &state)
        }
    }

    private func keyboard(_ event: ConsoleKeyboardEvent, state: inout State) -> Effect<Action> {
        let commands = state.keyboard.send(event)
        guard let id = state.session.liveID, !commands.isEmpty else {
            return .none
        }
        return .run { [streamSession, logger] _ in
            for command in commands {
                let sent = await streamSession.keyboard(id, command)
                guard !sent else {
                    continue
                }
                await logger.log(.diagnostic(
                    .playback, .warning,
                    "The console keyboard \(Self.describe(command)) was not sent because the stream is not active"
                ))
            }
        }
    }

    private static func describe(_ command: ConsoleKeyboardCommand) -> String {
        switch command {
        case .setText:
            "text"
        case .accept:
            "confirmation"
        case .reject:
            "dismissal"
        }
    }
}

extension StreamFeature {
    private func accessRequested(
        _ prompt: StreamAccessPrompt,
        for id: StreamSessionID,
        state: inout State
    ) -> Effect<Action> {
        switch prompt {
        case .controllerPasscode(let pad, let retry):
            state.access = .requested(prompt)
            return .send(.couch(.event(.passcodeRequested(pad: pad, retry: retry))))
        case .loginPIN(let retry):
            let login = loginPINRequested(retry: retry, for: id, state: &state)
            let delegate = Effect<Action>.send(.delegate(.loginPINRequested(id)))
            guard state.session.isStarting, state.access.loginPINOpen else {
                return .merge(delegate, login)
            }
            state.session.requestAccess(prompt, for: id)
            return .merge(delegate, login, .cancel(id: CancelID.deadline))
        }
    }

    private func loginPINRequested(retry: Bool, for id: StreamSessionID,
                                   state: inout State) -> Effect<Action> {
        guard let owner = state.loginPINOwner else {
            state.access = .requested(.loginPIN(retry: retry))
            return .none
        }
        if retry {
            let rejected = state.savedLoginPIN
            state.savedLoginPIN = .settled
            state.access = .requested(.loginPIN(retry: true))
            switch rejected {
            case .recalling, .recalled:
                return forgetLoginPIN(owner)
            case .available, .typed, .verifying, .settled:
                return .none
            }
        }
        guard state.savedLoginPIN == .available else {
            state.access = .requested(.loginPIN(retry: false))
            return .none
        }
        let attempt = uuid()
        state.savedLoginPIN = .recalling
        state.access = .recalling(attempt)
        return .run { [consoles, streamSession, logger] send in
            let code: StreamAccessCode?
            do {
                code = try await consoles.loginPIN(owner)
            } catch {
                await logger.log(.consoleWarning(
                    "The saved login PIN for console \(LogFormat.idPrefix(owner.consoleID)) could not be read: "
                        + LogFormat.error(error)
                ))
                code = nil
            }
            try Task.checkCancellation()
            guard let code else {
                await send(.savedLoginPINMissing(attempt))
                return
            }
            let accepted = await streamSession.submitAccessCode(id, .loginPIN(retry: false), code)
            try Task.checkCancellation()
            await send(.savedLoginPINSubmitted(attempt, accepted))
        }
        .cancellable(id: CancelID.session)
    }

    private func submit(_ code: StreamAccessCode, state: inout State) -> Effect<Action> {
        let prompt: StreamAccessPrompt
        switch state.access {
        case .requested(let value), .failed(let value):
            prompt = value
        case .idle, .recalling, .submitting:
            return .none
        }
        guard let id = state.session.liveID else {
            return .none
        }
        let attempt = uuid()
        state.access = .submitting(attempt, prompt)
        if prompt.isLoginPIN, state.loginPINOwner != nil {
            state.savedLoginPIN = .typed(code)
        }
        return .run { [streamSession] send in
            let accepted = await streamSession.submitAccessCode(id, prompt, code)
            await send(.accessSubmitted(attempt, accepted))
        }
    }

    private func reduceAccess(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .accessSubmitted(attempt, accepted):
            accessSubmitted(attempt, accepted: accepted, state: &state)
        case .savedLoginPINMissing(let attempt):
            savedLoginPINMissing(attempt, state: &state)
        case let .savedLoginPINSubmitted(attempt, accepted):
            savedLoginPINSubmitted(attempt, accepted: accepted, state: &state)
        case .typedLoginPINVerified(let attempt):
            typedLoginPINVerified(attempt, state: &state)
        default:
            .none
        }
    }

    private func accessSubmitted(_ attempt: UUID, accepted: Bool, state: inout State) -> Effect<Action> {
        guard case let .submitting(current, prompt) = state.access, current == attempt else {
            return .none
        }
        state.access = accepted
            ? .idle
            : .failed(prompt)
        guard prompt.isLoginPIN else {
            return .none
        }
        guard accepted else {
            if case .typed = state.savedLoginPIN {
                state.savedLoginPIN = .settled
            }
            return .none
        }
        return resume(&state)
    }

    private func savedLoginPINMissing(_ attempt: UUID, state: inout State) -> Effect<Action> {
        guard state.access == .recalling(attempt) else {
            return .none
        }
        state.savedLoginPIN = .settled
        return promptForLoginPIN(&state)
    }

    private func savedLoginPINSubmitted(_ attempt: UUID, accepted: Bool,
                                        state: inout State) -> Effect<Action> {
        guard state.access == .recalling(attempt) else {
            return .none
        }
        guard accepted else {
            state.savedLoginPIN = .settled
            return promptForLoginPIN(&state)
        }
        state.savedLoginPIN = .recalled
        state.access = .idle
        return resume(&state)
    }

    private func promptForLoginPIN(_ state: inout State) -> Effect<Action> {
        state.access = .requested(.loginPIN(retry: false))
        guard let id = state.session.liveID, state.session.isStarting else {
            return .none
        }
        state.session.requestAccess(.loginPIN(retry: false), for: id)
        return .cancel(id: CancelID.deadline)
    }

    private func resume(_ state: inout State) -> Effect<Action> {
        guard let id = state.session.liveID else {
            return .none
        }
        guard state.session.isStarting else {
            return verifyTypedLoginPIN(&state)
        }
        state.session.accessGranted(for: id)
        return deadline(for: id, state: state)
    }

    private func verifyTypedLoginPIN(_ state: inout State) -> Effect<Action> {
        guard case let .typed(code) = state.savedLoginPIN else {
            return .none
        }
        let attempt = uuid()
        state.savedLoginPIN = .verifying(attempt, code)
        return .run { [clock] send in
            try await clock.sleep(for: Self.typedLoginPINVerification)
            await send(.typedLoginPINVerified(attempt))
        }
        .cancellable(id: CancelID.session)
    }

    private func typedLoginPINVerified(_ attempt: UUID, state: inout State) -> Effect<Action> {
        guard case .verifying(attempt, let code) = state.savedLoginPIN else {
            return .none
        }
        guard state.session.isStreaming else {
            state.savedLoginPIN = .settled
            return .none
        }
        state.savedLoginPIN = .typed(code)
        return rememberTypedLoginPIN(&state)
    }

    private func rememberTypedLoginPIN(_ state: inout State) -> Effect<Action> {
        guard case let .typed(code) = state.savedLoginPIN, let owner = state.loginPINOwner else {
            return .none
        }
        state.savedLoginPIN = .settled
        return .run { [consoles, logger] _ in
            do {
                try await consoles.saveLoginPIN(owner, code)
            } catch {
                await logger.log(.consoleWarning(
                    "The login PIN for console \(LogFormat.idPrefix(owner.consoleID)) could not be remembered: "
                        + LogFormat.error(error)
                ))
            }
        }
        .cancellable(id: CancelID.loginPINStore, cancelInFlight: true)
    }

    private func forgetLoginPIN(_ owner: LoginPINOwner) -> Effect<Action> {
        .run { [consoles, logger] _ in
            do {
                try await consoles.clearLoginPIN(owner)
            } catch {
                await logger.log(.consoleWarning(
                    "The rejected login PIN for console \(LogFormat.idPrefix(owner.consoleID)) could not be forgotten: "
                        + LogFormat.error(error)
                ))
            }
        }
        .cancellable(id: CancelID.loginPINStore, cancelInFlight: true)
    }

    private func unpair(_ state: inout State) -> Effect<Action> {
        guard case .failed(let id, _) = state.session, let offer = state.unpair,
              offer.phase != .unpairing else {
            return .none
        }
        state.unpair?.phase = .unpairing
        return .run { [consoles] send in
            switch await consoles.unpair(offer.account, offer.console) {
            case .success:
                await send(.unpaired(id))
            case .failure:
                await send(.unpairFailed(id))
            }
        }
    }

    private func unpairAnswered(_ id: StreamSessionID, removed: Bool, state: inout State) -> Effect<Action> {
        guard state.session.id == id, let offer = state.unpair, offer.phase == .unpairing else {
            return .none
        }
        guard removed else {
            state.unpair?.phase = .refused
            return .none
        }
        state.unpair = nil
        state.session.dismiss()
        return .send(.delegate(.pairAgain(offer.console)))
    }
}

extension StreamFeature {
    private func coordinate(_ action: KakusanHostFeature.Action, in state: inout State) -> Effect<Action> {
        switch action {
        case .delegate(.claimSeat(let remote)):
            .send(.couch(.claimRemote(CouchRemoteInput(guest: remote.guest, name: remote.name))))
        case let .delegate(.reserveSeat(remote, pad)):
            .send(.couch(.reserveRemote(CouchRemoteInput(guest: remote.guest, name: remote.name), pad: pad)))
        case let .delegate(.showSeat(remote, pad)):
            .send(.couch(.seatRemote(CouchRemoteInput(guest: remote.guest, name: remote.name), pad: pad)))
        case .delegate(.releaseSeat(let guest)):
            .send(.couch(.releaseRemote(guest)))
        case .delegate(.notice(let notice)):
            .send(.couch(.post(.remote(notice))))
        default:
            syncSeats(&state)
        }
    }

    private func coordinate(_ delegate: CouchReducer.Delegate) -> Effect<Action> {
        switch delegate {
        case .remoteJoinFailed(let remote):
            .send(.kakusan(.seatDeclined(remote.guest)))
        case .remoteLeft(let remote):
            .send(.kakusan(.removeGuest(remote.guest)))
        case let .seatRemote(remote, controllerType, accountID):
            .send(.kakusan(.giveSeat(remote.guest, controllerType: controllerType, accountID: accountID)))
        case .controlsCommitted:
            .none
        }
    }

    private func couchChanged(_ state: inout State) -> Effect<Action> {
        if let pad = state.access.passcodePad, !state.couch.seats.awaitsPasscode(pad) {
            state.access = .idle
        }
        return syncSeats(&state)
    }

    private func syncSeats(_ state: inout State) -> Effect<Action> {
        let held = state.kakusan.hosting == .available
            ? max(0, state.kakusan.remoteReservations - state.couch.seats.remoteCount)
            : 0
        if state.couch.seats.heldForRemote != held {
            state.couch.seats.heldForRemote = held
        }
        let local = 1 + state.couch.seats.localCount
        guard !state.kakusan.guests.isEmpty, local != state.kakusan.localSeats else {
            return .none
        }
        return .send(.kakusan(.localSeatsChanged(local)))
    }

    private func prepareInvite(_ state: inout State, _ action: Action) -> Effect<Action> {
        if case .kakusan(.invite) = action {
            state.kakusan.localSeats = 1 + state.couch.seats.localCount
        }
        return .none
    }

    private func endHosting(_ state: inout State) -> Effect<Action> {
        guard state.kind == .console else {
            return .none
        }
        return KakusanHostFeature().disarm(&state.kakusan).map(Action.kakusan)
    }
}

extension StreamFeature.State {
    /// Whether the failure screen offers Try again: only for a cloud stream that did not end because its play
    /// time ran out.
    public var offersRetry: Bool {
        guard kind == .cloud else {
            return false
        }
        if case .stream(.consoleQuit(let reason), _)? = session.failure, reason?.endsPlayTime == true {
            return false
        }
        return true
    }

    /// Whether the stream takes the player's microphone: console and cloud streams do, Kakusan guest streams do
    /// not.
    public var offersMicrophone: Bool {
        switch kind {
        case .console, .cloud:
            true
        case .guest, nil:
            false
        }
    }
}

/// The offer to remove a console's pairing after the console rejected it.
public struct UnpairOffer: Equatable, Sendable {
    /// Where the offer is.
    public enum Phase: Equatable, Sendable {
        /// Offered to the user.
        case offered

        /// The pairing is being removed.
        case unpairing

        /// The pairing could not be removed.
        case refused
    }

    /// The account the pairing belongs to.
    public let account: UUID

    /// The registered console.
    public let console: RegistrationFlow.ConsoleTarget

    /// Creates an unpair offer.
    ///
    /// - Parameters:
    ///   - account: The account the pairing belongs to.
    ///   - console: The registered console.
    public init(account: UUID, console: RegistrationFlow.ConsoleTarget) {
        self.account = account
        self.console = console
    }

    /// Where the offer is.
    public var phase = Phase.offered
}

/// A parent's coarse view of a `StreamFeature`'s session.
public enum StreamStatus: Equatable, Sendable {
    /// Nothing is running and nothing failed.
    case idle

    /// The session is starting or waiting for the login PIN.
    case connecting

    /// Video is playing or reconnecting.
    case playing

    /// The user left and the session is closing.
    case stopping

    /// The session failed.
    case failed
}
