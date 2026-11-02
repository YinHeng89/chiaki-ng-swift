import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Starts again the console stream that the Mac's sleep interrupted, when the resume-after-wake setting is on.
///
/// The workflow is the ``WakeResume`` machine. The parent reports sleep with the stream that was running,
/// and wake; after ``resumeDelay`` the feature asks for the stream with ``Action/Delegate/resume(_:)`` and
/// gives up after ``replayDeadline`` unless the parent reports that a stream started. Every timer carries the
/// id of the resume that started it.
@Reducer
public struct WakeResumeFeature {
    /// How long after wake the stream is started again.
    public static let resumeDelay: Duration = .seconds(3)

    /// How long the parent has to start the stream before the resume gives up.
    public static let replayDeadline: Duration = .seconds(10)

    /// The resume's state.
    @ObservableState
    public struct State: Equatable {
        /// Where the resume is.
        public internal(set) var machine = WakeResume.idle

        /// Creates the state with nothing to resume.
        public init() {
        }
    }

    /// Everything the resume reacts to.
    public enum Action: Equatable {
        /// The Mac is going to sleep; `active` is the stream that runs, if one does.
        case sleeping(active: StreamTarget?)

        /// The Mac woke.
        case woke

        /// The delay of a resume passed.
        case due(UUID)

        /// A resume ended without a stream: the setting is off, or its deadline passed.
        case skipped(UUID)

        /// A stream started.
        case streamStarted

        /// The user did something else; abandons the resume.
        case interrupted

        /// The parent could not start the stream.
        case refused

        /// What the parent is told.
        case delegate(Delegate)

        /// What the resume asks of its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// Start this stream again, without changing the selected account or console.
            case resume(StreamTarget)
        }
    }

    private enum CancelID {
        case resume
    }

    @Dependency(\.uuid) private var uuid
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.settings) private var power

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .sleeping(let active):
                switch (active, state.machine) {
                case (let target?, _):
                    state.machine = .interrupted(target)
                case (nil, .waiting(_, let target)), (nil, .replaying(_, let target)):
                    state.machine = .interrupted(target)
                case (nil, .interrupted):
                    break
                case (nil, .idle):
                    break
                }
                return .cancel(id: CancelID.resume)
            case .woke:
                guard case .interrupted(let target) = state.machine else {
                    return .none
                }
                let id = uuid()
                state.machine = .waiting(id, target)
                return .run { [clock, power] send in
                    let enabled = (try? await power.load(ConsolePowerSettings.self).resumeAfterWake) ?? false
                    guard enabled else {
                        await send(.skipped(id))
                        return
                    }
                    try await clock.sleep(for: Self.resumeDelay)
                    await send(.due(id))
                }
                .cancellable(id: CancelID.resume, cancelInFlight: true)
            case .due(let id):
                guard case .waiting(id, let target) = state.machine else {
                    return .none
                }
                state.machine = .replaying(id, target)
                return .merge(
                    .send(.delegate(.resume(target))),
                    .run { [clock] send in
                        try await clock.sleep(for: Self.replayDeadline)
                        await send(.skipped(id))
                    }
                    .cancellable(id: CancelID.resume, cancelInFlight: true)
                )
            case .skipped(let id):
                switch state.machine {
                case .waiting(id, _), .replaying(id, _):
                    state.machine = .idle
                case .idle, .interrupted, .waiting, .replaying:
                    break
                }
                return .none
            case .streamStarted:
                guard case .replaying = state.machine else {
                    return .none
                }
                state.machine = .idle
                return .cancel(id: CancelID.resume)
            case .interrupted, .refused:
                guard state.machine != .idle else {
                    return .none
                }
                state.machine = .idle
                return .cancel(id: CancelID.resume)
            case .delegate:
                return .none
            }
        }
    }
}

/// Resuming a console stream that the Mac's sleep interrupted, as a finite state machine.
///
/// ```
/// idle --sleep while streaming--> interrupted --wake--> waiting --due--> replaying --stream starts--> idle
/// waiting --setting off--> idle         replaying --deadline / refused--> idle
/// any --user acts--> idle
/// ```
public enum WakeResume: Equatable, Sendable {
    /// Nothing to resume.
    case idle

    /// Sleep interrupted the stream of this target.
    case interrupted(StreamTarget)

    /// The Mac woke; the resume with this id waits for its delay.
    case waiting(UUID, StreamTarget)

    /// The resume with this id asked for the stream to start again.
    case replaying(UUID, StreamTarget)
}
