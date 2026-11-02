import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Quitting the app, the Mac going to sleep and the Mac waking.
///
/// Quitting follows `ChiakiModels/Termination`: the parent is told to stop every stream and session, the
/// native sessions are shut down, and only the shutdown that started completes it. Sleep stops streaming
/// before the Mac is allowed to sleep, resting a streamed console when the setting asks for it; once the app
/// is quitting, sleep and wake are let through without touching anything.
@Reducer
public struct LifecycleFeature {
    /// The lifecycle's state.
    @ObservableState
    public struct State: Equatable {
        /// Whether the app is quitting.
        public internal(set) var termination: Termination

        /// Creates the state.
        ///
        /// - Parameter termination: Whether the app is quitting.
        public init(termination: Termination = .running) {
            self.termination = termination
        }
    }

    /// Everything the lifecycle reacts to.
    public enum Action: Equatable {
        /// The user asked to quit.
        case terminationRequested

        /// The shutdown with this id finished.
        case terminationCompleted(OperationID)

        /// The Mac is going to sleep after the notification with this number; `consoleStreaming` says whether
        /// a console stream runs, `stream` is the stream session open as sleep began and `guestJoin` the id of
        /// the guest join shown then.
        case systemWillSleep(Int, consoleStreaming: Bool, stream: StreamSessionID?, guestJoin: UUID?)

        /// Sleep stopped the stream session and the guest join with these ids, the ones open as sleep began.
        case sleepStoppedStream(StreamSessionID?, guestJoin: UUID?)

        /// The Mac woke.
        case systemDidWake

        /// The network the Mac uses changed.
        case networkChanged

        /// What the parent is told.
        case delegate(Delegate)

        /// What the lifecycle asks of its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The app is quitting: stop every stream and session.
            case terminating

            /// The Mac is going to sleep.
            case sleeping

            /// Sleep stopped the stream session and the guest join with these ids: stop the stream and leave
            /// the join if they are still shown, but leave alone a stream or guest join started after the Mac
            /// woke.
            case sleepStoppedStream(StreamSessionID?, guestJoin: UUID?)

            /// The Mac woke.
            case woke
        }
    }

    @Dependency(\.platform) private var lifecycle
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .terminationRequested:
                guard state.termination == .running else {
                    return .none
                }
                let id = OperationID(uuid: uuid())
                state.termination = .stopping(id)
                return .merge(
                    .send(.delegate(.terminating)),
                    .run { [lifecycle] send in
                        await lifecycle.shutdown()
                        await send(.terminationCompleted(id))
                    }
                )
            case .terminationCompleted(let id):
                guard state.termination == .stopping(id) else {
                    return .none
                }
                state.termination = .ready
                return .none
            case let .systemWillSleep(notification, consoleStreaming, stream, guestJoin):
                guard state.termination == .running else {
                    return .run { [lifecycle] _ in
                        await lifecycle.allowSleep(notification)
                    }
                }
                return .concatenate(
                    .send(.delegate(.sleeping)),
                    .run { [lifecycle] send in
                        let rest = consoleStreaming
                            ? await lifecycle.restsConsoleOnSleep()
                            : false
                        if await lifecycle.sleep(rest) {
                            await send(.sleepStoppedStream(stream, guestJoin: guestJoin))
                        }
                        await lifecycle.allowSleep(notification)
                    }
                )
            case let .sleepStoppedStream(stream, guestJoin):
                return .send(.delegate(.sleepStoppedStream(stream, guestJoin: guestJoin)))
            case .systemDidWake:
                guard state.termination == .running else {
                    return .none
                }
                return .merge(
                    .run { [lifecycle] _ in
                        await lifecycle.woke()
                    },
                    .send(.delegate(.woke))
                )
            case .networkChanged:
                guard state.termination == .running else {
                    return .none
                }
                return .run { [lifecycle] _ in
                    await lifecycle.networkChanged()
                }
            case .delegate:
                return .none
            }
        }
    }
}
