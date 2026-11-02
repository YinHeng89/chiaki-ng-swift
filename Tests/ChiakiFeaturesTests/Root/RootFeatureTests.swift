import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
private let consoleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
private let console = RegistrationFlow.ConsoleTarget(
    address: "192.0.2.5", kind: .ps5, id: consoleID, name: "Living Room"
)

private func libraryState() -> RootFeature.State {
    var state = RootFeature.State(route: .library)
    state.appData.restoreProfiles([
        .init(id: accountID, name: "Demo", kind: .npsso, accountID: AccountID(value: 1).base64)
    ])
    state.appData.restoreRegistrations([.init(profileID: accountID, console: console)])
    return state
}

@MainActor private func rootStore(
    _ state: RootFeature.State,
    quits: LockIsolated<Int> = LockIsolated(0)
) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.logger = .disabled
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
        $0.platform = PlatformClient(
            shutdown: {},
            quit: {
                quits.withValue {
                    $0 += 1
                }
            }
        )
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.accounts.refresh = {
            .failure(.refreshFailed)
        }
        $0.accounts.selectAccount = { _ in
            true
        }
        $0.consoles.pairings = {
            .success([])
        }
        $0.consoles.launchOptions = { _ in
            .success(ConsoleLaunchOptions())
        }
        $0.consoles.saveDraft = { _ in
            nil
        }
        $0.consoles.deleteConsole = { _ in
            nil
        }
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func theWelcomeScreenLeadsToSignInAndAccountIDEntryAndTheirDelegatesReturn() async {
    let store = rootStore(RootFeature.State(route: .welcome))
    await store.send(.view(.chooseSignIn)) {
        $0.route = .signIn(SignInFeature.State())
    }
    await store.send(.route(.signIn(.delegate(.left)))) {
        $0.route = .welcome
    }
    await store.send(.view(.chooseAccountID)) {
        $0.route = .accountIDEntry(AccountIDEntryFeature.State())
    }
    await store.send(.route(.accountIDEntry(.delegate(.left)))) {
        $0.route = .welcome
    }
    await store.send(.view(.showLibrary))
    #expect(store.state.route == .welcome)
}

@MainActor @Test func aSignInThatStartsInterruptsAutoConnectAndASignedInAccountIsAdopted() async {
    let store = rootStore(RootFeature.State(route: .signIn(SignInFeature.State())))
    let profile = AccountProfile(
        id: accountID,
        name: "Player",
        method: .npsso,
        accountID: AccountID(value: 7)
    )
    await store.send(.route(.signIn(.delegate(.started))))
    await store.receive(.autoConnect(.interrupted))
    await store.send(.route(.signIn(.delegate(.signedIn(profile)))))
    await store.receive(.accounts(.adopt(profile)))
    await store.receive(\.accounts.delegate.saved) {
        $0.route = .library
    }
    #expect(store.state.selectedAccount == accountID)
}

@MainActor @Test func launchingShowsTheLibraryOnceAccountsLoad() async {
    let profile = AccountProfile(
        id: accountID,
        name: "Player",
        method: .npsso,
        accountID: AccountID(value: 7)
    )
    let store = rootStore(RootFeature.State())
    await store.send(.accounts(.delegate(.loaded([profile])))) {
        $0.route = .library
        $0.appData.restoreProfiles([RegistrationFlow.Profile(profile)])
        $0.restoringSelection = OperationID(uuid: UUID(0))
    }
}

@MainActor @Test func launchingWithoutAccountsShowsTheWelcomeScreen() async {
    let store = rootStore(RootFeature.State())
    await store.send(.accounts(.delegate(.loaded([])))) {
        $0.route = .welcome
        $0.restoringSelection = OperationID(uuid: UUID(0))
    }
}

@MainActor @Test func launchingShowsTheWelcomeScreenWhenTheAccountsCannotBeRead() async {
    let store = rootStore(RootFeature.State())
    await store.send(.accounts(.delegate(.loadFailed))) {
        $0.route = .welcome
    }
}

@MainActor @Test func addingAConsoleShowsItsRouteAndLeavingReleasesDiscovery() async {
    let store = rootStore(libraryState())
    await store.send(.view(.addConsole)) {
        $0.route = .addConsole(AddConsoleFeature.State(
            account: accountID,
            modes: AddConsoleMode.allCases,
            registered: [console]
        ))
    }
    await store.send(.route(.addConsole(.delegate(.left)))) {
        $0.route = .library
    }
    await store.receive(.discovery(.release(.addConsole)))
}

@MainActor @Test func startStreamShowsTheStreamRouteAndLeavingReturnsToTheLibrary() async {
    let store = rootStore(libraryState())
    await store.send(.view(.selectConsole(console))) {
        $0.selectedConsole = console
    }
    await store.send(.view(.play(.local))) {
        $0.route = .stream
    }
    await store.receive(.stream(.startConsole(account: accountID, console: console, route: .local)))
    await store.send(.view(.leaveStream)) {
        $0.route = .library
    }
    await store.receive(.stream(.stop))
}

@MainActor @Test func startStreamIsRefusedAwayFromTheLibrary() async {
    var away = libraryState()
    away.selectedConsole = console
    away.route = .welcome
    let welcome = rootStore(away)
    await welcome.send(.view(.play(.local)))
    #expect(welcome.state.route == .welcome)
}

@MainActor @Test func startStreamIsRefusedWithoutAPairing() async {
    let unpaired = rootStore(RootFeature.State(route: .library))
    let target = StreamTarget(account: accountID, consoleID: consoleID, route: .local)
    await unpaired.send(.wakeResume(.delegate(.resume(target))))
    await unpaired.receive(.wakeResume(.refused))
    #expect(unpaired.state.route == .library)
}

@MainActor @Test func anAutomaticConnectionStartsTheStreamThroughTheSameRoute() async {
    let store = rootStore(libraryState())
    let plan = AutoConnect.Plan(
        account: accountID,
        consoleID: consoleID,
        console: console,
        mode: .stream(.local)
    )
    await store.send(.autoConnect(.delegate(.play(plan, route: .local)))) {
        $0.route = .stream
        $0.selectedConsole = console
    }
    await store.receive(.stream(.startConsole(account: accountID, console: console, route: .local)))
}

@MainActor @Test func settingsIsTheRootDestination() async {
    let store = rootStore(libraryState())
    await store.send(.view(.openSettings)) {
        $0.destination = .settings
        $0.settingsOpenedAt = 0
    }
    #expect(store.state.settingsPresented)
    await store.send(.view(.closeSettings)) {
        $0.destination = nil
        $0.settingsOpenedAt = nil
    }
    await store.receive(.settings(.closed))
    await store.send(.view(.toggleSettings)) {
        $0.destination = .settings
        $0.settingsOpenedAt = 0
    }
    await store.send(.destination(.dismiss)) {
        $0.destination = nil
        $0.settingsOpenedAt = nil
    }
    await store.receive(.settings(.closed))
}

@MainActor @Test func quittingAsksFirstAndOnlyQuitsWhenConfirmed() async {
    let quits = LockIsolated(0)
    let store = rootStore(libraryState(), quits: quits)
    await store.send(.view(.quitRequested(.button))) {
        $0.destination = .alert(RootPresentationReducer.quitAlert(.button))
    }
    await store.send(.destination(.presented(.alert(.stay(.button))))) {
        $0.destination = nil
    }
    #expect(quits.value == 0)
    await store.send(.view(.quitRequested(.screen))) {
        $0.destination = .alert(RootPresentationReducer.quitAlert(.screen))
    }
    await store.send(.destination(.presented(.alert(.quit)))) {
        $0.destination = nil
    }
    await store.finish()
    #expect(quits.value == 1)
}

@MainActor @Test func quittingIsNotAskedOverAnotherDestination() async {
    var state = libraryState()
    state.destination = .settings
    let store = rootStore(state)
    await store.send(.view(.quitRequested(.screen)))
    #expect(store.state.destination == .settings)
}

@MainActor @Test func theConsoleEditorIsADestinationThatClosesItself() async {
    let draft = ConsoleDraft(
        id: consoleID, name: "Living Room", address: "192.0.2.5", generation: "PS5",
        remoteAvailable: false, hardwareID: "aabbccddeeff"
    )
    let store = rootStore(libraryState())
    await store.send(.view(.editConsole(draft))) {
        $0.destination = .consoleEditor(ConsoleEditorFeature.State())
    }
    await store.receive(\.destination.presented.consoleEditor.edit)
    await store.receive(\.destination.presented.consoleEditor.optionsLoaded)
    #expect(store.state.destination?.consoleEditor?.flow.draft != nil)
    await store.send(.destination(.presented(.consoleEditor(.view(.cancel)))))
    await store.receive(\.destination.presented.consoleEditor.delegate.closed) {
        $0.destination = nil
    }
}

@MainActor @Test func pairingAgainFromAStreamDropsThePairingAndOpensPairing() async {
    var state = libraryState()
    state.appData.restoreProfiles([
        .init(id: accountID, name: "Den", kind: .accountID, accountID: AccountID(value: 1).base64)
    ])
    state.appData.selectStream(profile: accountID, console: console)
    state.route = .stream
    let store = rootStore(state)
    await store.send(.stream(.delegate(.pairAgain(console)))) {
        $0.appData.forgetPairing(console)
        $0.route = .pairing(PairingFeature.State(
            account: AccountID(value: 1),
            target: .atHome(address: "192.0.2.5", kind: .ps5)
        ))
    }
    #expect(store.state.registrations.isEmpty)
    #expect(store.state.selectedConsole == nil)
}

@MainActor @Test func joiningAGameShowsTheGuestRouteOnlyWhenKakusanIsBuilt() async {
    let store = rootStore(libraryState())
    await store.send(.view(.joinGame))
    if KakusanBuild.included {
        await store.receive(.route(.kakusanGuest(.open)))
    }
    #expect(store.state.route.is(\.kakusanGuest) == KakusanBuild.included)
}
