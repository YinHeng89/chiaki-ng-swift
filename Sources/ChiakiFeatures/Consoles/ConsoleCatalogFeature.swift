import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The saved console pairings, owned by the root and reloaded whenever they change.
///
/// Reads follow `ChiakiModels/ConsoleCatalogLoad`; a newer read supersedes an older one, and only the
/// running read's result is applied. While ``Action/observe`` runs, every change the
/// `ChiakiClients/ConsolesClient` reports starts a reload, so an address a scan saved reaches the
/// library whichever screen's scan found it.
@Reducer
public struct ConsoleCatalogFeature {
    /// The pairings and how far reading them has got.
    @ObservableState
    public struct State: Equatable {
        /// Every saved pairing from the last successful read.
        public internal(set) var consoles: [RegisteredConsole] = []

        /// How far reading the pairings has got.
        public internal(set) var load = ConsoleCatalogLoad.pending

        /// Creates the state before anything is read.
        public init() {}
    }

    /// Everything the catalog reacts to.
    public enum Action: Equatable {
        /// Reads the pairings again.
        case load

        /// Reloads whenever the pairings change, until the effect is cancelled.
        case observe

        /// Abandons a running read.
        case stop

        /// A read finished.
        case loadFinished(OperationID, Result<[RegisteredConsole], ConsoleCatalogFailure>)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the catalog reports to its parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The pairings were read.
            case loaded([RegisteredConsole])

            /// The pairings could not be read.
            case failed
        }
    }

    private enum CancelID {
        case load, observe
    }

    @Dependency(\.consoles) private var catalog
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                let id = OperationID(uuid: uuid())
                state.load.start(id)
                return .run { [catalog] send in
                    await send(.loadFinished(id, catalog.pairings()))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)
            case .observe:
                return .run { [catalog] send in
                    for await _ in catalog.pairingChanges() {
                        await send(.load)
                    }
                }
                .cancellable(id: CancelID.observe, cancelInFlight: true)
            case .stop:
                state.load.stop()
                return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.observe))
            case let .loadFinished(id, .success(consoles)):
                guard state.load.finish(id, .loaded) else {
                    return .none
                }
                state.consoles = consoles
                return .send(.delegate(.loaded(consoles)))
            case let .loadFinished(id, .failure):
                guard state.load.finish(id, .failed) else {
                    return .none
                }
                return .send(.delegate(.failed))
            case .delegate:
                return .none
            }
        }
    }
}
