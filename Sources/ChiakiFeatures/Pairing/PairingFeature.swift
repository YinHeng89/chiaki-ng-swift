import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Pairs one console: PIN entry for a home console, then the attempt and its progress.
///
/// The workflow is the `ChiakiModels/PairingFlow` machine. A home target opens on PIN entry and starts
/// when the view submits a valid PIN; an internet target opens ready and starts when the parent sends
/// ``Action/start``. Every progress report and the result carry the `ChiakiModels/OperationID` of the
/// attempt that produced them, so a cancelled or superseded attempt cannot move the workflow. A failed home
/// attempt returns to PIN entry with its failure; everything that ends the workflow is reported upward
/// through ``Action/Delegate``.
@Reducer
public struct PairingFeature {
    /// The pairing screen's state.
    @ObservableState
    public struct State: Equatable {
        /// The account the console is paired for.
        public let account: AccountID

        /// Where the workflow is.
        public internal(set) var flow: PairingFlow

        /// The PIN being typed. It is cleared when it is submitted.
        public var pin = ""

        /// When the running attempt last reported progress.
        public internal(set) var reportedAt: Date?

        /// Opens the workflow for a console.
        ///
        /// - Parameters:
        ///   - account: The account the console is paired for.
        ///   - target: The console and how it is reached.
        public init(account: AccountID, target: PairingTarget) {
            self.account = account
            flow = PairingFlow(target: target)
        }

        /// Whether the typed PIN can be submitted now.
        public var canSubmitPIN: Bool {
            guard case .enteringPIN = flow else {
                return false
            }
            return PairingPIN.accepts(pin)
        }
    }

    /// Everything the pairing screen reacts to.
    public enum Action: BindableAction, Equatable {
        /// A change to a bound field.
        case binding(BindingAction<State>)

        /// Something the user did on the screen.
        case view(View)

        /// Starts the attempt of an internet target, sent by the parent once the screen is shown.
        case start

        /// A progress report from an attempt.
        case attemptProgress(OperationID, PairingProgress)

        /// The result of an attempt, and how long it ran.
        case attemptFinished(OperationID, Result<PairedConsole, PairingFailure>, elapsed: Duration)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did on the screen.
        @CasePathable
        public enum View: Equatable {
            /// Pair with the typed PIN.
            case submitPIN

            /// Step back: stop the running attempt, or leave the workflow.
            case cancel
        }

        /// What the pairing screen reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// An attempt started for the target.
            case attemptStarted(PairingTarget)

            /// An attempt ended with its result after running for `elapsed`.
            case attemptEnded(PairingTarget, Result<PairedConsole, PairingFailure>, elapsed: Duration)

            /// The console was paired and saved; the workflow is over.
            case paired(PairedConsole)

            /// The user left, or an internet attempt failed; the workflow is over.
            case left(PairingTarget, PairingFailure?)
        }
    }

    private enum CancelID {
        case attempt
    }

    @Dependency(\.consoles) private var consoles
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date.now) private var now
    @Dependency(\.continuousClock) private var clock

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none
            case .view(.submitPIN):
                guard state.canSubmitPIN else {
                    return .none
                }
                let pin = state.pin
                state.pin = ""
                return begin(&state, pin: pin)
            case .start:
                guard case .ready = state.flow else {
                    return .none
                }
                return begin(&state, pin: nil)
            case .view(.cancel):
                return cancel(&state)
            case .attemptProgress(let id, let progress):
                if state.flow.report(progress, for: id) {
                    state.reportedAt = now
                }
                return .none
            case .attemptFinished(let id, let result, let elapsed):
                return finish(&state, id: id, result: result, elapsed: elapsed)
            }
        }
    }

    private func begin(_ state: inout State, pin: String?) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        guard let target = state.flow.target, state.flow.start(id) else {
            return .none
        }
        state.reportedAt = nil
        let account = state.account
        return .merge(
            .send(.delegate(.attemptStarted(target))),
            .run { [consoles, clock] send in
                let (reports, feed) = AsyncStream.makeStream(of: PairingProgress.self)
                let forwarding = Task {
                    for await progress in reports {
                        await send(.attemptProgress(id, progress))
                    }
                }
                var result = Result<PairedConsole, PairingFailure>.failure(.cancelled)
                let elapsed = await clock.measure {
                    result = await consoles.pair(account, target, pin) { progress in
                        feed.yield(progress)
                    }
                }
                feed.finish()
                await forwarding.value
                await send(.attemptFinished(id, result, elapsed: elapsed))
            }
            .cancellable(id: CancelID.attempt, cancelInFlight: true)
        )
    }

    private func cancel(_ state: inout State) -> Effect<Action> {
        let running = state.flow.attempt != nil
        guard state.flow.cancel() else {
            return .none
        }
        state.reportedAt = nil
        let cancellation: Effect<Action> = running
            ? .cancel(id: CancelID.attempt)
            : .none
        guard case .left(let target, let failure) = state.flow else {
            return cancellation
        }
        return .merge(cancellation, .send(.delegate(.left(target, failure))))
    }

    private func finish(
        _ state: inout State,
        id: OperationID,
        result: Result<PairedConsole, PairingFailure>,
        elapsed: Duration
    ) -> Effect<Action> {
        guard let attempt = state.flow.attempt, attempt.id == id, state.flow.finish(id, with: result) else {
            return .none
        }
        state.reportedAt = nil
        let ended = Effect<Action>.send(.delegate(.attemptEnded(attempt.target, result, elapsed: elapsed)))
        switch state.flow {
        case .paired(let console):
            return .concatenate(ended, .send(.delegate(.paired(console))))
        case .left(let target, let failure):
            return .concatenate(ended, .send(.delegate(.left(target, failure))))
        case .enteringPIN, .ready, .pairing:
            return ended
        }
    }
}
