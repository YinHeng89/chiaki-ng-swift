import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The accounts the app knows: loading, adding by account id, adopting signed-in accounts, deleting and
/// refreshing them.
///
/// One `ChiakiModels/AccountsOperation` runs at a time; the refresh is its own
/// `ChiakiModels/AccountsRefresh` machine beside it. Every completion carries the operation id that started
/// it. The parent learns about every change through ``Action/Delegate`` and never reads the machines.
@Reducer
public struct AccountsFeature {
    /// The accounts and the work on them.
    @ObservableState
    public struct State: Equatable {
        /// Whether the saved accounts have been read once.
        public enum Availability: Hashable, Sendable {
            /// The first load has not finished.
            case pending

            /// The first load finished, successfully or not.
            case settled
        }

        /// Every known account, in the order they were added.
        public internal(set) var accounts: [AccountProfile] = []

        /// Whether the first load finished.
        public internal(set) var availability = Availability.pending

        /// The running or last account operation.
        public internal(set) var operation = AccountsOperation.idle

        /// The refresh machine.
        public internal(set) var refresh = AccountsRefresh.idle

        /// When the last refresh finished.
        public internal(set) var lastRefreshed: Date?

        /// The accounts the last refresh could not refresh.
        public internal(set) var refreshIssues: [UUID: AccountRefreshResult.Issue] = [:]

        /// Creates the state before anything is loaded.
        public init() {}

        /// Creates the state after a load found these accounts.
        ///
        /// - Parameter accounts: The loaded accounts.
        public init(loaded accounts: [AccountProfile]) {
            self.accounts = accounts
            availability = .settled
        }

        /// Whether the first load finished.
        public var hasLoaded: Bool {
            availability == .settled
        }

        /// The accounts that must sign in again.
        public var needingSignIn: Set<UUID> {
            Set(refreshIssues.filter { $0.value == .signInRequired }.keys)
        }
    }

    /// Everything the accounts react to.
    public enum Action: Equatable {
        /// Reads the saved accounts, or refreshes them once they are known.
        case load

        /// Refreshes the accounts every minute until ``stopWatching``.
        case watch

        /// Stops the periodic refresh.
        case stopWatching

        /// Refreshes the accounts; an unforced refresh runs at most once a minute.
        case refresh(force: Bool)

        /// Saves an account added by account id.
        case addAccountID(profile: UUID, name: String, account: AccountID)

        /// Records an account a sign-in just saved.
        case adopt(AccountProfile)

        /// Abandons every operation, for teardown.
        case stop

        /// Something the user did.
        case view(View)

        /// The saved accounts were read.
        case loadFinished(OperationID, Result<[AccountProfile], AccountsFailure>)

        /// An account added by account id was saved.
        case saveFinished(OperationID, Result<AccountProfile, AccountsFailure>)

        /// A deletion ended, with why it failed.
        case deleteFinished(OperationID, AccountsFailure?)

        /// A refresh ended.
        case refreshFinished(OperationID, Result<AccountRefreshResult, AccountsFailure>)

        /// What the parent is told.
        case delegate(Delegate)

        /// What the user did.
        @CasePathable
        public enum View: Equatable {
            /// Asks to delete an account.
            case requestDeletion(UUID)

            /// Keeps the account.
            case cancelDeletion

            /// Deletes the account waiting for confirmation.
            case confirmDeletion

            /// Abandons saving an account added by account id.
            case cancelSaving
        }

        /// What the accounts report to their parent.
        @CasePathable
        public enum Delegate: Equatable {
            /// The saved accounts were read.
            case loaded([AccountProfile])

            /// The saved accounts could not be read.
            case loadFailed

            /// An account was saved or signed in again.
            case saved(AccountProfile)

            /// An account was deleted.
            case deleted(UUID)

            /// A refresh of this many accounts started.
            case refreshStarted(count: Int, reason: AccountsRefreshReason)

            /// A refresh finished; `before` is the list it replaced.
            case refreshed(before: [AccountProfile], result: AccountRefreshResult)

            /// A refresh could not read or update storage.
            case refreshFailed
        }
    }

    /// How often the accounts are refreshed while watched.
    public static let refreshInterval: Duration = .seconds(60)

    /// How old the last refresh must be, in seconds, before an unforced refresh runs.
    public static let refreshAge: TimeInterval = 60

    @Dependency(\.accounts) private var client
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        AccountsRefresher()
        Reduce { state, action in
            switch action {
            case .load:
                return load(&state)
            case let .addAccountID(profile, name, account):
                return addAccountID(&state, profile: profile, name: name, account: account)
            case .adopt(let profile):
                state.accounts.removeAll {
                    $0.id == profile.id
                }
                state.accounts.append(profile)
                state.refresh.stop()
                state.lastRefreshed = nil
                return .concatenate(
                    .cancel(id: AccountsCancelID.refresh),
                    .send(.delegate(.saved(profile))),
                    AccountsRefresher().start(&state, force: true)
                )
            case .stop:
                state.operation.stop()
                state.refresh.stop()
                return .merge(
                    .cancel(id: AccountsCancelID.operation),
                    .cancel(id: AccountsCancelID.refresh),
                    .cancel(id: AccountsCancelID.watch)
                )
            case .view(let view):
                return reduce(&state, view: view)
            case let .loadFinished(id, result):
                return loadFinished(&state, id: id, result: result)
            case let .saveFinished(id, result):
                return saveFinished(&state, id: id, result: result)
            case let .deleteFinished(id, failure):
                return deleteFinished(&state, id: id, failure: failure)
            case .watch, .stopWatching, .refresh, .refreshFinished, .delegate:
                return .none
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard state.accounts.isEmpty else {
            return AccountsRefresher().start(&state, force: false)
        }
        let id = OperationID(uuid: uuid())
        guard state.operation.startLoading(id) else {
            return .none
        }
        return .run { [client] send in
            await send(.loadFinished(id, client.load()))
        }
        .cancellable(id: AccountsCancelID.operation, cancelInFlight: true)
    }

    private func addAccountID(
        _ state: inout State,
        profile: UUID,
        name: String,
        account: AccountID
    ) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        guard state.operation.startSaving(id) else {
            return .none
        }
        state.refresh.stop()
        state.lastRefreshed = nil
        return .merge(
            .cancel(id: AccountsCancelID.refresh),
            .run { [client] send in
                await send(.saveFinished(id, client.addAccountID(profile, name, account)))
            }
            .cancellable(id: AccountsCancelID.operation, cancelInFlight: true)
        )
    }

    private func reduce(_ state: inout State, view: Action.View) -> Effect<Action> {
        switch view {
        case .requestDeletion(let profile):
            guard state.accounts.contains(where: { $0.id == profile }) else {
                return .none
            }
            state.operation.requestDeletion(of: profile)
            return .none
        case .cancelDeletion:
            state.operation.cancelDeletion()
            return .none
        case .confirmDeletion:
            let id = OperationID(uuid: uuid())
            guard let profile = state.operation.confirmDeletion(id) else {
                return .none
            }
            state.refresh.stop()
            return .merge(
                .cancel(id: AccountsCancelID.refresh),
                .run { [client] send in
                    await send(.deleteFinished(id, client.delete(profile)))
                }
                .cancellable(id: AccountsCancelID.operation, cancelInFlight: true)
            )
        case .cancelSaving:
            guard case .saving = state.operation else {
                return .none
            }
            state.operation.stop()
            return .cancel(id: AccountsCancelID.operation)
        }
    }

    private func loadFinished(
        _ state: inout State,
        id: OperationID,
        result: Result<[AccountProfile], AccountsFailure>
    ) -> Effect<Action> {
        switch result {
        case .success(let accounts):
            guard state.operation.finish(id, failure: nil) else {
                return .none
            }
            state.accounts = accounts
            state.availability = .settled
            return .concatenate(
                .send(.delegate(.loaded(accounts))),
                AccountsRefresher().start(&state, force: false)
            )
        case .failure(let failure):
            guard state.operation.finish(id, failure: failure) else {
                return .none
            }
            state.availability = .settled
            return .send(.delegate(.loadFailed))
        }
    }

    private func saveFinished(
        _ state: inout State,
        id: OperationID,
        result: Result<AccountProfile, AccountsFailure>
    ) -> Effect<Action> {
        switch result {
        case .success(let profile):
            guard state.operation.finish(id, failure: nil) else {
                return .none
            }
            state.accounts.removeAll {
                $0.id == profile.id
            }
            state.accounts.append(profile)
            return .concatenate(
                .send(.delegate(.saved(profile))),
                AccountsRefresher().start(&state, force: true)
            )
        case .failure(let failure):
            state.operation.finish(id, failure: failure)
            return .none
        }
    }

    private func deleteFinished(_ state: inout State, id: OperationID,
                                failure: AccountsFailure?) -> Effect<Action> {
        guard case .deleting(id, let profile) = state.operation,
              state.operation.finish(id, failure: failure) else {
            return .none
        }
        guard failure == nil else {
            return .none
        }
        state.accounts.removeAll {
            $0.id == profile
        }
        state.refreshIssues[profile] = nil
        state.lastRefreshed = nil
        return .send(.delegate(.deleted(profile)))
    }
}

/// The work on the accounts that a later request or teardown cancels.
private enum AccountsCancelID {
    /// The running load, save or deletion.
    case operation

    /// The running refresh.
    case refresh

    /// The periodic refresh while the accounts are watched.
    case watch
}

/// Refreshes the known accounts, on request and every ``AccountsFeature/refreshInterval`` while watched.
///
/// A refresh starts only when no account operation or other refresh runs, and an unforced one only once the
/// last refresh is ``AccountsFeature/refreshAge`` old. Its answer is accepted only from the refresh that is
/// still running.
private struct AccountsRefresher: Reducer {
    /// The accounts' state.
    typealias State = AccountsFeature.State

    /// What the accounts react to.
    typealias Action = AccountsFeature.Action

    @Dependency(\.accounts) private var client
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date.now) private var now
    @Dependency(\.continuousClock) private var clock

    /// Reacts to watching, refresh requests and refresh answers.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .watch:
                return .run { [clock] send in
                    while !Task.isCancelled {
                        try await clock.sleep(for: AccountsFeature.refreshInterval)
                        await send(.refresh(force: false))
                    }
                }
                .cancellable(id: AccountsCancelID.watch, cancelInFlight: true)
            case .stopWatching:
                return .cancel(id: AccountsCancelID.watch)
            case .refresh(let force):
                return start(&state, force: force)
            case let .refreshFinished(id, result):
                return finished(&state, id: id, result: result)
            default:
                return .none
            }
        }
    }

    /// Starts a refresh when the accounts allow one.
    ///
    /// - Parameters:
    ///   - state: The accounts' state.
    ///   - force: Whether to refresh however recent the last refresh is.
    /// - Returns: The effect that tells the parent and runs the refresh, or none.
    func start(_ state: inout State, force: Bool) -> Effect<Action> {
        guard state.operation.running == nil, !state.accounts.isEmpty, state.refresh.running == nil else {
            return .none
        }
        let reason: AccountsRefreshReason
        if let refreshed = state.lastRefreshed {
            let elapsed = now.timeIntervalSince(refreshed)
            guard force || elapsed >= AccountsFeature.refreshAge else {
                return .none
            }
            reason = force
                ? .accountAdded
                : .periodic(secondsSinceLast: Int(elapsed))
        } else {
            reason = force
                ? .accountAdded
                : .firstSinceLoad
        }
        let id = OperationID(uuid: uuid())
        state.refresh.start(id)
        return .merge(
            .send(.delegate(.refreshStarted(count: state.accounts.count, reason: reason))),
            .run { [client] send in
                await send(.refreshFinished(id, client.refresh()))
            }
            .cancellable(id: AccountsCancelID.refresh, cancelInFlight: true)
        )
    }

    private func finished(
        _ state: inout State,
        id: OperationID,
        result: Result<AccountRefreshResult, AccountsFailure>
    ) -> Effect<Action> {
        switch result {
        case .success(let refreshed):
            guard state.refresh.finish(id, clean: refreshed.issues.isEmpty) else {
                return .none
            }
            let before = state.accounts
            state.accounts = refreshed.accounts
            state.refreshIssues = refreshed.issues
            state.lastRefreshed = now
            return .send(.delegate(.refreshed(before: before, result: refreshed)))
        case .failure:
            guard state.refresh.finish(id, clean: false) else {
                return .none
            }
            state.lastRefreshed = now
            return .send(.delegate(.refreshFailed))
        }
    }
}
