import ChiakiModels
import ChiakiClients

@testable import ChiakiFeatures
import ComposableArchitecture
import Foundation
import Testing

private let account = UUID()
private let consoleID = UUID()
private let hardware = Data(repeating: 0xef, count: 6)
private let console = RegistrationFlow.ConsoleTarget(
    address: "192.0.2.5", kind: .ps5, id: consoleID, name: "Living Room"
)
private let title = RecentTitle(
    titleID: "PPSA01234_00", launchID: "PPSA01234", name: "Game", imageURL: "https://example.com/a.png"
)

private func consolePage() -> RootFeature.State {
    var flow = RegistrationFlow()
    flow.restoreProfiles([.init(id: account, name: "Demo", kind: .npsso, accountID: nil)], selected: account)
    flow.restoreRegistrations([.init(profileID: account, console: console)])
    var state = RootFeature.State(route: .library)
    state.appData = flow
    state.recentlyPlayed.selection = .init(profileID: account, eligible: true)
    state.recentlyPlayed.phase = .loaded
    state.recentlyPlayed.rails = [RecentlyPlayedRail(
        consoleID: consoleID,
        hardwareID: hardware,
        titles: [title]
    )]
    return state
}

@MainActor @Test func playingATitleLaunchesThenStreamsLocallyAndResendsOnceAfterAPIN() async {
    let launches = LockIsolated<[String]>([])
    let page = consolePage()
    let store = TestStore(initialState: page) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.consoles.launchTitle = { owner, device, title in
            launches.withValue { $0.append("\(owner == account):\(device == hardware):\(title.titleID)") }
            throw ConsoleTitlesFailure.unavailable
        }
    }
    store.exhaustivity = .off
    let request = TitleLaunch(accountID: account, consoleID: consoleID, hardwareID: hardware, title: title)
    await store.send(.view(.playTitle(consoleID, title)))
    #expect(store.state.route == .stream)
    #expect(store.state.selectedConsole == console)
    await store.receive(.recentlyPlayed(.launch(.play(request))))
    #expect(store.state.recentlyPlayed.launchingTitle == title)
    await store.receive(.recentlyPlayed(.launch(.launchFinished(OperationID(uuid: UUID(0))))))
    await store.receive(.recentlyPlayed(.launch(.delegate(.startStream(request)))))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.receive(.recentlyPlayed(.launch(.streamStarted(UUID(1)))))
    #expect(store.state.recentlyPlayed.launch == .streaming(UUID(1), request, .none))

    await store.send(.stream(.event(
        StreamSessionID(uuid: UUID(1)),
        .accessRequested(.loginPIN(retry: false))
    )))
    await store.receive(.recentlyPlayed(.launch(.loginPINRequested(UUID(1)))))
    await store.send(.stream(.event(StreamSessionID(uuid: UUID(1)), .firstFrame)))
    await store.receive(.recentlyPlayed(.launch(.streamConnected(UUID(1)))))
    await store.send(.stream(.event(
        StreamSessionID(uuid: UUID(1)),
        .accessRequested(.loginPIN(retry: true))
    )))
    await store.send(.stream(.event(StreamSessionID(uuid: UUID(1)), .firstFrame)))
    await store.skipReceivedActions(strict: false)
    #expect(store.state.recentlyPlayed.launch == .streaming(UUID(1), request, .resent))

    await store.send(.view(.leaveStream))
    await store.receive(.stream(.stopped(StreamSessionID(uuid: UUID(1)), .left)))
    await store.receive(.recentlyPlayed(.streamEnded))
    #expect(store.state.recentlyPlayed.launch == .idle)
    await store.skipInFlightEffects()
    #expect(launches.value == ["true:true:PPSA01234_00", "true:true:PPSA01234_00"])
}

@MainActor @Test func leavingDuringTheLaunchCancelsItWithoutStartingAStream() async {
    let clock = TestClock()
    let page = consolePage()
    let store = TestStore(initialState: page) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.consoles.launchTitle = { _, _, _ in
            try await clock.sleep(for: .seconds(10))
            return .completed
        }
    }
    store.exhaustivity = .off
    await store.send(.view(.playTitle(consoleID, title)))
    await store.receive(.recentlyPlayed(.launch(.play(TitleLaunch(
        accountID: account, consoleID: consoleID, hardwareID: hardware, title: title
    )))))
    await store.send(.view(.leaveStream))
    await store.receive(.recentlyPlayed(.launch(.cancel)))
    await clock.advance(by: .seconds(20))
    await store.skipReceivedActions(strict: false)
    #expect(store.state.route == .library)
    #expect(store.state.stream.status == .idle)
    #expect(store.state.recentlyPlayed.launch == .idle)
}

@MainActor @Test func aTitleIsNotPlayedOnAConsoleWithoutARailOrOnAPS4() async {
    var state = consolePage()
    state.recentlyPlayed.rails = []
    state.library.recentlyPlayed = state.recentlyPlayed
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    await store.send(.view(.playTitle(consoleID, title)))
    await store.receive(.autoConnect(.interrupted))
    await store.receive(.wakeResume(.interrupted))
    await store.send(.view(.playTitle(UUID(), title)))
    await store.receive(.autoConnect(.interrupted))
    await store.receive(.wakeResume(.interrupted))
    #expect(store.state.route == .library)
}
