import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Connects to a console without the user picking it: the console set to connect at launch, or one a launch
/// request names.
///
/// The workflow is the ``AutoConnect`` machine. It waits for the library, finds the console with the root's
/// discovery (held through ``Action/Delegate/acquireDiscovery`` and ``Action/Delegate/releaseDiscovery``),
/// wakes it when it rests, and asks the parent to start the stream with ``Action/Delegate/play(_:route:)``.
/// Every step and deadline carries the run id that started it, so an abandoned run cannot move the machine.
@Reducer
public struct AutoConnectFeature {
    /// The automatic connection's state.
    @ObservableState
    public struct State: Equatable {
        /// Where the automatic connection is.
        public internal(set) var machine = AutoConnect.idle

        /// Whether the connect-at-launch setting was checked this run of the app.
        public internal(set) var launchCheck = AutoConnect.LaunchCheck.pending

        /// What the connection knows about the saved accounts and consoles.
        public internal(set) var library = AutoConnectLibrary.pending

        /// Whether a stream runs, as last told by the parent before an action reached the connection.
        public internal(set) var activity = AutoConnect.Activity.free

        /// Creates the state before the library is known.
        public init() {
        }
    }

    /// Everything the automatic connection reacts to.
    public enum Action: Equatable {
        /// The app became active; checks the connect-at-launch setting once.
        case launch

        /// Connects to a console, replacing any run in progress.
        case start(UUID, AutoConnect.StartMode)

        /// Abandons the run in progress.
        case cancel

        /// Dismisses a shown failure.
        case dismiss

        /// The library changed.
        case libraryChanged(AutoConnectLibrary)

        /// The root's discovery sees these consoles.
        case discovered(DiscoverySnapshot)

        /// The root's discovery stopped.
        case discoveryFailed

        /// The user did something else, or another stream started; abandons the run in progress.
        case interrupted

        /// The parent could not start the stream for this plan.
        case refused(AutoConnect.Plan)

        /// The connect-at-launch setting was read for a run.
        case launchSettingLoaded(UUID, UUID?)

        /// The connect-at-launch setting could not be read for a run.
        case launchSettingFailed(UUID)

        /// A wake request of a run was sent, or failed.
        case wakeSent(UUID, Bool)

        /// A run's step ran out of time.
        case deadline(UUID, AutoConnect.Step)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the automatic connection asks of its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// Start looking for consoles on the local network.
            case acquireDiscovery

            /// Stop looking for consoles for this connection.
            case releaseDiscovery

            /// Start the stream of a plan over a route.
            case play(AutoConnect.Plan, route: PlaybackRoute)
        }
    }

    /// Cancels a run's deadline timer and its in-flight launch-setting read or wake request.
    public enum CancelID: Sendable {
        /// The deadline of the current step, and the step's own work.
        case deadline, step
    }

    /// Makes the id of each new run.
    @Dependency(\.uuid) var uuid
    /// Times each step's deadline.
    @Dependency(\.continuousClock) var clock
    /// Reads the connect-at-launch setting and wakes consoles.
    @Dependency(\.consoles) var consoleLaunch
    /// Writes the connection's diagnostic trace.
    @Dependency(\.logger) var logger

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        AutoConnectLaunchCheck()
        Reduce { state, action in
            switch action {
            case .launch:
                guard state.launchCheck == .pending else {
                    return .none
                }
                state.launchCheck = .done
                guard state.library != .unavailable, state.activity == .free, !state.machine.isActive else {
                    return .none
                }
                return request(.launchSetting, state: &state)
            case let .start(consoleID, mode):
                let abandoned = abandon(&state)
                return .concatenate(abandoned, request(.console(consoleID, mode), state: &state))
            case .cancel, .interrupted:
                return abandon(&state)
            case .dismiss:
                if case .failed = state.machine {
                    state.machine = .idle
                }
                return .none
            case .libraryChanged(let library):
                state.library = library
                return libraryChanged(&state)
            case .discovered(let snapshot):
                return observe(snapshot, state: &state)
            case .discoveryFailed:
                guard case .discovering(_, let plan) = state.machine else {
                    return .none
                }
                return expired(.discovery, plan: plan, state: &state)
            case .refused(let plan):
                state.machine = .failed(plan.name, .busy)
                return .none
            case let .wakeSent(run, sent):
                return wakeSent(run, sent: sent, state: &state)
            case let .deadline(run, step):
                return deadlinePassed(run, step: step, state: &state)
            case .launchSettingLoaded, .launchSettingFailed, .delegate:
                return .none
            }
        }
    }

    private func libraryChanged(_ state: inout State) -> Effect<Action> {
        guard case .awaitingLibrary(_, let request) = state.machine else {
            return .none
        }
        switch state.library {
        case .pending:
            return .none
        case .ready:
            return proceed(request, state: &state)
        case .unavailable:
            return libraryUnavailable(request, state: &state)
        }
    }

    private func wakeSent(_ run: UUID, sent: Bool, state: inout State) -> Effect<Action> {
        guard case .waking(run, let plan) = state.machine else {
            return .none
        }
        guard sent else {
            return finish(.failed(plan.name, .wakeFailed), state: &state)
        }
        state.machine = .awaitingWake(run, plan)
        return deadline(run, .wake, after: AutoConnect.wakeTimeout)
    }

    private func deadlinePassed(_ run: UUID, step: AutoConnect.Step, state: inout State) -> Effect<Action> {
        switch (state.machine, step) {
        case (.awaitingLibrary(run, let request), .library):
            return libraryUnavailable(request, state: &state)
        case (.discovering(run, let plan), .discovery), (.waking(run, let plan), .wake),
             (.awaitingWake(run, let plan), .wake):
            return expired(step, plan: plan, state: &state)
        default:
            return .none
        }
    }

    private func request(_ request: AutoConnect.Request, state: inout State) -> Effect<Action> {
        guard case .ready = state.library else {
            let run = uuid()
            state.machine = .awaitingLibrary(run, request)
            return deadline(run, .library, after: AutoConnect.libraryTimeout)
        }
        return proceed(request, state: &state)
    }

    private func libraryUnavailable(_ request: AutoConnect.Request, state: inout State) -> Effect<Action> {
        switch request {
        case .launchSetting:
            return finish(.idle, state: &state)
        case .console:
            return finish(.failed(nil, .storage), state: &state)
        }
    }

    private func proceed(_ request: AutoConnect.Request, state: inout State) -> Effect<Action> {
        let cancelLibraryWait: Effect<Action> = .cancel(id: CancelID.deadline)
        switch request {
        case .launchSetting:
            return .merge(cancelLibraryWait, AutoConnectLaunchCheck().read(&state))
        case let .console(consoleID, mode):
            state.machine = .idle
            return .concatenate(cancelLibraryWait, begin(consoleID, mode: mode, state: &state))
        }
    }

    /// Starts connecting to a console the library knows, from finding it on the network or from launching it.
    ///
    /// - Parameters:
    ///   - consoleID: The console.
    ///   - mode: Whether to stream, over which route, or only wake the console.
    ///   - state: The connection's state.
    /// - Returns: The effects of the first step.
    func begin(_ consoleID: UUID, mode: AutoConnect.StartMode, state: inout State) -> Effect<Action> {
        let plan: AutoConnect.Plan
        switch state.library.plan(for: consoleID, mode: mode) {
        case .success(let found):
            plan = found
        case .failure(let failure):
            state.machine = .failed(nil, failure)
            return .none
        }
        guard state.activity == .free else {
            state.machine = .failed(plan.name, .busy)
            return .none
        }
        if mode == .stream(.remote) {
            guard plan.console.remoteDeviceID != nil else {
                state.machine = .failed(plan.name, .remoteUnavailable)
                return .none
            }
            return launch(plan, state: &state)
        }
        let run = uuid()
        state.machine = .discovering(run, plan)
        return .merge(
            .run { [logger] _ in
                await logger.log(.consoleDiagnostic(
                    "Auto-connect: looking for \"\(plan.name)\" on the local network"
                ))
            },
            deadline(run, .discovery, after: AutoConnect.discoveryTimeout),
            .send(.delegate(.acquireDiscovery))
        )
    }

    private func observe(_ snapshot: DiscoverySnapshot, state: inout State) -> Effect<Action> {
        guard let run = state.machine.run, let plan = state.machine.plan,
              let match = snapshot.match(for: plan.console)
        else {
            return .none
        }
        guard match.standby else {
            return launch(plan, state: &state)
        }
        guard case .discovering = state.machine else {
            return .none
        }
        state.machine = .waking(run, plan)
        return .merge(
            deadline(run, .wake, after: AutoConnect.wakeTimeout),
            .run { [consoleLaunch] send in
                do {
                    try await consoleLaunch.wake(plan.account, plan.console, match.address)
                    try Task.checkCancellation()
                    await send(.wakeSent(run, true))
                } catch is CancellationError {
                } catch {
                    await send(.wakeSent(run, false))
                }
            }
            .cancellable(id: CancelID.step, cancelInFlight: true)
        )
    }

    private func expired(_ step: AutoConnect.Step, plan: AutoConnect.Plan,
                         state: inout State) -> Effect<Action> {
        switch (step, plan.mode) {
        case (_, .stream):
            return launch(plan, state: &state)
        case (.discovery, .wake), (.library, .wake):
            return finish(.failed(plan.name, .notFound), state: &state)
        case (.wake, .wake):
            return finish(.failed(plan.name, .wakeTimedOut), state: &state)
        }
    }

    private func launch(_ plan: AutoConnect.Plan, state: inout State) -> Effect<Action> {
        guard case .stream(let route) = plan.mode else {
            return finish(.idle, state: &state)
        }
        return .concatenate(finish(.idle, state: &state), .send(.delegate(.play(plan, route: route))))
    }

    private func finish(_ next: AutoConnect, state: inout State) -> Effect<Action> {
        state.machine = next
        return .merge(
            .cancel(id: CancelID.deadline),
            .cancel(id: CancelID.step),
            .send(.delegate(.releaseDiscovery))
        )
    }

    private func abandon(_ state: inout State) -> Effect<Action> {
        guard state.machine.isActive else {
            if case .failed = state.machine {
                state.machine = .idle
            }
            return .none
        }
        return finish(.idle, state: &state)
    }

    private func deadline(_ run: UUID, _ step: AutoConnect.Step, after duration: Duration) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: duration)
            await send(.deadline(run, step))
        }
        .cancellable(id: CancelID.deadline, cancelInFlight: true)
    }
}

/// Reads the console set to connect at launch and starts connecting to it.
///
/// Only the answer of the read the machine still waits for is followed. A setting that cannot be read leaves
/// the connection idle and writes a warning.
private struct AutoConnectLaunchCheck: Reducer {
    /// The automatic connection's state.
    typealias State = AutoConnectFeature.State

    /// What the automatic connection reacts to.
    typealias Action = AutoConnectFeature.Action

    @Dependency(\.uuid) private var uuid
    @Dependency(\.consoles) private var consoleLaunch
    @Dependency(\.logger) private var logger

    /// Reacts to the launch setting's answers.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .launchSettingLoaded(run, consoleID):
                guard state.machine == .checkingLaunchSetting(run) else {
                    return .none
                }
                state.machine = .idle
                guard let consoleID else {
                    return .none
                }
                return AutoConnectFeature().begin(consoleID, mode: .stream(.local), state: &state)
            case .launchSettingFailed(let run):
                guard state.machine == .checkingLaunchSetting(run) else {
                    return .none
                }
                state.machine = .idle
                return .run { [logger] _ in
                    await logger.log(.consoleWarning(
                        "Auto-connect: the console to connect at launch could not be read, so none was started"
                    ))
                }
            default:
                return .none
            }
        }
    }

    /// Starts reading the connect-at-launch setting for a new run.
    ///
    /// - Parameter state: The automatic connection's state.
    /// - Returns: The effect that reads the setting.
    func read(_ state: inout State) -> Effect<Action> {
        let run = uuid()
        state.machine = .checkingLaunchSetting(run)
        return .run { [consoleLaunch] send in
            do {
                let consoleID = try await consoleLaunch.launchConsole()
                try Task.checkCancellation()
                await send(.launchSettingLoaded(run, consoleID))
            } catch is CancellationError {
            } catch {
                await send(.launchSettingFailed(run))
            }
        }
        .cancellable(id: AutoConnectFeature.CancelID.step, cancelInFlight: true)
    }
}

/// What an automatic connection knows about the saved accounts and consoles.
public enum AutoConnectLibrary: Equatable, Sendable {
    /// The accounts or the consoles have not been read yet.
    case pending

    /// The pairings, and the account the user selected, if any.
    case ready([RegistrationFlow.Registration], selected: UUID?)

    /// The accounts or the consoles could not be read.
    case unavailable

    /// Finds the pairing to connect to a console with, preferring the selected account's.
    ///
    /// - Parameters:
    ///   - consoleID: The console.
    ///   - mode: Whether to stream, over which route, or only wake the console.
    /// - Returns: The plan, or ``AutoConnect/Failure/storage`` when the library is not read and
    ///   ``AutoConnect/Failure/notRegistered`` when no account is paired with the console.
    public func plan(for consoleID: UUID,
                     mode: AutoConnect.StartMode) -> Result<AutoConnect.Plan, AutoConnect.Failure> {
        guard case let .ready(registrations, selected) = self else {
            return .failure(.storage)
        }
        let candidates = registrations.filter {
            $0.console.id == consoleID
        }
        guard let registration = candidates.first(where: { $0.profileID == selected }) ?? candidates.first
        else {
            return .failure(.notRegistered)
        }
        return .success(AutoConnect.Plan(
            account: registration.profileID, consoleID: consoleID, console: registration.console, mode: mode
        ))
    }
}
