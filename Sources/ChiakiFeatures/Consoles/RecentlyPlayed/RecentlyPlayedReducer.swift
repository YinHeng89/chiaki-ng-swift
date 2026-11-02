import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Keeps the selected account's recently played rails, refetching them when the account changes, on request,
/// and after a stream ends, and launches titles from them.
///
/// Each fetch carries an attempt id, so an answer for an earlier account or attempt is ignored.
@Reducer
public struct RecentlyPlayedReducer {
    /// The account the rails are for, and whether it can show them.
    public struct Selection: Equatable, Sendable {
        /// The selected account.
        public let profileID: UUID
        /// Whether the account can list PSN consoles and has a paired PS5, which the rails need.
        public let eligible: Bool
        /// Creates a selection.
        ///
        /// - Parameters:
        ///   - profileID: The selected account.
        ///   - eligible: Whether the account can show the rails.
        public init(profileID: UUID, eligible: Bool) {
            self.profileID = profileID
            self.eligible = eligible
        }
    }
    /// Where fetching the rails is.
    public enum Phase: Equatable, Sendable {
        /// Nothing fetched yet, a fetch with this attempt id in flight, loaded, PSN sign-in expired, the
        /// titles could
        /// not be read, or the account is signed out of PSN.
        case idle, fetching(UUID), loaded, authExpired, unavailable, signedOut
    }
    /// The rails and how fetching them went.
    @ObservableState
    public struct State: Equatable {
        /// The account the rails are for.
        public var selection: Selection?
        /// Where fetching the rails is.
        public var phase: Phase = .idle
        /// The fetched rails with at least one title each.
        public var rails: [RecentlyPlayedRail] = []
        /// Whether another fetch runs once the one in flight answers.
        public var followUpQueued = false
        /// The title launch started from the rails.
        public var launch = TitleLaunchFeature.State.idle
        /// The trial mark of each title the account holds as a trial or demo, by title id, read from what the
        /// core already holds so the rails can mark trials before the cloud library loads.
        public var trialMarks: [String: CloudTrialMark] = [:]
        /// Creates state with no account and no rails.
        public init() {
        }
        /// Whether the rails are shown: the account can show them and is not signed out.
        public var visible: Bool {
            selection?.eligible == true && phase != .signedOut
        }
        /// Whether placeholder rails are shown while the first fetch runs.
        public var showsPlaceholders: Bool {
            guard visible, rails.isEmpty, case .fetching = phase else {
                return false
            }
            return true
        }
        /// Whether the rails show that the PSN sign-in expired.
        public var authExpired: Bool {
            visible && phase == .authExpired
        }
        /// The rail of a console, while the rails are shown and hold titles for it.
        ///
        /// - Parameter consoleID: The id of the saved console.
        /// - Returns: The console's rail, or `nil` when it has no titles or the rails are hidden.
        public func rail(for consoleID: UUID?) -> RecentlyPlayedRail? {
            guard visible, phase != .authExpired, let consoleID else {
                return nil
            }
            return rails.first {
                $0.consoleID == consoleID && !$0.titles.isEmpty
            }
        }
        /// The title being launched, while a launch runs.
        public var launchingTitle: RecentTitle? {
            if case .launching(_, let launch) = self.launch {
                return launch.title
            }
            return nil
        }
    }
    /// Everything the recently played rails react to.
    public enum Action: Equatable, Sendable {
        /// The selected account changed.
        case select(Selection?)
        /// Fetches again unless a fetch is in flight.
        case refresh
        /// A fetch of an account and attempt answered.
        case fetched(UUID, UUID, RecentlyPlayedFetch)
        /// A fetch of an account and attempt failed.
        case failed(UUID, UUID, ConsoleTitlesFailure)
        /// The core listed the games this account holds as a trial or demo for a fetch of an account and
        /// attempt.
        case trialsHeld(UUID, UUID, [CloudGame])
        /// The title launch started from the rails.
        case launch(TitleLaunchFeature.Action)
        /// A stream ended; refetches now and once more a few seconds later, since the console updates its
        /// list late.
        case streamEnded
        /// The delayed refetch after a stream is due.
        case followUpElapsed
        /// What the parent is told.
        case delegate(RecentlyPlayedDelegate)
    }
    /// Fetches and launches titles.
    @Dependency(\.consoles) var client
    /// The catalog that lists the account's held trials.
    @Dependency(\.catalog) var catalog
    /// Delays the refetch after a stream.
    @Dependency(\.continuousClock) var clock
    /// Makes each fetch's attempt id.
    @Dependency(\.uuid) var uuid
    /// Writes the diagnostic trace.
    @Dependency(\.logger) var logger
    /// Cancels the fetch in flight and the delayed refetch.
    public enum CancelID: Sendable {
        /// The fetch in flight, and the delayed refetch after a stream.
        case fetch, followUp
    }
    /// Creates the reducer.
    public init() {
    }
    public var body: some ReducerOf<Self> {
        Scope(state: \.launch, action: \.launch) {
            TitleLaunchFeature()
        }
        Reduce { state, action in
            switch action {
            case .select(let selection):
                return select(&state, selection)
            case .refresh:
                return refresh(&state)
            case let .fetched(profile, attempt, result):
                guard state.selection?.profileID == profile, state.phase == .fetching(attempt) else {
                    return .none
                }
                state.phase = .loaded
                state.rails = result.rails.filter {
                    !$0.titles.isEmpty
                }
                return followUp(&state)
            case let .trialsHeld(profile, attempt, games):
                guard state.selection?.profileID == profile, state.phase == .fetching(attempt) else {
                    return .none
                }
                state.trialMarks = CloudTrialMark.byTitle(games)
                return .none
            case let .failed(profile, attempt, failure):
                guard state.selection?.profileID == profile, state.phase == .fetching(attempt) else {
                    return .none
                }
                switch failure {
                case .signedOut:
                    state.phase = .signedOut
                    state.rails = []
                case .auth:
                    state.phase = .authExpired
                    state.rails = []
                case .rejected, .unavailable, .invalidDocument, .cancelled, .internalFailure:
                    state.phase = .unavailable
                }
                return followUp(&state)
            case .launch(.delegate(.startStream(let request))):
                return .send(.delegate(.startStream(request)))
            case .launch:
                return .none
            case .streamEnded:
                let ended: Effect<Action> = .send(.launch(.streamEnded))
                guard state.selection?.eligible == true else {
                    return ended
                }
                let now: Effect<Action>
                if case .fetching = state.phase {
                    state.followUpQueued = true
                    now = .none
                } else {
                    now = fetch(&state)
                }
                return .merge(
                    ended,
                    now,
                    .run { [clock] send in
                        try await clock.sleep(for: .seconds(5))
                        await send(.followUpElapsed)
                    }
                    .cancellable(id: CancelID.followUp, cancelInFlight: true)
                )
            case .followUpElapsed:
                guard state.selection?.eligible == true else {
                    return .none
                }
                if case .fetching = state.phase {
                    state.followUpQueued = true
                    return .none
                }
                return fetch(&state)
            case .delegate:
                return .none
            }
        }
    }
}

extension RecentlyPlayedReducer {
    private func select(_ state: inout State, _ selection: Selection?) -> Effect<Action> {
        guard state.selection?.profileID == selection?.profileID else {
            state.selection = selection
            state.phase = .idle
            state.rails = []
            state.trialMarks = [:]
            state.followUpQueued = false
            guard selection?.eligible == true else {
                return .merge(.cancel(id: CancelID.fetch), .cancel(id: CancelID.followUp))
            }
            return .merge(.cancel(id: CancelID.followUp), fetch(&state))
        }
        state.selection = selection
        guard selection?.eligible == true else {
            state.phase = .idle
            state.rails = []
            state.followUpQueued = false
            return .merge(.cancel(id: CancelID.fetch), .cancel(id: CancelID.followUp))
        }
        return refresh(&state)
    }

    private func refresh(_ state: inout State) -> Effect<Action> {
        guard state.selection?.eligible == true else {
            return .none
        }
        if case .fetching = state.phase {
            return .none
        }
        return fetch(&state)
    }

    private func followUp(_ state: inout State) -> Effect<Action> {
        guard state.followUpQueued else {
            return .none
        }
        state.followUpQueued = false
        return fetch(&state)
    }

    private func fetch(_ state: inout State) -> Effect<Action> {
        guard let selection = state.selection, selection.eligible else {
            return .none
        }
        let profile = selection.profileID
        let attempt = uuid()
        state.phase = .fetching(attempt)
        return .run { [client, catalog] send in
            async let trials = catalog.heldTrials(profile)
            await send(.trialsHeld(profile, attempt, trials))
            do {
                let result = try await client.recentlyPlayed(profile)
                try Task.checkCancellation()
                await send(.fetched(profile, attempt, result))
            } catch is CancellationError {
                return
            } catch {
                await send(.failed(profile, attempt, error as? ConsoleTitlesFailure ?? .unavailable))
            }
        }
        .cancellable(id: CancelID.fetch, cancelInFlight: true)
    }
}

/// What the recently played rails ask of their parent.
public enum RecentlyPlayedDelegate: Equatable, Sendable {
    /// Start streaming the console that is launching a title.
    case startStream(TitleLaunch)
}
