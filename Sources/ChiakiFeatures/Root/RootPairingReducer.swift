import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Moves between the add-console screen and pairing, and records what a pairing ends with.
///
/// The add-console screen's draft is kept while a pairing runs so that a failed pairing returns to the same
/// screen, with the failure shown and PlayStation preferred when the failure came over the internet.
struct RootPairingReducer: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    @Dependency(\.logger) private var logger

    /// Reacts to the add-console screen and the pairing screen.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .route(.addConsole(.delegate(let delegate))):
                return addConsoleReported(delegate, state: &state)
            case .route(.pairing(.delegate(let delegate))):
                return pairingReported(delegate, state: &state)
            default:
                return .none
            }
        }
    }

    /// Shows the add-console screen from the library, preferring PlayStation after a failed remote pairing.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The effects of showing the screen.
    func showAddConsole(state: inout State) -> Effect<Action> {
        guard state.route == .library else {
            return .none
        }
        state.addConsoleDraft = nil
        let retryingRemote = state.pairingFailure?.isOverInternet == true
            || state.registrationFailure?.isRemote == true
        guard let route = Self.addConsoleRoute(
            state,
            preferred: retryingRemote
                ? .playStation
                : nil
        ) else {
            return .none
        }
        return RootRouter.show(route, state: &state)
    }

    /// Forgets a console the stream found unpaired and pairs it again.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - state: The application's state.
    /// - Returns: The effects that start pairing or show the add-console screen.
    func pairAgain(_ console: RegistrationFlow.ConsoleTarget, state: inout State) -> Effect<Action> {
        guard state.route == .stream, let profile = state.selectedProfile else {
            return .none
        }
        state.appData.forgetPairing(console)
        guard console.remoteDeviceID != nil, profile.kind == .npsso else {
            return startPairing(console, state: &state)
        }
        guard let route = Self.addConsoleRoute(state, preferred: .playStation) else {
            return .none
        }
        return RootRouter.show(route, state: &state)
    }

    private static func addConsoleRoute(
        _ state: State,
        preferred: AddConsoleMode?,
        draft: AddConsoleFeature.Draft? = nil
    ) -> RootFeature.Route.State? {
        guard let profile = state.selectedProfile else {
            return nil
        }
        let modes: [AddConsoleMode] = profile.kind == .npsso
            ? AddConsoleMode.allCases.filter { !$0.needsSignIn || profile.kind.permits(.psnConsoles) }
            : [.manual]
        return .addConsole(AddConsoleFeature.State(
            account: profile.id,
            modes: modes,
            preferred: preferred,
            registered: state.appData.linkedConsoles,
            draft: draft
        ))
    }

    private func addConsoleReported(
        _ delegate: AddConsoleFeature.Action.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .startScanning:
            return .send(.discovery(.acquire(.addConsole)))
        case .stopScanning:
            return .send(.discovery(.release(.addConsole)))
        case .retryScanning:
            return .send(.discovery(.retry))
        case .pair(let target):
            return pair(target, state: &state)
        case .left:
            state.pairingFailure = nil
            state.addConsoleDraft = nil
            return RootRouter.show(state.home, state: &state)
        }
    }

    private func pair(_ target: RegistrationFlow.ConsoleTarget, state: inout State) -> Effect<Action> {
        guard state.selectedAccount != nil else {
            return .none
        }
        guard target.remoteDeviceID == nil else {
            guard state.selectedProfile?.kind == .npsso, target.remoteDeviceID?.count == 32 else {
                return .none
            }
            return startPairing(target, state: &state)
        }
        guard let address = ConsoleAddress(target.address) else {
            return .none
        }
        return startPairing(
            RegistrationFlow.ConsoleTarget(address: address.text, kind: target.kind),
            state: &state
        )
    }

    private func startPairing(_ console: RegistrationFlow.ConsoleTarget,
                              state: inout State) -> Effect<Action> {
        state.pairingFailure = nil
        guard let account = state.selectedProfile?.accountID.flatMap(AccountID.init(base64:)),
              let target = console.pairingTarget
        else {
            state.registrationFailure = nil
            state.pairingFailure = .invalidInput
            return .none
        }
        state.addConsoleDraft = state.route.addConsole?.draft
        let shown = RootRouter.show(
            .pairing(PairingFeature.State(account: account, target: target)),
            state: &state
        )
        return target.needsPIN
            ? shown
            : .merge(shown, .send(.route(.pairing(.start))))
    }

    private func pairingReported(_ delegate: PairingFeature.Action.Delegate,
                                 state: inout State) -> Effect<Action> {
        let account = state.selectedProfile.map {
            "\"\($0.name)\" (id \(LogFormat.idPrefix($0.id)))"
        } ?? "no account"
        switch delegate {
        case .attemptStarted(let target):
            return log(.info, PairingLog.started(target, for: account))
        case .attemptEnded(let target, let result, let elapsed):
            let level: LogLevel =
                switch result {
                case .success:
                    .info
                case .failure:
                    .error
                }
            return log(level, PairingLog.ended(target, result, elapsed: elapsed, for: account))
        case .paired(let console):
            state.appData.recordPairing(RegistrationFlow.ConsoleTarget(paired: console))
            state.addConsoleDraft = nil
            return .merge(RootRouter.show(.library, state: &state), .send(.consoleCatalog(.load)))
        case .left(_, let failure):
            let preferred: AddConsoleMode? = failure?.isOverInternet == true
                ? .playStation
                : nil
            let draft = state.addConsoleDraft
            state.addConsoleDraft = nil
            let returning = RootRouter.show(
                Self.addConsoleRoute(state, preferred: preferred, draft: draft) ?? state.home,
                state: &state
            )
            state.pairingFailure = failure
            return returning
        }
    }

    private func log(_ level: LogLevel, _ message: String) -> Effect<Action> {
        .run { [logger] _ in
            await logger.log(.diagnostic(.registration, level, message))
        }
    }
}
