import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// A game whose layered art should be fetched, and the account to fetch it as.
public struct ConsoleArtRequest: Equatable, Sendable {
    /// The account whose PSN identity asks for the art.
    public let accountID: UUID
    /// The game's concept id.
    public let conceptID: String

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - accountID: The account whose PSN identity asks for the art.
    ///   - conceptID: The game's concept id.
    public init(accountID: UUID, conceptID: String) {
        self.accountID = accountID
        self.conceptID = conceptID
    }
}

/// Fetches the layered art of recently played games one at a time, remembering each answer so a game is
/// only asked about once.
@Reducer public struct ConsoleArtReducer {
    /// Whether a fetch is in flight.
    public enum Phase: Equatable, Sendable {
        /// No fetch is in flight.
        case idle
        /// The art of this request is being fetched.
        case asking(ConsoleArtRequest)
    }

    /// The remembered outcome of a game's art fetch.
    public enum Art: Equatable, Sendable {
        /// The game has layered art.
        case layered(GameArtLayers)
        /// The game has no layered art, so its card shows the plain tile.
        case plain
    }

    /// The fetch queue and the remembered answers.
    @ObservableState
    public struct State: Equatable {
        /// Whether a fetch is in flight, and for which game.
        public var phase = Phase.idle
        /// The requests still to fetch, in order; a requested game moves to the front.
        public var waiting: [ConsoleArtRequest] = []
        /// The remembered art, by concept id.
        public var games: [String: Art] = [:]

        /// Creates state with nothing fetched or queued.
        public init() {
        }

        /// The layered art of a game, once fetched.
        ///
        /// - Parameter conceptID: The game's concept id.
        /// - Returns: The layers, or `nil` when the game has none or was not fetched yet.
        public func layers(for conceptID: String) -> GameArtLayers? {
            guard case .layered(let layers) = games[conceptID] else {
                return nil
            }
            return layers
        }

        /// Whether the fetch in flight is for a game.
        ///
        /// - Parameter conceptID: The game's concept id.
        /// - Returns: `true` while that game's art is being fetched.
        public func asks(_ conceptID: String) -> Bool {
            guard case .asking(let request) = phase else {
                return false
            }
            return request.conceptID == conceptID
        }
    }

    /// Everything the art queue reacts to.
    public enum Action: Equatable, Sendable {
        /// Replaces the queue with the shown games that are not fetched or being fetched yet.
        case show([ConsoleArtRequest])
        /// Moves a game to the front of the queue, unless it was fetched or is being fetched.
        case want(ConsoleArtRequest)
        /// The fetch for a concept id finished, with its layers or `nil`.
        case answered(String, GameArtLayers?)
    }

    /// Fetches the art layers.
    @Dependency(\.consoles) var client

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .show(let requests):
                var queued = Set<String>()
                state.waiting = requests.filter { request in
                    !request.conceptID.isEmpty && state.games[request.conceptID] == nil
                        && !state.asks(request.conceptID) && queued.insert(request.conceptID).inserted
                }
                return askNext(&state)
            case .want(let request):
                guard !request.conceptID.isEmpty, state.games[request.conceptID] == nil,
                      !state.asks(request.conceptID) else {
                    return .none
                }
                state.waiting.removeAll {
                    $0.conceptID == request.conceptID
                }
                state.waiting.insert(request, at: 0)
                return askNext(&state)
            case let .answered(conceptID, layers):
                guard state.asks(conceptID) else {
                    return .none
                }
                state.games[conceptID] = layers.map(Art.layered) ?? .plain
                state.phase = .idle
                return askNext(&state)
            }
        }
    }

    private func askNext(_ state: inout State) -> Effect<Action> {
        guard state.phase == .idle, !state.waiting.isEmpty else {
            return .none
        }
        let request = state.waiting.removeFirst()
        state.phase = .asking(request)
        return .run { [client] send in
            await send(.answered(request.conceptID, client.artLayers(request.accountID, request.conceptID)))
        }
    }
}
