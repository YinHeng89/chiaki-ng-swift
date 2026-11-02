import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The detail of one cloud game: the layered art and media when the store publishes them, the card otherwise.
///
/// The cloud library presents it through ``CloudLibraryFeature/Destination/gameDetail(_:)`` and sends
/// ``Action/open(_:_:)`` when a game is opened. Completions carry the id of the load that asked for them, so an
/// answer for a game that was closed or replaced is ignored.
@Reducer public struct GameDetailFeature {
    /// Why the detail shows the card instead of the layered view.
    public enum Fallback: Equatable, Sendable {
        /// No account is signed in to ask for details.
        case noAccount
        /// The details could not be fetched.
        case unavailable
        /// The store publishes no layered art for the game.
        case noLayeredArt
        /// The layered art could not be loaded.
        case artUnavailable
    }

    /// Where the detail's load is, with the product id it is for.
    public enum Phase: Equatable, Sendable {
        /// Nothing was opened.
        case closed
        /// The details are being fetched by the load with this id.
        case loadingDetails(ProductID, UUID)
        /// The details arrived and the art is being loaded by the load with this id.
        case loadingArt(ProductID, UUID, GameDetails)
        /// The layered view is shown.
        case layered(ProductID, GameDetails, GameArtLayers)
        /// The card is shown.
        case fallback(ProductID, Fallback)
    }

    /// What an earlier load learned about a game.
    public enum Known: Equatable, Sendable {
        /// The game has no layered art.
        case card
        /// The game's details, which have layered art.
        case layered(GameDetails)
    }

    /// How the layered view appeared.
    public enum Arrival: Equatable, Sendable {
        /// It opened at once from art held in memory.
        case direct
        /// It grew out of the loading card.
        case afterLoader
    }

    /// The layered view's content.
    public struct Expanded: Equatable, Sendable {
        /// The game's details.
        public let details: GameDetails
        /// The decoded art.
        public let layers: GameArtLayers
        /// How the view appeared.
        public let arrival: Arrival

        /// Creates an expanded.
        ///
        /// - Parameters:
        ///   - details: The game's details.
        ///   - layers: The decoded art.
        ///   - arrival: How the view appeared.
        public init(details: GameDetails, layers: GameArtLayers, arrival: Arrival) {
            self.details = details
            self.layers = layers
            self.arrival = arrival
        }
    }

    /// What the detail shows for one game.
    public enum Shown: Equatable, Sendable {
        /// The card.
        case card
        /// The loader.
        case loading
        /// The layered view.
        case layered(Expanded)

        /// Whether the layered view is shown.
        public var isLayered: Bool {
            if case .layered = self {
                return true
            }
            return false
        }
    }

    /// The detail's state.
    @ObservableState public struct State: Equatable {
        /// The product id of the game the detail was opened on.
        public var requested: ProductID?
        /// Where the load is.
        public var phase = Phase.closed
        /// What loads learned about each game, by product id.
        public var known: [ProductID: Known] = [:]
        /// Which media item is enlarged.
        public var media = GameDetailMedia.idle
        /// How the layered view appeared.
        public var arrival = Arrival.direct

        /// Creates a detail.
        ///
        /// - Parameters:
        ///   - known: What earlier details learned, so a game known to have no layered art opens on its card.
        ///   - requested: The product id of the game being opened.
        public init(known: [ProductID: Known] = [:], requested: ProductID? = nil) {
            self.known = known
            self.requested = requested
        }

        /// The product id of the game the load is for.
        public var productID: ProductID? {
            switch phase {
            case .closed:
                nil
            case .loadingDetails(let product, _), .loadingArt(let product, _, _), .layered(let product, _, _),
                 .fallback(let product, _):
                product
            }
        }

        /// Tells what the detail shows for a game.
        ///
        /// - Parameter productID: The game's product id.
        /// - Returns: The card for any other game than the loaded one.
        public func shown(for productID: ProductID?) -> Shown {
            guard self.productID == productID else {
                return .card
            }
            switch phase {
            case .closed, .fallback:
                return .card
            case .loadingDetails, .loadingArt:
                return .loading
            case .layered(_, let details, let layers):
                return .layered(Expanded(details: details, layers: layers, arrival: arrival))
            }
        }

        /// Tells which media item of a game is enlarged.
        ///
        /// - Parameter productID: The game's product id.
        /// - Returns: The enlarged item's index, or `nil` when none is.
        public func viewed(for productID: ProductID?) -> Int? {
            guard case .viewing(let index) = media, case .layered(let product, _, _) = phase,
                  product == productID else {
                return nil
            }
            return index
        }

        /// The number of screenshots and trailers the layered view offers, or zero when it is not shown.
        public var mediaCount: Int {
            guard case .layered(_, let details, _) = phase else {
                return 0
            }
            return details.screenshots.count + details.trailers.count
        }
    }

    /// What the detail can do.
    public enum Action: Equatable, Sendable {
        /// Opens a game for an account, or for no account.
        case open(UUID?, ProductID)
        /// The details asked for by the load with this id arrived.
        case detailsLoaded(UUID, Result<GameDetails, CatalogFailure>)
        /// The art asked for by the load with this id arrived, or `nil` when it could not be loaded.
        case artLoaded(UUID, GameArtLayers?)
        /// A media tile was pressed; pressing the enlarged one shrinks it.
        case viewMedia(Int)
        /// The enlarged media moved by this many items.
        case stepMedia(Int)
        /// The enlarged media was dismissed.
        case closeMedia
    }

    @Dependency(\.catalog) private var catalog
    @Dependency(\.uuid) private var uuid

    private enum CancelID: Sendable {
        case load
    }

    /// Creates the feature.
    public init() {
    }

    /// Runs the detail.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .open(account, product):
                return open(&state, account: account, product: product)
            case let .detailsLoaded(attempt, result):
                guard case .loadingDetails(let product, attempt) = state.phase else {
                    return .none
                }
                guard case .success(let details) = result else {
                    state.phase = .fallback(product, .unavailable)
                    return .none
                }
                guard let art = details.art else {
                    state.known[product] = .card
                    state.phase = .fallback(product, .noLayeredArt)
                    return .none
                }
                state.known[product] = .layered(details)
                state.phase = .loadingArt(product, attempt, details)
                return loadArt(art, of: product, attempt: attempt)
            case let .artLoaded(attempt, layers):
                guard case .loadingArt(let product, attempt, let details) = state.phase else {
                    return .none
                }
                if let layers {
                    state.arrival = .afterLoader
                    state.phase = .layered(product, details, layers)
                } else {
                    state.phase = .fallback(product, .artUnavailable)
                }
                return .none
            case .viewMedia(let index):
                guard (0..<state.mediaCount).contains(index) else {
                    return .none
                }
                state.media = state.media == .viewing(index)
                    ? .idle
                    : .viewing(index)
                return .none
            case .stepMedia(let step):
                guard case .viewing(let index) = state.media,
                      (0..<state.mediaCount).contains(index + step) else {
                    return .none
                }
                state.media = .viewing(index + step)
                return .none
            case .closeMedia:
                state.media = .idle
                return .none
            }
        }
    }

    private func open(_ state: inout State, account: UUID?, product: ProductID) -> Effect<Action> {
        if state.productID == product {
            switch state.phase {
            case .loadingDetails, .loadingArt, .layered:
                return .none
            case .closed, .fallback:
                break
            }
        }
        state.media = .idle
        guard let account else {
            state.phase = .fallback(product, .noAccount)
            return .cancel(id: CancelID.load)
        }
        switch state.known[product] {
        case .card:
            state.phase = .fallback(product, .noLayeredArt)
            return .cancel(id: CancelID.load)
        case .layered(let details):
            guard let art = details.art else {
                state.phase = .fallback(product, .noLayeredArt)
                return .cancel(id: CancelID.load)
            }
            if let layers = catalog.heldArtLayers(art) {
                state.arrival = .direct
                state.phase = .layered(product, details, layers)
                return .cancel(id: CancelID.load)
            }
            let attempt = uuid()
            state.phase = .loadingArt(product, attempt, details)
            return loadArt(art, of: product, attempt: attempt)
        case nil:
            let attempt = uuid()
            state.phase = .loadingDetails(product, attempt)
            return .run { [catalog] send in
                let details = await catalog.gameDetails(account, product)
                guard !Task.isCancelled else {
                    return
                }
                await send(.detailsLoaded(attempt, details))
            }.cancellable(id: CancelID.load, cancelInFlight: true)
        }
    }

    private func loadArt(_ art: GameDetails.Art, of product: ProductID, attempt: UUID) -> Effect<Action> {
        .run { [catalog] send in
            catalog.rememberArt(art, product)
            let layers = await catalog.artLayers(art)
            guard !Task.isCancelled else {
                return
            }
            await send(.artLoaded(attempt, layers))
        }.cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
