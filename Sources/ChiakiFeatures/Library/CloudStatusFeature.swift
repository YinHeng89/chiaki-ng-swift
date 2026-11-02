import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The selected account's cloud status and PlayStation Plus tier, shown in the library header.
///
/// The status is read from its cache when an account is selected, refreshed when the cache has expired and
/// checked again every minute while it is watched. The catalog is asked for in the locale the app runs in.
/// Every completion carries the id of the operation that asked for it.
@Reducer public struct CloudStatusFeature {
    /// Where the status is.
    public enum Phase: Equatable, Sendable {
        /// No account is selected.
        case idle
        /// The cache is being read by the operation with this id.
        case loading(UUID)
        /// The status is being refreshed by the operation with this id.
        case refreshing(UUID)
        /// The status is shown.
        case ready
        /// The status could not be read.
        case failed(CloudStatusFailure)
    }

    /// The status's state.
    @ObservableState public struct State: Equatable {
        /// The account and locale the status is for.
        public var scope: CloudAccountScope?
        /// Where the status is.
        public var phase: Phase = .idle
        /// The last status read.
        public var snapshot: CloudStatusSnapshot?
        /// When the last refresh was asked for.
        public var lastAttempt: Date?
        /// The account's PlayStation Plus tier, once the core has reported it.
        public var plusTier: PlusTier?
        /// The operation whose tier answer is accepted.
        public var tierAttempt: UUID?

        /// Creates an idle status.
        public init() {
        }

        /// Tells whether the stream service rules cloud play out for an account.
        ///
        /// - Parameter profile: The selected account.
        /// - Returns: Whether the region is unsupported or a subscription is required.
        public func unavailable(for profile: UUID?) -> Bool {
            guard let profile, scope?.accountID == profile else {
                return false
            }
            switch phase {
            case .failed(.regionUnsupported):
                return true
            case .ready:
                guard let snapshot, snapshot.scope.accountID == profile else {
                    return false
                }
                return snapshot.catalog.availability == .subscriptionRequired
            default:
                return false
            }
        }
    }

    /// What the status can do.
    public enum Action: Equatable, Sendable {
        /// An account was selected.
        case select(UUID)
        /// The cache read by the operation with this id answered.
        case cached(UUID, CloudStatusSnapshot?)
        /// A refresh was asked for.
        case refresh
        /// The refresh with this id answered.
        case refreshed(UUID, CloudStatusSnapshot)
        /// The operation with this id failed.
        case failed(UUID, CloudStatusFailure)
        /// The tier read by the operation with this id answered.
        case plusTierLoaded(UUID, PlusTier?)
        /// The status left the screen.
        case stop
        /// Starts checking the status every minute.
        case watch
        /// The minute between checks passed.
        case tick
    }

    @Dependency(\.cloud) private var client
    @Dependency(\.catalog) private var catalog
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.locale) private var locale
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date.now) private var now

    private enum CancelID {
        case operation
        case monitor
    }

    /// Creates the feature.
    public init() {
    }

    /// Runs the status.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .watch:
                return .run { [clock] send in
                    while !Task.isCancelled {
                        try await clock.sleep(for: .seconds(60))
                        await send(.tick)
                    }
                }
                .cancellable(id: CancelID.monitor, cancelInFlight: true)
            case .tick:
                if let snapshot = state.snapshot, snapshot.expiresAt > now {
                    return .none
                }
                if let last = state.lastAttempt, now.timeIntervalSince(last) < 300 {
                    return .none
                }
                return .send(.refresh)
            case .select(let account):
                return select(&state, account: account)
            case .cached(let id, let snapshot):
                guard state.phase == .loading(id) else {
                    return .none
                }
                state.snapshot =
                    snapshot?.scope == state.scope
                        ? snapshot
                        : nil
                state.phase = .ready
                if let snapshot = state.snapshot, snapshot.expiresAt > now {
                    return .none
                }
                return .send(.refresh)
            case .refresh:
                return refresh(&state)
            case .refreshed(let id, let snapshot):
                guard state.phase == .refreshing(id) else {
                    return .none
                }
                guard snapshot.scope == state.scope else {
                    state.phase = .failed(.malformedResponse)
                    return .none
                }
                state.snapshot = snapshot
                state.phase = .ready
                return .none
            case .failed(let id, let failure):
                guard state.phase == .loading(id) || state.phase == .refreshing(id) else {
                    return .none
                }
                state.phase = .failed(failure)
                return .none
            case .plusTierLoaded(let id, let tier):
                guard state.tierAttempt == id else {
                    return .none
                }
                state.tierAttempt = nil
                state.plusTier = tier
                return .none
            case .stop:
                state = State()
                return .merge(
                    .cancel(id: CancelID.operation),
                    .cancel(id: CancelID.monitor)
                )
            }
        }
    }

    private func select(_ state: inout State, account: UUID) -> Effect<Action> {
        let scope = CloudAccountScope(
            accountID: account,
            locale: locale.identifier.replacingOccurrences(of: "_", with: "-")
        )
        if state.scope == scope, case .failed = state.phase,
           let last = state.lastAttempt, now.timeIntervalSince(last) < 300 {
            return .none
        }
        let id = uuid()
        let sameAccount = state.scope?.accountID == account
        state.scope = scope
        state.snapshot = nil
        state.lastAttempt = nil
        state.phase = .loading(id)
        if !sameAccount {
            state.plusTier = nil
        }
        state.tierAttempt = id
        return .run { [client, catalog] send in
            await send(.plusTierLoaded(id, catalog.plusTier(account)))
            do {
                try await send(.cached(id, client.cachedStatus(scope)))
            } catch is CancellationError {
            } catch {
                await send(.failed(id, .storage))
            }
        }
        .cancellable(id: CancelID.operation, cancelInFlight: true)
    }

    private func refresh(_ state: inout State) -> Effect<Action> {
        guard let scope = state.scope else {
            return .none
        }
        switch state.phase {
        case .loading, .refreshing:
            return .none
        default:
            break
        }
        let id = uuid()
        state.phase = .refreshing(id)
        state.lastAttempt = now
        return .run { [client] send in
            do {
                try await send(.refreshed(id, client.refreshStatus(scope)))
            } catch is CancellationError {
            } catch let failure as CloudStatusFailure {
                await send(.failed(id, failure))
            } catch {
                await send(.failed(id, .network))
            }
        }
        .cancellable(id: CancelID.operation, cancelInFlight: true)
    }
}
