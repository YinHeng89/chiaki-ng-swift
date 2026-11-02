import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The root's one local-network discovery, held open by leases.
///
/// The library, the add-console screen and an automatic connection each hold a `ChiakiModels/DiscoveryLease`
/// while they need to see consoles. Discovery subscribes to the shared scan of `ChiakiClients/ConsolesClient`
/// while any lease is held and unsubscribes when the last is released, so no holder stops the scan under
/// another. Every event carries the `ChiakiModels/OperationID` of the subscription that produced it.
///
/// Once a snapshot reports an available network the scan listens for ``searchWindow``, long enough for any
/// console on the network to answer its broadcasts, and then counts as searched: only then is a console it
/// does not see known to be away. Losing the network returns it to scanning.
@Reducer
public struct DiscoveryFeature {
    /// The leases and what the scan sees.
    @ObservableState
    public struct State: Equatable {
        /// Whether the scan runs.
        public enum Phase: Equatable, Sendable {
            /// No lease is held.
            case idle

            /// The subscription with this id is receiving snapshots and waits for a network.
            case scanning(OperationID)

            /// The subscription with this id has a network and gives consoles time to answer.
            case listening(OperationID)

            /// The subscription with this id has listened long enough that a console it does not see is away.
            case searched(OperationID)

            /// The scan stopped; a retry or a new lease starts it again.
            case failed

            /// The id of the running subscription, while one runs.
            public var scan: OperationID? {
                switch self {
                case .scanning(let id), .listening(let id), .searched(let id):
                    id
                case .idle, .failed:
                    nil
                }
            }

            /// Whether the scan has listened long enough that a console it does not see is away.
            public var hasSearched: Bool {
                if case .searched = self {
                    return true
                }
                return false
            }
        }

        /// Who needs the scan.
        public internal(set) var leases: Set<DiscoveryLease> = []

        /// Whether the scan runs.
        public internal(set) var phase = Phase.idle

        /// The consoles the scan currently sees.
        public internal(set) var snapshot = DiscoverySnapshot()

        /// Creates the state with no lease held.
        public init() {
        }

        /// Whether the scan is receiving snapshots.
        public var isScanning: Bool {
            phase.scan != nil
        }
    }

    /// Everything discovery reacts to.
    public enum Action: Equatable {
        /// Holds a lease, starting the scan when it is not running, or reporting what a running scan sees.
        case acquire(DiscoveryLease)

        /// Releases a lease, stopping the scan when none is left.
        case release(DiscoveryLease)

        /// Starts a failed scan again while a lease is held.
        case retry

        /// Releases every lease, for teardown.
        case stop

        /// The subscription with this id reported an event.
        case scanned(OperationID, ConsoleScanEvent)

        /// The subscription with this id listened for the whole search window.
        case searchWindowElapsed(OperationID)

        /// What the parent is told.
        case delegate(Delegate)

        /// What discovery reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The scan sees these consoles now.
            case updated(DiscoverySnapshot)

            /// Whether the scan has listened long enough that a console it does not see is away changed.
            case searched(Bool)

            /// The scan stopped.
            case failed
        }
    }

    private enum CancelID {
        case scan
        case search
    }

    /// How long the scan listens on an available network before a console it does not see counts as away.
    public static let searchWindow = Duration.seconds(3)

    @Dependency(\.consoles) private var scan
    @Dependency(\.uuid) private var uuid
    @Dependency(\.continuousClock) private var clock

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .acquire(let lease):
                state.leases.insert(lease)
                guard !state.isScanning else {
                    return .merge(
                        .send(.delegate(.updated(state.snapshot))),
                        .send(.delegate(.searched(state.phase.hasSearched)))
                    )
                }
                return subscribe(&state)
            case .release(let lease):
                state.leases.remove(lease)
                guard state.leases.isEmpty else {
                    return .none
                }
                return unsubscribe(&state)
            case .retry:
                guard !state.leases.isEmpty, !state.isScanning else {
                    return .none
                }
                return subscribe(&state)
            case .stop:
                state.leases = []
                return unsubscribe(&state)
            case let .scanned(id, .snapshot(snapshot)):
                guard state.phase.scan == id else {
                    return .none
                }
                state.snapshot = snapshot
                return .merge(
                    .send(.delegate(.updated(snapshot))),
                    followNetwork(snapshot.networkAvailable, scan: id, state: &state)
                )
            case let .scanned(id, .failed):
                guard state.phase.scan == id else {
                    return .none
                }
                state.phase = .failed
                return .merge(
                    .cancel(id: CancelID.scan),
                    .cancel(id: CancelID.search),
                    .send(.delegate(.failed))
                )
            case .searchWindowElapsed(let id):
                guard state.phase == .listening(id) else {
                    return .none
                }
                state.phase = .searched(id)
                return .send(.delegate(.searched(true)))
            case .delegate:
                return .none
            }
        }
    }

    private func subscribe(_ state: inout State) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        state.phase = .scanning(id)
        state.snapshot = DiscoverySnapshot()
        return .merge(
            .cancel(id: CancelID.search),
            .run { [scan] send in
                for await event in await scan.scanEvents() {
                    await send(.scanned(id, event))
                }
            }
            .cancellable(id: CancelID.scan, cancelInFlight: true)
        )
    }

    private func unsubscribe(_ state: inout State) -> Effect<Action> {
        state.phase = .idle
        state.snapshot = DiscoverySnapshot()
        return .merge(.cancel(id: CancelID.scan), .cancel(id: CancelID.search))
    }

    private func followNetwork(_ available: Bool, scan id: OperationID,
                               state: inout State) -> Effect<Action> {
        switch (state.phase, available) {
        case (.scanning(id), true):
            state.phase = .listening(id)
            return .run { [clock] send in
                try await clock.sleep(for: Self.searchWindow)
                await send(.searchWindowElapsed(id))
            }
            .cancellable(id: CancelID.search, cancelInFlight: true)
        case (.listening(id), false):
            state.phase = .scanning(id)
            return .cancel(id: CancelID.search)
        case (.searched(id), false):
            state.phase = .scanning(id)
            return .merge(.cancel(id: CancelID.search), .send(.delegate(.searched(false))))
        default:
            return .none
        }
    }
}
