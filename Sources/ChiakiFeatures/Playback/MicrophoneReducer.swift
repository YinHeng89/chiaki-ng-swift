import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Owns the stream microphone, feeding stream lifecycle and user toggles through `MicrophoneMachine` and
/// running
/// the permission, capture and mute effects it asks for, tagged with the operation that started them.
@Reducer public struct MicrophoneReducer {
    /// Whether a stream session can currently carry microphone audio.
    public enum Availability: Equatable, Sendable {
        /// No stream session is running.
        case unavailable
        /// The stream session with the given identifier is running.
        case available(UUID)
    }

    /// The microphone feature state.
    @ObservableState public struct State: Equatable {
        /// Which stream session, if any, the microphone can attach to.
        public var availability = Availability.unavailable
        /// The state machine that decides microphone transitions.
        public var machine = MicrophoneMachine()

        /// Creates an unavailable, switched off microphone.
        public init() {
        }

        /// The microphone phase from the state machine.
        public var phase: MicrophoneMachine.Phase {
            machine.phase
        }

        /// Whether a stream session is running that the microphone can join.
        public var available: Bool {
            availability != .unavailable
        }

        /// Whether the mute indicator should be lit: a stream is running but no microphone audio is being
        /// sent.
        public var indicatorLit: Bool {
            available && !machine.transmitting
        }
    }

    /// Events the microphone feature handles.
    public enum Action: Equatable, Sendable {
        /// A stream session with the given identifier started, so the microphone becomes available.
        case streamStarted(UUID)
        /// The stream ended, so any capture stops and the microphone becomes unavailable.
        case streamEnded
        /// The stream reconnected, so an active capture restarts.
        case streamReconnected
        /// The start preference for the given session loaded; `true` switches the microphone on.
        case startPreferenceLoaded(UUID, Bool)
        /// The user switched the microphone on or off.
        case toggle
        /// The permission request for the given operation finished with the given result.
        case permissionResolved(UUID, Bool)
        /// The capture for the given operation reported progress.
        case capture(UUID, MicrophoneCaptureEvent)
        /// A mute change for the given operation finished, with a failure if it could not be applied.
        case muteApplied(UUID, muted: Bool, failure: MicrophoneFailure?)
    }

    /// Cancels the capture effect belonging to one microphone operation.
    public struct CaptureID: Hashable, Sendable {
        /// The operation the capture belongs to.
        public let operation: UUID

        /// Creates a capture id.
        ///
        /// - Parameter operation: The operation the capture belongs to.
        public init(operation: UUID) {
            self.operation = operation
        }
    }

    /// Cancellation identifiers for the reducer's single in-flight effects.
    public enum CancelID: Sendable {
        /// The pending permission request.
        case permission
        /// The pending start preference read.
        case preference
        /// The latest mute change.
        case mute
        /// The latest indicator light update.
        case indicator
    }

    /// The client that performs microphone side effects.
    @Dependency(\.streamSession) var client
    /// Generates operation identifiers for each microphone start.
    @Dependency(\.uuid) var uuid

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce(apply)
    }

    /// Reduces an action and, when the indicator should change as a result, also updates the mute indicator,
    /// cancelling any earlier indicator update still in flight.
    /// - Parameters:
    ///   - state: The state to update.
    ///   - action: The action to handle.
    /// - Returns: The effects for the action, merged with an indicator update when needed.
    public func apply(_ state: inout State, action: Action) -> Effect<Action> {
        let lit = state.indicatorLit
        let effect = reduce(&state, action: action)
        guard state.indicatorLit != lit else {
            return effect
        }
        let indicator = state.indicatorLit
        return .merge(
            effect,
            .run { [client] _ in
                guard !Task.isCancelled else {
                    return
                }
                await client.indicateMicrophone(indicator)
            }
            .cancellable(id: CancelID.indicator, cancelInFlight: true)
        )
    }

    private func reduce(_ state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .streamStarted, .streamEnded, .streamReconnected:
            return streamChanged(action, state: &state)
        case let .startPreferenceLoaded(session, enabled):
            guard enabled, state.availability == .available(session), state.machine.phase == .off else {
                return .none
            }
            return perform(state.machine.handle(.toggle(uuid())))
        case .toggle:
            guard state.available else {
                return .none
            }
            return perform(state.machine.handle(.toggle(uuid())))
        case let .permissionResolved(operation, granted):
            return perform(state.machine.handle(.permission(operation, granted: granted)))
        case .capture(let operation, .started):
            return perform(state.machine.handle(.connected(operation)))
        case .capture(let operation, .failed(let failure)):
            return perform(state.machine.handle(.failed(operation, failure)))
        case let .muteApplied(operation, muted, failure):
            return perform(state.machine.handle(.muteApplied(operation, muted: muted, failure: failure)))
        }
    }

    private func streamStarted(_ session: UUID, state: inout State) -> Effect<Action> {
        guard state.availability != .available(session) else {
            return .none
        }
        let commands = state.machine.handle(.reset)
        state.availability = .available(session)
        return .merge(
            perform(commands),
            .run { [client] send in
                await send(.startPreferenceLoaded(session, await client.microphoneStartPreference()))
            }
            .cancellable(id: CancelID.preference, cancelInFlight: true)
        )
    }

    private func streamChanged(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case .streamStarted(let session):
            streamStarted(session, state: &state)
        case .streamReconnected:
            streamReconnected(&state)
        default:
            streamEnded(&state)
        }
    }

    private func streamReconnected(_ state: inout State) -> Effect<Action> {
        switch state.machine.phase {
        case .connecting, .live:
            let stop = state.machine.handle(.reset)
            return .merge(perform(stop), perform(state.machine.handle(.toggle(uuid()))))
        case .off, .requestingPermission, .denied, .failed:
            return .none
        }
    }

    private func streamEnded(_ state: inout State) -> Effect<Action> {
        state.availability = .unavailable
        return .merge(
            perform(state.machine.handle(.reset)),
            .cancel(id: CancelID.permission),
            .cancel(id: CancelID.preference)
        )
    }

    private func perform(_ commands: [MicrophoneMachine.Command]) -> Effect<Action> {
        .merge(commands.map(perform))
    }

    private func perform(_ command: MicrophoneMachine.Command) -> Effect<Action> {
        switch command {
        case .requestPermission(let operation):
            return .run { [client] send in
                await send(.permissionResolved(operation, await client.requestMicrophonePermission()))
            }
            .cancellable(id: CancelID.permission, cancelInFlight: true)
        case .startCapture(let operation):
            return .run { [client] send in
                for await event in client.captureMicrophone(operation) {
                    await send(.capture(operation, event))
                }
            }
            .cancellable(id: CaptureID(operation: operation), cancelInFlight: true)
        case .stopCapture(let operation):
            return .merge(.cancel(id: CaptureID(operation: operation)), .cancel(id: CancelID.mute))
        case let .setMuted(operation, muted):
            return .run { [client] send in
                guard !Task.isCancelled else {
                    return
                }
                let failure = await client.setMicrophoneMuted(operation, muted)
                await send(.muteApplied(operation, muted: muted, failure: failure))
            }
            .cancellable(id: CancelID.mute, cancelInFlight: true)
        }
    }
}
