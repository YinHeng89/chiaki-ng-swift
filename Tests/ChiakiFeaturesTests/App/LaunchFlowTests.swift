@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Synchronization
import Testing

private let account = UUID()
private let other = UUID()
private let consoleID = UUID()
private let console = RegistrationFlow.ConsoleTarget(
    address: "192.0.2.5", kind: .ps5, id: consoleID, name: "Living Room", hardwareID: "AABBCCDDEEFF"
)
private let registration = RegistrationFlow.Registration(profileID: account, console: console)
private let consoles = LaunchFlow.Consoles(registrations: [registration], selectedProfileID: other)

@Test func launchFlowResolvesConsolesByIdentifierNameOrHardwareID() {
    #expect(LaunchFlow.match(.id(consoleID), in: consoles) == registration)
    #expect(LaunchFlow.match(.name("living room"), in: consoles) == registration)
    #expect(LaunchFlow.match(.name("aabbccddeeff"), in: consoles) == registration)
    #expect(LaunchFlow.match(.name("192.0.2.5"), in: consoles) == registration)
    #expect(LaunchFlow.match(.name("Den"), in: consoles) == nil)
    let shared = RegistrationFlow.Registration(profileID: other, console: console)
    let both = LaunchFlow.Consoles(registrations: [registration, shared], selectedProfileID: other)
    #expect(LaunchFlow.match(.name("Living Room"), in: both) == shared)
}

@Test func launchFlowWaitsForSavedConsolesAndFollowsTheStreamOnceItConnects() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .name("Living Room"), display: .fullscreen(.zoom))
    let empty = LaunchFlow.Consoles(registrations: [], selectedProfileID: nil, catalog: .pending)
    #expect(flow.send(.requested(id, .stream(stream), empty, .idle)) == [.scheduleTimeout(id)])
    #expect(flow.phase == .resolving(id, stream))
    #expect(flow.send(.consolesChanged(empty)).isEmpty)
    let connect = LaunchConnect(id: id, profileID: account, console: console, route: .local)
    #expect(flow.send(.consolesChanged(consoles)) == [
        .scheduleConnectTimeout(id),
        .connect(connect, .fullscreen(.zoom))
    ])
    #expect(flow.phase == .connecting(connect, stream))
    #expect(flow.send(.timedOut(UUID())).isEmpty)
    #expect(flow.phase == .connecting(connect, stream))
    #expect(flow.send(.stream(.connecting(consoleID))) == [.cancelTimeout, .present(.fullscreen(.zoom))])
    #expect(flow.send(.timedOut(id)).isEmpty)
    #expect(flow.phase == .streaming(id, stream))
    #expect(flow.send(.stream(.playing(consoleID))).isEmpty)
    #expect(flow.send(.stream(.idle)) == [.restoreDisplay])
    #expect(flow.phase == .idle)
}

@Test func launchFlowWaitsForTheActiveAccountWhenSeveralProfilesShareTheConsole() {
    var flow = LaunchFlow()
    let id = UUID()
    let shared = RegistrationFlow.Registration(profileID: other, console: console)
    let stream = LaunchStream(console: .id(consoleID))
    let pending = LaunchFlow.Consoles(
        registrations: [registration, shared], selectedProfileID: account, catalog: .pending
    )
    #expect(flow.send(.requested(id, .stream(stream), pending, .idle)) == [.scheduleTimeout(id)])
    let loaded = LaunchFlow.Consoles(registrations: [registration, shared], selectedProfileID: other)
    let connect = LaunchConnect(id: id, profileID: other, console: console, route: .local)
    #expect(flow.send(.consolesChanged(loaded)) == [.scheduleConnectTimeout(id), .connect(connect, .window)])
}

@Test func launchFlowReportsUnknownConsolesOnceConsolesHaveLoaded() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .name("Den"))
    let pending = LaunchFlow.Consoles(
        registrations: [registration],
        selectedProfileID: other,
        catalog: .pending
    )
    _ = flow.send(.requested(id, .stream(stream), pending, .idle))
    #expect(flow.send(.consolesChanged(consoles)) == [
        .cancelTimeout,
        .report(.consoleNotFound(.name("Den")))
    ])
    #expect(flow.phase == .idle)
    #expect(flow.send(.requested(UUID(), .stream(stream), consoles, .idle)) == [
        .cancelTimeout, .report(.consoleNotFound(.name("Den")))
    ])
    let failed = LaunchFlow.Consoles(registrations: [], selectedProfileID: nil, catalog: .failed)
    #expect(flow.send(.requested(UUID(), .stream(stream), failed, .idle)) == [
        .cancelTimeout, .report(.consolesUnavailable)
    ])
}

@Test func launchFlowTimesOutOnlyWhileResolvingAndIgnoresStaleTimeouts() {
    var flow = LaunchFlow()
    let first = UUID()
    let second = UUID()
    let stream = LaunchStream(console: .name("Den"))
    let empty = LaunchFlow.Consoles(registrations: [], selectedProfileID: nil, catalog: .pending)
    _ = flow.send(.requested(first, .stream(stream), empty, .idle))
    _ = flow.send(.requested(second, .stream(stream), empty, .idle))
    #expect(flow.send(.timedOut(first)).isEmpty)
    #expect(flow.phase == .resolving(second, stream))
    #expect(flow.send(.timedOut(second)) == [.report(.consolesUnavailable)])
    #expect(flow.phase == .idle)
}

@Test func launchFlowRejectsRemoteStreamsWithoutARemoteRegistration() {
    var flow = LaunchFlow()
    let stream = LaunchStream(console: .id(consoleID), route: .remote)
    #expect(flow.send(.requested(UUID(), .stream(stream), consoles, .idle)) == [
        .cancelTimeout, .report(.remoteUnavailable("Living Room"))
    ])
}

@Test func launchFlowQuitsAfterTheLaunchedStreamWhenAsked() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .id(consoleID), exit: .quitApp)
    _ = flow.send(.requested(id, .stream(stream), consoles, .idle))
    #expect(flow.exitWatch == .launch(id, then: .disabled))
    _ = flow.send(.stream(.connecting(consoleID)))
    #expect(flow.exitWatch == .launch(id, then: .disabled))
    _ = flow.send(.stream(.playing(consoleID)))
    #expect(flow.exitWatch == .watching)
    #expect(flow.send(.stream(.idle)) == [.restoreDisplay, .quit])
    #expect(flow.exitWatch == .quitting)
    #expect(flow.send(.stream(.playing(consoleID))).isEmpty)
    #expect(flow.send(.stream(.idle)).isEmpty)
}

@Test func launchFlowRejectedConnectQuitsWhenTheLaunchAskedToExit() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    #expect(flow.send(.connectRejected(UUID(), .screenBusy)).isEmpty)
    #expect(flow.send(.connectRejected(id, .remoteNeedsSignIn)) == [
        .cancelTimeout, .restoreDisplay, .report(.rejected(.remoteNeedsSignIn)), .quit
    ])
    #expect(flow.exitWatch == .quitting)
    #expect(flow.send(.stream(.playing(consoleID))).isEmpty)
    #expect(flow.send(.stream(.idle)).isEmpty)
}

@Test func launchFlowSessionExitQuitsAfterAnyConsoleStream() {
    var flow = LaunchFlow()
    #expect(flow.send(.requested(UUID(), .session(.quitApp), consoles, .idle)).isEmpty)
    #expect(flow.send(.stream(.idle)).isEmpty)
    _ = flow.send(.stream(.connecting(nil)))
    #expect(flow.send(.stream(.idle)).isEmpty)
    _ = flow.send(.stream(.playing(nil)))
    #expect(flow.send(.stream(.resuming)).isEmpty)
    #expect(flow.exitWatch == .watching)
    _ = flow.send(.stream(.playing(nil)))
    #expect(flow.send(.stream(.idle)) == [.quit])
}

@Test func launchFlowStartupFailureQuitsWhenTheLaunchAskedToExit() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    _ = flow.send(.stream(.connecting(consoleID)))
    #expect(flow.send(.stream(.idle)) == [.restoreDisplay, .quit])
    #expect(flow.phase == .idle)
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowStartupFailureKeepsTheAppOpenWithoutAnExitRequest() {
    var flow = LaunchFlow()
    _ = flow.send(.requested(UUID(), .stream(LaunchStream(console: .id(consoleID))), consoles, .idle))
    _ = flow.send(.stream(.connecting(consoleID)))
    #expect(flow.send(.stream(.idle)) == [.restoreDisplay])
    #expect(flow.exitWatch == .disabled)
}

@Test func launchFlowEndsAConnectThatNeverStartsAStream() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(id, .stream(LaunchStream(console: .id(consoleID))), consoles, .idle))
    #expect(flow.send(.timedOut(id)) == [.cancelConnect, .restoreDisplay, .report(.notStarted)])
    #expect(flow.phase == .idle)
    let next = UUID()
    let connect = LaunchConnect(id: next, profileID: account, console: console, route: .local)
    #expect(flow.send(.requested(next, .stream(LaunchStream(console: .id(consoleID))), consoles, .idle))
        == [.scheduleConnectTimeout(next), .connect(connect, .window)])
}

@Test func launchFlowQuitsWhenAConnectThatAskedToExitNeverStarts() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    #expect(flow.send(.timedOut(id)) == [.cancelConnect, .restoreDisplay, .report(.notStarted), .quit])
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowQuitsWhenAConsoleThatAskedToExitCannotBeFound() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .name("Den"), exit: .quitApp)
    #expect(flow.send(.requested(id, .stream(stream), consoles, .idle)) == [
        .cancelTimeout, .report(.consoleNotFound(.name("Den"))), .quit
    ])
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowQuitsWhenSavedConsolesNeverLoadForALaunchThatAskedToExit() {
    var flow = LaunchFlow()
    let id = UUID()
    let pending = LaunchFlow.Consoles(registrations: [], selectedProfileID: nil, catalog: .pending)
    let stream = LaunchStream(console: .id(consoleID), exit: .quitApp)
    #expect(flow.send(.requested(id, .stream(stream), pending, .idle)) == [.scheduleTimeout(id)])
    #expect(flow.send(.timedOut(id)) == [.report(.consolesUnavailable), .quit])
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowDropsALaunchWhenAnotherConsoleStartsStreamingWithoutQuitting() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    #expect(flow.send(.stream(.connecting(UUID()))) == [.cancelTimeout, .cancelConnect, .restoreDisplay])
    #expect(flow.phase == .idle)
    #expect(flow.exitWatch == .disabled)
    #expect(flow.send(.timedOut(id)).isEmpty)
    #expect(flow.send(.stream(.playing(UUID()))).isEmpty)
    #expect(flow.send(.stream(.idle)).isEmpty)
}

@Test func launchFlowKeepsTheSessionExitWhenALaunchIsSuperseded() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(UUID(), .session(.quitApp), consoles, .idle))
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    #expect(flow.exitWatch == .launch(id, then: .session))
    _ = flow.send(.stream(.connecting(UUID())))
    #expect(flow.exitWatch == .session)
    _ = flow.send(.stream(.playing(UUID())))
    #expect(flow.send(.stream(.idle)) == [.quit])
}

@Test func launchFlowQuitsForAFailedLaunchThatAskedToExitWhileTheSessionWatchIsArmed() {
    var flow = LaunchFlow()
    _ = flow.send(.requested(UUID(), .session(.quitApp), consoles, .idle))
    let stream = LaunchStream(console: .name("Den"), exit: .quitApp)
    #expect(flow.send(.requested(UUID(), .stream(stream), consoles, .idle)) == [
        .cancelTimeout, .report(.consoleNotFound(.name("Den"))), .quit
    ])
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowQuitsForAFailedExitLaunchWhileAWatchedSessionStreamResumes() {
    var flow = LaunchFlow()
    _ = flow.send(.requested(UUID(), .session(.quitApp), consoles, .idle))
    _ = flow.send(.stream(.playing(consoleID)))
    #expect(flow.exitWatch == .watching)
    #expect(flow.send(.stream(.resuming)).isEmpty)
    let stream = LaunchStream(console: .name("Den"), exit: .quitApp)
    #expect(flow.send(.requested(UUID(), .stream(stream), consoles, .resuming)) == [
        .cancelTimeout, .report(.consoleNotFound(.name("Den"))), .quit
    ])
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowLeavesTheSessionWatchArmedWhenALaunchWithoutAnExitFails() {
    var flow = LaunchFlow()
    _ = flow.send(.requested(UUID(), .session(.quitApp), consoles, .idle))
    let stream = LaunchStream(console: .name("Den"))
    #expect(flow.send(.requested(UUID(), .stream(stream), consoles, .idle)) == [
        .cancelTimeout, .report(.consoleNotFound(.name("Den")))
    ])
    #expect(flow.exitWatch == .session)
}

@Test func launchFlowKeepsTheLaunchExitThroughASleepResume() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .id(consoleID), exit: .quitApp)
    _ = flow.send(.requested(id, .stream(stream), consoles, .idle))
    _ = flow.send(.stream(.connecting(consoleID)))
    #expect(flow.send(.stream(.resuming)).isEmpty)
    #expect(flow.phase == .streaming(id, stream))
    #expect(flow.exitWatch == .launch(id, then: .disabled))
    #expect(flow.send(.stream(.idle)) == [.restoreDisplay, .quit])
    #expect(flow.exitWatch == .quitting)
}

@Test func launchFlowStaysOpenWhenAnExitLaunchLosesToAnotherStream() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    #expect(flow.send(.connectRejected(id, .streamActive)) == [
        .cancelTimeout, .restoreDisplay, .report(.rejected(.streamActive))
    ])
    #expect(flow.exitWatch == .disabled)
}

@Test func launchFlowExplainsThatThePreviousStreamIsStillClosing() {
    var flow = LaunchFlow()
    #expect(flow.send(.requested(
        UUID(),
        .stream(LaunchStream(console: .id(consoleID))),
        consoles,
        .closing(consoleID)
    ))
        == [.report(.rejected(.streamClosing))])
    #expect(flow.phase == .idle)
}

@Test func launchFlowKeepsALaunchedStreamWhileItCloses() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(
        id,
        .stream(LaunchStream(console: .id(consoleID), exit: .quitApp)),
        consoles,
        .idle
    ))
    _ = flow.send(.stream(.connecting(consoleID)))
    _ = flow.send(.stream(.playing(consoleID)))
    #expect(flow.send(.stream(.closing(consoleID))).isEmpty)
    #expect(flow.send(.stream(.idle)) == [.restoreDisplay, .quit])
}

@Test func launchFlowWaitingForConsolesDoesNotTakeOverAStreamStartedMeanwhile() {
    var flow = LaunchFlow()
    let id = UUID()
    let pending = LaunchFlow.Consoles(registrations: [], selectedProfileID: nil, catalog: .pending)
    let stream = LaunchStream(console: .id(consoleID), exit: .quitApp)
    #expect(flow.send(.requested(id, .stream(stream), pending, .idle)) == [.scheduleTimeout(id)])
    #expect(flow.send(.stream(.playing(consoleID))).isEmpty)
    #expect(flow.send(.consolesChanged(consoles)) == [.cancelTimeout, .report(.busy)])
    #expect(flow.phase == .idle)
    #expect(flow.exitWatch == .disabled)
    #expect(flow.send(.stream(.idle)).isEmpty)
}

@Test func launchFlowRefusesASecondLaunchWhileOneIsConnecting() {
    var flow = LaunchFlow()
    let id = UUID()
    _ = flow.send(.requested(id, .stream(LaunchStream(console: .id(consoleID))), consoles, .idle))
    #expect(flow.send(.requested(UUID(), .stream(LaunchStream(console: .id(consoleID))), consoles, .idle))
        == [.report(.busy)])
    #expect(flow.send(.requested(
        UUID(),
        .stream(LaunchStream(console: .id(consoleID))),
        consoles,
        .playing(nil)
    ))
        == [.report(.busy)])
    guard case .connecting(let connect, _) = flow.phase else {
        Issue.record("The first launch should still be connecting")
        return
    }
    #expect(connect.id == id)
}

private let awake = DiscoverySnapshot(
    consoles: [
        DiscoveredConsole(
            id: "AABBCCDDEEFF", name: "Living Room", address: "192.0.2.5", kind: .ps5, standby: false
        )
    ],
    networkAvailable: true
)

private let scanFindingTheConsoleAwake: @Sendable () async -> AsyncStream<ConsoleScanEvent> = {
    AsyncStream { continuation in
        continuation.yield(.snapshot(awake))
    }
}

@MainActor private func streamSession(_ store: TestStoreOf<RootFeature>) -> StreamSessionID? {
    store.state.stream.session.id
}

private func profilesPage() -> RootFeature.State {
    var flow = RegistrationFlow()
    flow.restoreProfiles([
        .init(id: account, name: "Demo", kind: .npsso, accountID: nil),
        .init(id: other, name: "Other", kind: .npsso, accountID: nil)
    ], selected: other)
    flow.restoreRegistrations([registration])
    var state = RootFeature.State(route: .library)
    state.appData = flow
    state.accounts = AccountsFeature.State(loaded: [])
    state.catalogStatus = .loaded
    state.autoConnection.library = .ready(flow.registrations, selected: other)
    return state
}

private final class LaunchRecord: Sendable {
    let prepared = Mutex<[LaunchDisplay]>([])
    let presented = Mutex<[LaunchDisplay]>([])
    let quits = Mutex(0)

    func recording(on platform: PlatformClient) -> PlatformClient {
        var client = platform
        client.prepareLaunch = { [self] display in
            prepared.withLock {
                $0.append(display)
            }
        }
        client.presentLaunch = { [self] display in
            presented.withLock {
                $0.append(display)
            }
        }
        client.quit = { [self] in
            quits.withLock {
                $0 += 1
            }
        }
        return client
    }
}

@MainActor @Test func aLaunchRequestFindsTheConsolePlaysItAndQuitsAfterwards() async throws {
    let clock = TestClock()
    let record = LaunchRecord()
    let store = TestStore(initialState: profilesPage()) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.consoles.scanEvents = scanFindingTheConsoleAwake
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.platform = record.recording(on: $0.platform)
    }
    store.exhaustivity = .off
    let stream = LaunchStream(console: .name("Living Room"), display: .fullscreen(.stretch), exit: .quitApp)
    await store.send(.launchRequested(.stream(stream)))
    await store.receive(.launch(.delegate(.connect(LaunchConnect(
        id: UUID(0),
        profileID: account,
        console: console,
        route: .local
    )))))
    await store.receive(.autoConnect(.start(consoleID, .stream(.local))))
    await store.receive(.stream(.startConsole(
        account: account,
        console: console,
        route: .local
    )))
    #expect(store.state.selectedAccount == account)
    #expect(store.state.route == .stream)
    #expect(store.state.launch.flow.phase == .streaming(UUID(0), stream))
    #expect(record.prepared.withLock { $0 } == [.fullscreen(.stretch)])
    let session = try #require(streamSession(store))
    await store.send(.stream(.event(session, .firstFrame)))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(session, .left)))
    await store.finish()
    #expect(record.presented.withLock { $0 } == [.fullscreen(.stretch)])
    #expect(record.quits.withLock { $0 } == 1)
    #expect(store.state.launch.flow.phase == .idle)
}

@MainActor @Test func aLaunchThatNeverStartsAStreamTimesOutCancelsItsConnectAndQuits() async {
    let clock = TestClock()
    let cancelled = Mutex(false)
    let restores = Mutex(0)
    let quits = Mutex(0)
    let store = TestStore(initialState: profilesPage()) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.platform.prepareLaunch = { _ in
            do {
                try await Task.never()
            } catch {
                cancelled.withLock {
                    $0 = true
                }
            }
        }
        $0.platform.restoreLaunch = {
            restores.withLock {
                $0 += 1
            }
        }
        $0.platform.quit = {
            quits.withLock {
                $0 += 1
            }
        }
    }
    store.exhaustivity = .off
    let stream = LaunchStream(console: .name("Living Room"), exit: .quitApp)
    await store.send(.launchRequested(.stream(stream)))
    await store.receive(\.launch.requested)
    let connect = LaunchConnect(id: UUID(0), profileID: account, console: console, route: .local)
    #expect(store.state.launch.flow.phase == .connecting(connect, stream))
    await clock.advance(by: LaunchFeature.connectTimeout)
    await store.receive(.launch(.timedOut(UUID(0))))
    await store.finish()
    #expect(store.state.launch.flow.phase == .idle)
    #expect(store.state.launch.flow.exitWatch == .quitting)
    #expect(store.state.stream.status == .idle)
    #expect(cancelled.withLock { $0 })
    #expect(restores.withLock { $0 } == 1)
    #expect(quits.withLock { $0 } == 1)
    #expect(store.state.launch.notice == LaunchFeature.notice(.notStarted))
}

@MainActor @Test func aLaunchThatAskedToExitSurvivesASleepResumeAndQuitsWhenItEnds() async throws {
    let clock = TestClock()
    let quits = Mutex(0)
    let store = TestStore(initialState: profilesPage()) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.consoles.scanEvents = scanFindingTheConsoleAwake
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.platform.quit = {
            quits.withLock {
                $0 += 1
            }
        }
    }
    store.exhaustivity = .off
    let stream = LaunchStream(console: .name("Living Room"), exit: .quitApp)
    await store.send(.launchRequested(.stream(stream)))
    await store.receive(.stream(.startConsole(
        account: account,
        console: console,
        route: .local
    )))
    let first = try #require(streamSession(store))
    await store.send(.stream(.event(first, .firstFrame)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(first, .left)))
    #expect(store.state.launch.flow.phase == .streaming(UUID(0), stream))
    await store.send(.lifecycle(.delegate(.woke)))
    await store.receive(.wakeResume(.woke))
    guard case .waiting(let resume, _) = store.state.wakeResumption.machine else {
        Issue.record("Waking should schedule a resume")
        return
    }
    await clock.advance(by: WakeResumeFeature.resumeDelay)
    await store.receive(.wakeResume(.due(resume)))
    await store.receive(.stream(.startConsole(
        account: account,
        console: console,
        route: .local
    )))
    #expect(quits.withLock { $0 } == 0)
    #expect(store.state.launch.flow.phase == .streaming(UUID(0), stream))
    let second = try #require(streamSession(store))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(second, .left)))
    await store.finish()
    #expect(quits.withLock { $0 } == 1)
}

@MainActor @Test func aLaunchRequestDuringAStreamIsRejected() async {
    let clock = TestClock()
    var state = profilesPage()
    state.stream.session = .playing(StreamSessionID())
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
    }
    store.exhaustivity = .off
    await store.send(.launchRequested(.stream(LaunchStream(console: .id(consoleID)))))
    #expect(store.state.launch.flow.phase == .idle)
    await store.send(.launch(.delegate(.connect(LaunchConnect(
        id: UUID(5), profileID: account, console: console, route: .local
    )))))
    await store.receive(.launch(.connectRejected(UUID(5), .streamActive)))
    await store.finish()
    #expect(store.state.launch.notice == LaunchFeature.notice(.busy))
    await store.send(.launch(.notice(.dismiss)))
    #expect(store.state.launch.notice == nil)
}

@MainActor @Test func connectRejectsRemotePlayForAnAccountWithoutPlayStationNetwork() async {
    let remote = RegistrationFlow.ConsoleTarget(
        address: "192.0.2.7", kind: .ps5, remoteDeviceID: Data(repeating: 1, count: 32), id: UUID(),
        name: "Den"
    )
    var flow = RegistrationFlow()
    flow.restoreProfiles([.init(id: account, name: "Local", kind: .accountID, accountID: "AAAAAAAAAAA=")])
    flow.restoreRegistrations([.init(profileID: account, console: remote)])
    var state = RootFeature.State(route: .library)
    state.appData = flow
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    store.exhaustivity = .off
    let request = LaunchConnect(id: UUID(), profileID: account, console: remote, route: .remote)
    await store.send(.launch(.delegate(.connect(request))))
    await store.receive(.launch(.connectRejected(request.id, .remoteNeedsSignIn)))
    #expect(store.state.route == .library)
    let unlinked = LaunchConnect(id: UUID(), profileID: other, console: remote, route: .local)
    await store.send(.launch(.delegate(.connect(unlinked))))
    await store.receive(.launch(.connectRejected(unlinked.id, .consoleNotLinked)))
}

@Test func launchFlowWaitsLongerWhileTheConsoleIsFoundOrWokenThenHandsBackToTheConnectTimeout() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .id(consoleID))
    let connect = LaunchConnect(id: id, profileID: account, console: console, route: .local)
    #expect(flow.send(.requested(id, .stream(stream), consoles, .idle)) == [
        .scheduleConnectTimeout(id),
        .connect(connect, .window)
    ])
    #expect(flow.send(.stream(.preparing(consoleID))) == [.scheduleTimeout(id)])
    #expect(flow.send(.stream(.preparing(consoleID))).isEmpty)
    #expect(flow.send(.stream(.idle)) == [.scheduleConnectTimeout(id)])
    #expect(flow.send(.stream(.connecting(consoleID))) == [.cancelTimeout, .present(.window)])
    #expect(flow.phase == .streaming(id, stream))
}

@Test func launchFlowEndsQuietlyWhenFindingOrWakingTheConsoleFails() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .id(consoleID), exit: .quitApp)
    _ = flow.send(.requested(id, .stream(stream), consoles, .idle))
    _ = flow.send(.stream(.preparing(consoleID)))
    #expect(flow.send(.stream(.preparationFailed)) == [.cancelTimeout, .restoreDisplay, .quit])
    #expect(flow.phase == .idle)
}

@Test func launchFlowGivesWayWhenAnotherConsoleStartsConnecting() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .id(consoleID))
    _ = flow.send(.requested(id, .stream(stream), consoles, .idle))
    #expect(flow.send(.stream(.preparing(UUID()))) == [.cancelTimeout, .cancelConnect, .restoreDisplay])
    #expect(flow.phase == .idle)
}

@Test func launchFlowAcceptsALinkWhileAnotherConsoleIsBeingPrepared() {
    var flow = LaunchFlow()
    let id = UUID()
    let stream = LaunchStream(console: .id(consoleID))
    let connect = LaunchConnect(id: id, profileID: account, console: console, route: .local)
    #expect(flow.send(.requested(id, .stream(stream), consoles, .preparing(UUID()))) == [
        .scheduleConnectTimeout(id),
        .connect(connect, .window)
    ])
    #expect(flow.send(.requested(UUID(), .stream(stream), consoles, .preparationFailed)) == [.report(.busy)])
}
