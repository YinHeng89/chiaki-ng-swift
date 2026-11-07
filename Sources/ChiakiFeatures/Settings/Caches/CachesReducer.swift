import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Drives the caches settings pane: loads cache summaries, shows one cache's records, and clears caches after
/// the parent confirms.
@Reducer public struct CachesReducer {
    /// Where loading or clearing caches stands; each in-flight operation carries the ID that its completion
    /// must match.
    public enum Phase: Equatable, Sendable {
        /// Nothing has been loaded yet.
        case idle
        /// Summaries are loading under the given operation ID.
        case loading(UUID)
        /// Summaries are loaded and nothing is in flight.
        case ready
        /// A clear is running under the given operation ID.
        case clearing(UUID)
        /// The last load or clear failed with the given message.
        case failed(LocalizedStringResource)
    }

    /// Which cache's records are open below its row, and whether they have loaded.
    public enum Entries: Equatable, Sendable {
        /// No cache's records are shown.
        case closed
        /// The records of a cache are loading under the given operation ID.
        case loading(CacheKind, UUID)
        /// The records of a cache are shown.
        case shown(CacheKind, [CacheEntry])
        /// The records of a cache could not be read, with a message to show.
        case failed(CacheKind, LocalizedStringResource)

        /// The cache whose records are open, loading or failed, or `nil` when closed.
        public var cache: CacheKind? {
            switch self {
            case .closed:
                nil
            case .loading(let cache, _), .shown(let cache, _), .failed(let cache, _):
                cache
            }
        }
    }

    /// The caches pane's state.
    @ObservableState public struct State: Equatable {
        /// Where loading or clearing stands.
        public var phase = Phase.idle
        /// The latest counts and sizes for every cache.
        public var summaries: [CacheSummary] = []
        /// The number of decoded artwork images held in memory at the last load.
        public var decodedArtwork = 0
        /// Saved account display names keyed by account ID, used to label records.
        public var accountNames: [Data: String] = [:]
        /// Which cache's records are open below its row.
        public var entries = Entries.closed

        /// Creates the idle state with nothing loaded.
        public init() {
        }

        /// Whether a load or clear is in flight, which disables refreshing and clearing.
        public var busy: Bool {
            switch phase {
            case .loading, .clearing:
                true
            case .idle, .ready, .failed:
                false
            }
        }

        /// Whether any cache has entries or any decoded artwork is in memory, which enables Clear all.
        public var holdsAnything: Bool {
            summaries.contains { $0.entries > 0 } || decodedArtwork > 0
        }
    }

    /// Events the caches pane handles.
    public enum Action: Equatable, Sendable {
        /// Reloads every cache summary, ignored while busy.
        case load
        /// Summaries, account names and decoded artwork count arrived for the load with the given ID.
        case loaded(UUID, [CacheSummary], [Data: String], Int)
        /// The load or clear with the given ID failed with a message.
        case failed(UUID, LocalizedStringResource)
        /// Opens a cache's records below its row and loads them.
        case open(CacheKind)
        /// Closes the open records and cancels any load of them.
        case close
        /// Records arrived for the entries load with the given ID.
        case entriesLoaded(UUID, [CacheEntry])
        /// The entries load with the given ID failed with a message.
        case entriesFailed(UUID, LocalizedStringResource)
        /// Asks the parent to confirm a clear, ignored while busy.
        case askClear(CacheClearing)
        /// Clears after confirmation, then reloads the summaries.
        case clear(CacheClearing)
        /// The clear with the given ID finished.
        case cleared(UUID)
        /// Requests sent to the parent.
        case delegate(Delegate)

        /// What the caches pane asks its parent.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// Ask the user to confirm clearing before ``Action/clear(_:)`` is sent.
            case confirmClear(CacheClearing)
        }
    }

    /// The client that reads and clears caches.
    @Dependency(\.catalog) var client
    /// Generates the IDs that tie each completion to the operation that started it.
    @Dependency(\.uuid) var uuid

    /// Identifies the cancellable summaries and entries loads.
    public enum CancelID: Sendable {
        /// The summaries load and the entries load.
        case summaries, entries
    }

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.busy else {
                    return .none
                }
                return load(&state)
            case let .loaded(id, summaries, names, decoded):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.summaries = summaries
                state.decodedArtwork = decoded
                state.accountNames = names
                state.phase = .ready
                guard let cache = state.entries.cache else {
                    return .none
                }
                return loadEntries(&state, of: cache)
            case let .failed(id, message):
                guard state.phase == .loading(id) || state.phase == .clearing(id) else {
                    return .none
                }
                state.phase = .failed(message)
            case .open(let cache):
                return loadEntries(&state, of: cache)
            case .close:
                state.entries = .closed
                return .cancel(id: CancelID.entries)
            case let .entriesLoaded(id, entries):
                guard case .loading(let cache, id) = state.entries else {
                    return .none
                }
                state.entries = .shown(cache, entries)
            case let .entriesFailed(id, message):
                guard case .loading(let cache, id) = state.entries else {
                    return .none
                }
                state.entries = .failed(cache, message)
            case .askClear(let clearing):
                guard !state.busy else {
                    return .none
                }
                return .send(.delegate(.confirmClear(clearing)))
            case .delegate:
                return .none
            case .clear(let clearing):
                guard !state.busy else {
                    return .none
                }
                let id = uuid()
                state.phase = .clearing(id)
                return .run { [client] send in
                    do {
                        try await client.clearCache(clearing)
                        if clearing.holdsArtwork {
                            client.clearDecoded()
                        }
                        await send(.cleared(id))
                    } catch {
                        await send(.failed(id, .settingsCachesClearFailed))
                    }
                }
            case .cleared(let id):
                guard state.phase == .clearing(id) else {
                    return .none
                }
                return load(&state)
            }
            return .none
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        let id = uuid()
        state.phase = .loading(id)
        return .run { [client] send in
            do {
                let summaries = try await client.cacheSummaries()
                await send(.loaded(id, summaries, await client.cacheAccountNames(), client.decodedCount()))
            } catch {
                await send(.failed(id, .settingsCachesReadFailed))
            }
        }.cancellable(id: CancelID.summaries, cancelInFlight: true)
    }

    private func loadEntries(_ state: inout State, of cache: CacheKind) -> Effect<Action> {
        let id = uuid()
        state.entries = .loading(cache, id)
        return .run { [client] send in
            do {
                await send(.entriesLoaded(id, try await client.cacheEntries(cache)))
            } catch {
                await send(.entriesFailed(id, .settingsCachesEntriesFailed))
            }
        }.cancellable(id: CancelID.entries, cancelInFlight: true)
    }
}
