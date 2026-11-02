import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The stream menu's Trophies panel during a PS5 cloud or PS Now stream: the trophies of the game being played,
/// read fresh from PSN.
///
/// Opening the panel reads them again once the last read is older than ``minimumGap``; a trophy earned on a PS5
/// cloud stream, which arrives as a cloud notice, reads them again ``earnedDelay`` later, once PSN has it, and until
/// then opening the panel reads at once; Refresh reads them whenever asked. Each read asks for the game's release and
/// then its other generation's, keeping the first that has a trophy set, and moves on to the next when one fails.
/// Every answer carries the operation that asked for it, so an answer for an older read or an ended stream is
/// dropped.
@Reducer public struct StreamTrophiesFeature {
    /// Where the game's trophies stand.
    public enum Listing: Equatable, Sendable {
        /// Nothing has been read yet.
        case idle
        /// The operation with this id is reading, showing the trophies read before meanwhile.
        case loading(UUID, kept: CurrentTrophies?)
        /// PSN answered, with nothing when the game has no trophy set.
        case loaded(CurrentTrophies?)
        /// The trophies could not be read; those read before stay shown.
        case failed(PSNTrophiesFailure, kept: CurrentTrophies?)
    }

    /// The panel's state.
    @ObservableState public struct State: Equatable {
        /// The profile streaming.
        public var profile: ProfileID
        /// The title ids to read, the streamed release first and then the other generation's.
        public var titleIDs: [String]
        /// Where the trophies stand.
        public var listing = Listing.idle
        /// When the last read finished.
        public var readAt: Date?
        /// Which trophies are shown.
        public var filter = TrophyFilter.all
        /// The trophies' order.
        public var sort = TrophySort.game
        /// Whether the trophies run in their sort's order or the other way round.
        public var direction = TrophySortDirection.standard
        /// The hidden trophies the player chose to reveal.
        public var revealed: Set<Int> = []
        /// Whether a trophy was earned since the last read, so showing the panel reads again whatever the gap.
        public var earnedSinceRead = false

        /// Creates the panel's state.
        ///
        /// - Parameters:
        ///   - profile: The profile streaming.
        ///   - titleIDs: The title ids to read, the streamed release first.
        public init(profile: ProfileID, titleIDs: [String]) {
            self.profile = profile
            self.titleIDs = titleIDs
        }

        /// The trophies read last, kept while they are read again or after a failed read.
        public var current: CurrentTrophies? {
            switch listing {
            case .idle:
                nil
            case .loading(_, let kept), .failed(_, let kept):
                kept
            case .loaded(let found):
                found
            }
        }

        /// Whether a read is under way.
        public var isLoading: Bool {
            guard case .loading = listing else {
                return false
            }
            return true
        }

        /// The trophies shown, filtered and sorted as chosen.
        public var shown: [PSNTrophy] {
            TrophyArrangement.trophies(
                current?.trophies.trophies ?? [],
                filter: filter,
                sort: sort,
                direction: direction
            )
        }
    }

    /// What the panel can do.
    public enum Action: Equatable, Sendable {
        /// The panel was shown.
        case appeared
        /// The player asked to read the trophies again.
        case refresh
        /// A trophy was earned on the stream.
        case earned
        /// The wait after an earned trophy elapsed.
        case earnedSettled
        /// The read by an operation finished.
        case loaded(UUID, Result<CurrentTrophies?, PSNTrophiesFailure>)
        /// The player chose which trophies are shown.
        case filterChosen(TrophyFilter)
        /// The player chose the trophies' order.
        case sortChosen(TrophySort)
        /// The player turned reversing the trophies' order on or off.
        case reverseToggled
        /// The player revealed or hid a hidden trophy's name and description.
        case revealToggled(Int)
        /// The stream ended.
        case streamEnded
    }

    /// Cancellation identifiers for the panel's reads.
    public enum CancelID: Sendable {
        /// The read.
        case read
        /// The wait after an earned trophy.
        case earned
    }

    /// How old the last read must be before showing the panel reads again.
    public static let minimumGap: TimeInterval = 60
    /// How long after an earned trophy the trophies are read, so PSN has it by then.
    public static let earnedDelay: Duration = .seconds(10)

    /// Reads trophies through PSN.
    @Dependency(\.psnTrophies) var client
    /// Generates operation identifiers.
    @Dependency(\.uuid) var uuid
    /// Tells the time of a read.
    @Dependency(\.date) var date
    /// Times the wait after an earned trophy.
    @Dependency(\.continuousClock) var clock

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                if state.isLoading {
                    return .none
                }
                if !state.earnedSinceRead, let readAt = state.readAt,
                   date.now.timeIntervalSince(readAt) < Self.minimumGap {
                    return .none
                }
                return read(&state)
            case .refresh:
                return read(&state)
            case .earned:
                state.earnedSinceRead = true
                return .run { [clock] send in
                    try await clock.sleep(for: Self.earnedDelay)
                    await send(.earnedSettled)
                }
                .cancellable(id: CancelID.earned, cancelInFlight: true)
            case .earnedSettled:
                return read(&state)
            case let .loaded(operation, result):
                guard case .loading(operation, let kept) = state.listing else {
                    return .none
                }
                state.readAt = date.now
                state.earnedSinceRead = false
                switch result {
                case .success(let found):
                    state.listing = .loaded(found)
                case .failure(let failure):
                    state.listing = .failed(failure, kept: kept)
                }
                return .none
            case .filterChosen(let filter):
                state.filter = filter
                return .none
            case .sortChosen(let sort):
                state.sort = sort
                return .none
            case .reverseToggled:
                state.direction = state.direction.flipped
                return .none
            case .revealToggled(let trophy):
                if state.revealed.contains(trophy) {
                    state.revealed.remove(trophy)
                } else {
                    state.revealed.insert(trophy)
                }
                return .none
            case .streamEnded:
                if case .loading(_, let kept) = state.listing {
                    state.listing = kept.map(Listing.loaded) ?? .idle
                }
                return .merge(.cancel(id: CancelID.read), .cancel(id: CancelID.earned))
            }
        }
    }

    private func read(_ state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.listing = .loading(operation, kept: state.current)
        let profile = state.profile
        let titleIDs = state.titleIDs
        return .run { [client] send in
            var failure: PSNTrophiesFailure?
            for titleID in titleIDs {
                do throws(PSNTrophiesFailure) {
                    if let found = try await client.current(profile, titleID) {
                        await send(.loaded(operation, .success(found)))
                        return
                    }
                    failure = nil
                } catch .cancelled {
                    return
                } catch {
                    failure = error
                }
            }
            await send(.loaded(operation, failure.map { .failure($0) } ?? .success(nil)))
        }
        .cancellable(id: CancelID.read, cancelInFlight: true)
    }
}

extension StreamFeature {
    /// The Trophies panel state a stream starts with: one for a cloud stream whose game names a title id, and none
    /// otherwise.
    ///
    /// - Parameter source: The stream's source.
    /// - Returns: The panel state, or `nil`.
    static func trophies(for source: StreamSource) -> StreamTrophiesFeature.State? {
        guard case .cloud(let request) = source else {
            return nil
        }
        let titleIDs = [request.title.product, request.title.otherVersion].compactMap { product in
            product.flatMap(Self.titleID(of:))
        }
        guard !titleIDs.isEmpty else {
            return nil
        }
        return StreamTrophiesFeature.State(profile: request.profile, titleIDs: titleIDs)
    }

    /// The title id inside a store product id, such as `CUSA00341_00` in `UP9000-CUSA00341_00-UNCHARTED0000000`.
    ///
    /// - Parameter product: The product id.
    /// - Returns: The title id, or `nil` when the product id has none.
    static func titleID(of product: ProductID) -> String? {
        let parts = product.rawValue.split(separator: "-")
        guard parts.count > 1 else {
            return nil
        }
        let id = Array(parts[1])
        guard id.count == 12, id[9] == "_" else {
            return nil
        }
        return String(id)
    }
}
