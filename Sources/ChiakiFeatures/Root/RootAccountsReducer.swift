import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Keeps the root's accounts, console pairings and selection in step with what the accounts, the console
/// catalog and the account screens report.
///
/// It adds the accounts the sign-in and account id screens produce, restores the remembered account after the
/// accounts load, persists every new selection, moves to the right screen when the accounts change and tells
/// automatic connection when the library is ready.
struct RootAccountsReducer: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    @Dependency(\.uuid) private var uuid
    @Dependency(\.accounts) private var accountsClient
    @Dependency(\.logger) private var logger

    /// Reacts to the accounts, the catalog, the account screens and the restored selection.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .activeAccountRestored(let id, let active):
                guard state.restoringSelection == id else {
                    return .none
                }
                state.restoringSelection = nil
                state.appData.restoreSelection(active)
                return Self.libraryChanged(state)
            case .accounts(.delegate(let delegate)):
                return accountsReported(delegate, state: &state)
            case .consoleCatalog(.delegate(let delegate)):
                return catalogReported(delegate, state: &state)
            case .route(.signIn(.delegate(.started))):
                return .send(.autoConnect(.interrupted))
            case .route(.signIn(.delegate(.signedIn(let profile)))):
                return .merge(
                    .send(.accounts(.adopt(profile))),
                    .send(.library(.alerts(.restart(ProfileID(uuid: profile.id)))))
                )
            case .route(.signIn(.delegate(.left))), .route(.accountIDEntry(.delegate(.left))):
                return RootRouter.show(.welcome, state: &state)
            case let .route(.accountIDEntry(.delegate(.submitted(name, account)))):
                return .send(.accounts(.addAccountID(profile: uuid(), name: name, account: account)))
            default:
                return .none
            }
        }
    }

    /// Selects an account from the library and persists the choice.
    ///
    /// - Parameters:
    ///   - id: The account.
    ///   - state: The application's state.
    /// - Returns: The effects that refresh the accounts and follow the new selection.
    func select(_ id: UUID, state: inout State) -> Effect<Action> {
        let refresh = Effect<Action>.send(.accounts(.refresh(force: false)))
        guard state.route == .library, state.appData.selectProfile(id) else {
            return refresh
        }
        state.restoringSelection = nil
        return .merge(
            refresh,
            persist(id),
            Self.libraryChanged(state),
            Self.stopForeignCloudPlayback(state)
        )
    }

    /// Remembers the selected account for the next launch.
    ///
    /// - Parameter id: The account.
    /// - Returns: The effect that saves it.
    func persist(_ id: UUID) -> Effect<Action> {
        .run { [accountsClient] _ in
            _ = await accountsClient.selectAccount(id)
        }
    }

    private func accountsReported(_ delegate: AccountsFeature.Action.Delegate,
                                  state: inout State) -> Effect<Action> {
        switch delegate {
        case .loaded(let profiles):
            return loaded(profiles, state: &state)
        case .loadFailed:
            let arrival = state.route == .launching
                ? RootRouter.show(.welcome, state: &state)
                : .none
            return .merge(arrival, .send(.autoConnect(.libraryChanged(.unavailable))))
        case .saved(let profile):
            return saved(profile, state: &state)
        case .deleted(let id):
            state.appData.removeProfile(id)
            return .merge(
                Self.arriveAfterAccountsChanged(state: &state),
                Self.libraryChanged(state),
                Self.stopForeignCloudPlayback(state)
            )
        case let .refreshStarted(count, reason):
            return log(.info, AccountRefreshSummary.started(count: count, reason: reason))
        case let .refreshed(before, result):
            return refreshed(before: before, result: result, state: &state)
        case .refreshFailed:
            return log(
                .error,
                "Account refresh failed: storage could not be read or updated; it runs again at the next 60 s check"
            )
        }
    }

    private func loaded(_ profiles: [AccountProfile], state: inout State) -> Effect<Action> {
        state.appData.restoreProfiles(profiles.map(RegistrationFlow.Profile.init))
        let arrival = Self.arriveAfterAccountsChanged(state: &state)
        let id = OperationID(uuid: uuid())
        state.restoringSelection = id
        return .merge(
            arrival,
            .send(.consoleCatalog(.observe)),
            .concatenate(
                .run { [accountsClient] send in
                    if let active = await accountsClient.selectedAccount() {
                        await send(.activeAccountRestored(id, active))
                    }
                },
                .send(.consoleCatalog(.load))
            )
        )
    }

    private func saved(_ profile: AccountProfile, state: inout State) -> Effect<Action> {
        let others = state.accounts.accounts.filter {
            $0.id != profile.id
        }
        state.appData.restoreProfiles(
            (others + [profile]).map(RegistrationFlow.Profile.init),
            selected: profile.id
        )
        return .merge(
            RootRouter.show(.library, state: &state),
            persist(profile.id),
            Self.libraryChanged(state)
        )
    }

    private func refreshed(
        before: [AccountProfile],
        result: AccountRefreshResult,
        state: inout State
    ) -> Effect<Action> {
        let selectionGone = state.appData
            .updateProfiles(result.accounts.map(RegistrationFlow.Profile.init))
        let arrival = selectionGone
            ? Self.arriveAfterAccountsChanged(state: &state)
            : .none
        return .merge(
            arrival,
            Self.libraryChanged(state),
            log(
                result.issues.isEmpty
                    ? .info
                    : .warning,
                AccountRefreshSummary.message(before: before, after: result)
            )
        )
    }

    private func catalogReported(
        _ delegate: ConsoleCatalogFeature.Action.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .loaded(let consoles):
            state.catalogStatus = .loaded
            state.appData.restoreRegistrations(consoles.map(RegistrationFlow.Registration.init))
            return Self.libraryChanged(state)
        case .failed:
            state.catalogStatus = .failed
            state.registrationFailure = .storage
            return .send(.autoConnect(.libraryChanged(.unavailable)))
        }
    }

    /// Stops a cloud stream that belongs to an account other than the selected one.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The effect that stops the stream, or none.
    static func stopForeignCloudPlayback(_ state: State) -> Effect<Action> {
        guard state.stream.isPresented, let profile = state.stream.cloudProfile,
              profile != state.selectedAccount else {
            return .none
        }
        return .send(.stream(.stop))
    }

    /// Tells automatic connection the library is ready once the accounts and the pairings are read.
    ///
    /// - Parameter state: The application's state.
    /// - Returns: The effect that reports the library, or none while it is still loading.
    static func libraryChanged(_ state: State) -> Effect<Action> {
        guard state.accounts.hasLoaded, state.catalogStatus == .loaded else {
            return .none
        }
        return .send(.autoConnect(.libraryChanged(.ready(
            state.registrations,
            selected: state.selectedAccount
        ))))
    }

    private static func arriveAfterAccountsChanged(state: inout State) -> Effect<Action> {
        switch state.route {
        case .launching:
            return RootRouter.show(state.home, state: &state)
        case .library where state.profiles.isEmpty:
            return RootRouter.show(.welcome, state: &state)
        case .welcome, .signIn, .accountIDEntry, .library, .addConsole, .pairing, .stream, .kakusanGuest:
            return .none
        }
    }

    private func log(_ level: LogLevel, _ message: String) -> Effect<Action> {
        .run { [logger] _ in
            await logger.log(.diagnostic(.accounts, level, message))
        }
    }
}
