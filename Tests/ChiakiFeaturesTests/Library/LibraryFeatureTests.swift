@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func theLibraryStartsAndStopsItsFeaturesWithTheScene() async {
    let account = UUID()
    let store = TestStore(initialState: LibraryFeature.State(section: .cloud)) {
        LibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.continuousClock = TestClock()
        $0.date.now = Date(timeIntervalSince1970: 0)
    }
    store.exhaustivity = .off
    @Shared(.accounts) var accounts
    @Shared(.selectedAccount) var selected
    $accounts.withLock {
        $0 = [.init(id: account, name: "PSN", kind: .npsso, accountID: nil)]
    }
    $selected.withLock {
        $0 = account
    }
    await store.send(.scenePhaseChanged(.active))
    await store.receive(.delegate(.acquireDiscovery))
    #expect(store.state.discovery == .watching(DiscoverySnapshot()))
    await store.receive(.cloudStatus(.select(account)))
    await store.receive(.cloudLibrary(.account(account)))
    #expect(store.state.cloudLibrary.accountID == account)
    await store.send(.scenePhaseChanged(.inactive))
    await store.receive(.delegate(.releaseDiscovery))
    #expect(store.state.discovery == .idle)
    await store.receive(.cloudStatus(.stop))
    await store.receive(.cloudLibrary(.stop))
    #expect(store.state.cloudStatus.scope == nil)
    await store.skipInFlightEffects(strict: false)
}

@MainActor @Test func theLibraryResumesTheStopThatHeldFocusWhenItIsShownAgain() async {
    let store = TestStore(initialState: LibraryFeature.State(section: .consoles)) {
        LibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off
    await store.send(.task)
    #expect(store.state.focusRequest == .firstConsole)
    await store.send(.focusMoved(.addConsole)) {
        $0.heldFocus = .addConsole
    }
    await store.send(.focusRequestHandled)
    await store.send(.disappeared)
    await store.send(.task)
    #expect(store.state.focusRequest == .resume(.addConsole))
    await store.skipInFlightEffects(strict: false)
}

@MainActor @Test func theLibraryLeavesTheCloudWhenTheAccountCannotUseIt() async {
    let account = UUID()
    @Shared(.accounts) var accounts
    @Shared(.selectedAccount) var selected
    $accounts.withLock {
        $0 = [.init(id: account, name: "Local", kind: .accountID, accountID: "AAAAAAAAAAA=")]
    }
    $selected.withLock {
        $0 = account
    }
    let store = TestStore(initialState: LibraryFeature.State(section: .consoles)) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    #expect(store.state.cloudUnavailable)
    await store.send(.sectionSelected(.cloud))
    #expect(store.state.section == .consoles)
}

@MainActor @Test func theLibraryShowsWhatTheRootsDiscoveryReportsOnlyWhileItHoldsTheLease() async {
    let snapshot = DiscoverySnapshot(consoles: [], networkAvailable: true)
    let store = TestStore(initialState: LibraryFeature.State(section: .consoles)) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    await store.send(.discoveryUpdated(snapshot))
    #expect(store.state.discovery == .idle)
    await store.send(.scenePhaseChanged(.active))
    await store.receive(.delegate(.acquireDiscovery))
    await store.send(.discoveryUpdated(snapshot)) {
        $0.discovery = .watching(snapshot)
    }
    await store.send(.discoveryFailed) {
        $0.discovery = .failed(snapshot)
    }
    #expect(store.state.discovery.isRequested)
    await store.send(.disappeared)
    await store.receive(.delegate(.releaseDiscovery))
    #expect(store.state.discovery == .idle)
    await store.skipInFlightEffects(strict: false)
}

@MainActor @Test func playingOnAPS5ThatJoinedAGameStartsRemotePlayToIt() async {
    let account = UUID()
    let den = RegistrationFlow.ConsoleTarget(
        address: "192.168.1.20",
        kind: .ps5,
        id: UUID(),
        name: "Den",
        hardwareID: "0123456789ab"
    )
    @Shared(.accounts) var accounts
    @Shared(.selectedAccount) var selected
    @Shared(.consoleCatalog) var catalog
    $accounts.withLock {
        $0 = [.init(id: account, name: "PSN", kind: .npsso, accountID: nil)]
    }
    $selected.withLock {
        $0 = account
    }
    $catalog.withLock {
        $0 = [RegistrationFlow.Registration(profileID: account, console: den)]
    }
    var state = LibraryFeature.State(section: .consoles)
    state.alerts.panel = .open
    let store = TestStore(initialState: state) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    await store.send(.alerts(.delegate(.playOn(HardwareID(hex: "0123456789ab")!))))
    await store.receive(.alertsPanelClosed)
    await store.receive(.requested(.startConsole(den, .local)))
    await store.receive(.delegate(.requested(.startConsole(den, .local))))
}

@MainActor @Test func playingAnInvitationInTheCloudLaunchesItsGameCarryingTheInvitation() async throws {
    let account = UUID()
    @Shared(.accounts) var accounts
    @Shared(.selectedAccount) var selected
    $accounts.withLock {
        $0 = [.init(id: account, name: "PSN", kind: .npsso, accountID: nil)]
    }
    $selected.withLock {
        $0 = account
    }
    var state = LibraryFeature.State(section: .consoles)
    state.cloudLibrary.accountID = account
    state.cloudLibrary.listing.snapshot = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[
    {"productId":"EP0000-CUSA01234_00-GAME000000000000","name":"Old","platform":"ps4","category":"owned",
    "isOwned":true,"plusCatalog":true,"streamServiceType":"psnow","streamIdentifier":"old"},
    {"productId":"EP0000-PPSA01234_00-GAME000000000000","name":"New","platform":"ps5","category":"owned",
    "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"new"}]}
    """.utf8))
    state.cloudLibrary.phase = .ready
    let invitation = CloudGameInvitation(
        id: "11111111-2222-3333-4444-555555555555",
        inviter: "Friend",
        sessionName: "",
        titleIDs: ["PPSA01234_00", "CUSA01234_00"],
        sent: nil,
        unread: true,
        players: 1,
        maxPlayers: 4,
        joining: .joinable
    )
    state.alerts.items = [PSNAlertsFeature.Item(
        id: "invitation:1",
        kind: .invitation(invitation),
        arrived: Date(timeIntervalSince1970: 0)
    )]
    state.alerts.panel = .open
    #expect(state.cloudGame(joining: invitation)?.productId == "EP0000-PPSA01234_00-GAME000000000000")
    #expect(state.cloudPlayableAlerts == ["invitation:1"])
    let store = TestStore(initialState: state) {
        LibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off
    await store.send(.alerts(.delegate(.playInCloud(invitation))))
    await store.receive(.alertsPanelClosed)
    await store.receive(.sectionSelected(.cloud))
    #expect(store.state.section == .cloud)
    await store.receive(\.cloudLibrary.checkAndPlay) {
        _ = $0
    }
    #expect(store.state.cloudLibrary.launchChecks?.request.joining == invitation)
    await store.skipInFlightEffects(strict: false)
}
