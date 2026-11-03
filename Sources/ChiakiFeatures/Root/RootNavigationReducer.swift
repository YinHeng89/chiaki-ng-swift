import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Carries out what the user asks of the application: moving between screens, opening panels and joining
/// someone else's game.
///
/// Any request that leaves the current screen first interrupts automatic connection and wake resume, and
/// nothing navigates while an account is being deleted.
struct RootNavigationReducer: Reducer {
    /// The application's state.
    typealias State = RootFeature.State

    /// Everything the application reacts to.
    typealias Action = RootFeature.Action

    @Dependency(\.platform) private var platform

    /// Reacts to the user's requests from the root view, the library and opened files.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(let view):
                return reduce(view, state: &state)
            case .kakusanFileOpened(let block):
                return kakusanFileOpened(block, state: &state)
            case .library(.delegate(.requested(let request))):
                return libraryRequested(request, state: &state)
            case .library(.delegate(.showRecentlyPlayed(let selection))):
                return .send(.recentlyPlayed(.select(selection)))
            case .library(.delegate(.showAlert(let notice))):
                guard state.stream.session.isStreaming else {
                    return .send(.library(.toasts(.received(notice))))
                }
                return .send(.stream(.toasts(.received(notice))))
            default:
                return .none
            }
        }
    }

    private func reduce(_ view: Action.View, state: inout State) -> Effect<Action> {
        if case .deleting = state.accounts.operation, Self.navigates(view) {
            return .none
        }
        let interruptions: Effect<Action> = Self.navigates(view)
            ? .merge(.send(.autoConnect(.interrupted)), .send(.wakeResume(.interrupted)))
            : .none
        return .merge(interruptions, navigate(view, state: &state))
    }

    private static func navigates(_ view: Action.View) -> Bool {
        switch view {
        case .appeared, .sceneActivated, .sceneDeactivated, .disappeared, .openSettings, .closeSettings,
             .toggleSettings, .quitRequested, .reloadAccounts, .joinGame:
            false
        case .chooseSignIn, .chooseAccountID, .showLibrary, .cancelAccountWork, .selectAccount, .addAccount,
             .reconnectAccount, .addConsole, .selectConsole, .play, .playTitle, .leaveStream, .editConsole,
             .deleteConsole:
            true
        }
    }

    private func navigate(_ view: Action.View, state: inout State) -> Effect<Action> {
        switch view {
        case .appeared, .sceneActivated, .sceneDeactivated, .disappeared:
            return sceneChanged(view, state: &state)
        case .chooseSignIn, .chooseAccountID, .showLibrary, .reloadAccounts, .cancelAccountWork,
             .selectAccount,
             .addAccount, .reconnectAccount:
            return accountRequested(view, state: &state)
        case .addConsole, .selectConsole, .play, .playTitle, .leaveStream, .editConsole, .deleteConsole,
             .joinGame:
            return consoleRequested(view, state: &state)
        case .openSettings, .closeSettings, .toggleSettings, .quitRequested:
            return RootPresentationReducer().panelRequested(view, state: &state)
        }
    }

    private func sceneChanged(_ view: Action.View, state: inout State) -> Effect<Action> {
        switch view {
        case .appeared:
            return .send(.settings(.launched))
        case .sceneActivated:
            let reload: Effect<Action> = state.route.is(\.stream)
                ? .none
                : .send(.accounts(.load))
            return .merge(
                .send(.settings(.controls(.appeared))),
                .send(.autoConnect(.launch)),
                reload,
                .send(.accounts(.watch))
            )
        case .sceneDeactivated:
            return .send(.accounts(.stopWatching))
        case .disappeared:
            return teardown(state: &state)
        default:
            return .none
        }
    }

    private func accountRequested(_ view: Action.View, state: inout State) -> Effect<Action> {
        switch view {
        case .chooseSignIn:
            return showFromWelcome(
                .signIn(SignInFeature.State(offersBrowser: !platform.isPhone())),
                state: &state
            )
        case .chooseAccountID:
            return showFromWelcome(.accountIDEntry(AccountIDEntryFeature.State()), state: &state)
        case .showLibrary:
            guard !state.profiles.isEmpty else {
                return .none
            }
            return showFromWelcome(.library, state: &state)
        case .reloadAccounts:
            return .send(.accounts(.load))
        case .cancelAccountWork:
            return cancelAccountWork(state: &state)
        case .selectAccount(let id):
            return RootAccountsReducer().select(id, state: &state)
        case .addAccount:
            guard state.route == .library else {
                return .none
            }
            return RootRouter.show(.welcome, state: &state)
        case .reconnectAccount(let id):
            guard state.route == .library, state.appData.selectProfile(id) else {
                return .none
            }
            return RootRouter.show(
                .signIn(SignInFeature.State(reconnecting: id, offersBrowser: !platform.isPhone())),
                state: &state
            )
        default:
            return .none
        }
    }

    private func consoleRequested(_ view: Action.View, state: inout State) -> Effect<Action> {
        switch view {
        case .addConsole:
            return RootPairingReducer().showAddConsole(state: &state)
        case .selectConsole(let target):
            guard state.route == .library else {
                return .none
            }
            state.appData.selectConsole(target)
            return .none
        case .play(let route):
            guard state.route == .library,
                  let account = state.selectedAccount,
                  let consoleID = state.selectedConsole?.id
            else {
                return .none
            }
            let target = StreamTarget(account: account, consoleID: consoleID, route: route)
            return RootStreamReducer().startStream(.console(target, reselect: false), state: &state) ?? .none
        case let .playTitle(consoleID, title):
            return RootStreamReducer().playTitle(consoleID, title: title, state: &state)
        case .leaveStream:
            return .merge(
                RootRouter.leaveStream(state: &state),
                .send(.recentlyPlayed(.launch(.cancel))),
                .send(.stream(.stop))
            )
        case .editConsole(let draft):
            return RootPresentationReducer().presentConsoleEditor(.edit(draft), state: &state)
        case .deleteConsole(let console):
            return RootPresentationReducer().presentConsoleEditor(.requestDeletion(console), state: &state)
        case .joinGame:
            return openGuest(state: &state)
        default:
            return .none
        }
    }

    private func showFromWelcome(_ route: RootFeature.Route.State, state: inout State) -> Effect<Action> {
        guard state.route == .welcome else {
            return .none
        }
        return RootRouter.show(route, state: &state)
    }

    private func teardown(state: inout State) -> Effect<Action> {
        let home = state.route == .launching
            ? Effect<Action>.none
            : RootRouter.show(state.home, state: &state)
        return .merge(
            .send(.autoConnect(.interrupted)),
            .send(.wakeResume(.interrupted)),
            home,
            .send(.accounts(.stopWatching)),
            .send(.accounts(.stop)),
            .send(.recentlyPlayed(.launch(.cancel))),
            .send(.stream(.stop)),
            .send(.consoleCatalog(.stop)),
            .send(.discovery(.stop))
        )
    }

    private func cancelAccountWork(state: inout State) -> Effect<Action> {
        let cancelSaving = Effect<Action>.send(.accounts(.view(.cancelSaving)))
        switch state.route {
        case .signIn:
            return .merge(cancelSaving, .send(.route(.signIn(.view(.back)))))
        case .accountIDEntry:
            return .merge(cancelSaving, RootRouter.show(.welcome, state: &state))
        case .launching, .welcome, .library, .addConsole, .pairing, .stream, .kakusanGuest:
            return cancelSaving
        }
    }

    private func openGuest(state: inout State) -> Effect<Action> {
        guard KakusanBuild.included else {
            return .none
        }
        if state.route.is(\.kakusanGuest) {
            return .send(.route(.kakusanGuest(.open)))
        }
        guard state.route == .library || state.route == .welcome else {
            return .none
        }
        return .concatenate(
            RootRouter.show(.kakusanGuest(KakusanGuestFeature.State()), state: &state),
            .send(.route(.kakusanGuest(.open)))
        )
    }

    private func kakusanFileOpened(_ block: KakusanBlock, state: inout State) -> Effect<Action> {
        guard KakusanBuild.included else {
            return .none
        }
        switch block.kind {
        case .invitation:
            return .concatenate(
                openGuest(state: &state),
                .send(.route(.kakusanGuest(.submitInvitation(block.text))))
            )
        case .reply:
            return .send(.stream(.kakusan(.replyOpened(block.text))))
        case .unrecognised:
            return .none
        }
    }

    private func libraryRequested(_ request: LibraryRequest, state: inout State) -> Effect<Action> {
        switch request {
        case .addAccount:
            return reduce(.addAccount, state: &state)
        case .selectAccount(let id):
            return reduce(.selectAccount(id), state: &state)
        case .reconnectAccount(let id):
            return reduce(.reconnectAccount(id), state: &state)
        case .removeAccount(let id):
            return .send(.accounts(.view(.requestDeletion(id))))
        case .refreshAccounts:
            return .send(.accounts(.refresh(force: true)))
        case .addConsole:
            return reduce(.addConsole, state: &state)
        case let .startConsole(console, route):
            return .concatenate(
                reduce(.selectConsole(console), state: &state),
                reduce(.play(route), state: &state)
            )
        case .editConsole(let draft):
            return reduce(.editConsole(draft), state: &state)
        case .deleteConsole(let id):
            return reduce(.deleteConsole(id), state: &state)
        case let .playTitle(console, title):
            return reduce(.playTitle(console, title), state: &state)
        case .joinGame:
            return reduce(.joinGame, state: &state)
        case .showConsoleArt(let requests):
            return .send(.consoleArt(.show(requests)))
        }
    }
}
