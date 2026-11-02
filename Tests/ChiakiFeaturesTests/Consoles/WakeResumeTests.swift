@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels

import ComposableArchitecture
import Foundation
import Testing

private let account = UUID()
private let consoleID = UUID()
private let console = RegistrationFlow.ConsoleTarget(
    address: "192.0.2.5", kind: .ps5, remoteDeviceID: Data([1]), id: consoleID, name: "Living Room"
)

private func readyPage() -> RootFeature.State {
    var flow = RegistrationFlow()
    flow.restoreProfiles([.init(id: account, name: "Demo", kind: .npsso, accountID: nil)], selected: account)
    flow.restoreRegistrations([.init(profileID: account, console: console)])
    flow.selectConsole(console)
    var state = RootFeature.State(route: .library)
    state.appData = flow
    return state
}

@MainActor private func wakeStore(_ clock: TestClock<Duration>) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: readyPage()) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func aStreamInterruptedBySleepRestartsOnTheSameRouteAfterWake() async {
    let clock = TestClock()
    let store = wakeStore(clock)
    await store.send(.view(.play(.remote)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .remote)))
    await store.send(.stream(.event(StreamSessionID(uuid: UUID(0)), .firstFrame)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.receive(\.wakeResume.sleeping)
    let target = StreamTarget(account: account, consoleID: consoleID, route: .remote)
    #expect(store.state.wakeResumption.machine == .interrupted(target))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(StreamSessionID(uuid: UUID(0)), .left)))
    #expect(store.state.route == .library)
    await store.send(.lifecycle(.delegate(.woke)))
    await store.receive(.wakeResume(.woke))
    #expect(store.state.wakeResumption.machine == .waiting(UUID(1), target))
    await clock.advance(by: WakeResumeFeature.resumeDelay)
    await store.receive(.wakeResume(.due(UUID(1))))
    #expect(store.state.wakeResumption.machine == .replaying(UUID(1), target))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .remote)))
    await store.receive(.wakeResume(.streamStarted))
    #expect(store.state.wakeResumption.machine == .idle)
    #expect(store.state.route == .stream)
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func sleepWithoutAStreamOrALeaveBeforeWakeDoesNotResume() async {
    let clock = TestClock()
    let store = wakeStore(clock)
    await store.send(.lifecycle(.delegate(.sleeping)))
    #expect(store.state.wakeResumption.machine == .idle)
    await store.send(.lifecycle(.delegate(.woke)))
    #expect(store.state.wakeResumption.machine == .idle)

    await store.send(.view(.play(.local)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(StreamSessionID(uuid: UUID(0)), .left)))
    await store.send(.lifecycle(.delegate(.woke)))
    await store.send(.view(.leaveStream))
    await store.receive(.wakeResume(.interrupted))
    #expect(store.state.wakeResumption.machine == .idle)
    await clock.advance(by: .seconds(10))
    #expect(store.state.route == .library)
    #expect(store.state.stream.status == .idle)
    await store.finish()
}

@MainActor @Test func turningOffReconnectAfterWakeLeavesTheStreamEnded() async {
    let clock = TestClock()
    let store = TestStore(initialState: readyPage()) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.settings = .inMemory([ConsolePowerSettings(resumeAfterWake: false)])
    }
    store.exhaustivity = .off
    await store.send(.view(.play(.local)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(StreamSessionID(uuid: UUID(0)), .left)))
    await store.send(.lifecycle(.delegate(.woke)))
    await store.receive(.wakeResume(.skipped(UUID(1))))
    #expect(store.state.wakeResumption.machine == .idle)
    await clock.advance(by: .seconds(10))
    #expect(store.state.stream.status == .idle)
    await store.finish()
}

@MainActor @Test func switchingStreamSettingsKeepsTheSavedLeaveChoice() async {
    let id = StreamSessionID()
    var initial = StreamFeature.State()
    initial.session = .playing(id)
    initial.source = StreamFeature.source(account: account, console: console, route: .local)
    initial.menu = StreamMenuReducer.State(context: .console(.local))
    initial.menu.leaveAction = .leaveOn
    let store = StreamSessionCalls().store(initial: initial)
    await store.send(.event(id, .pictureRoute(.remote)))
    #expect(store.state.menu.context == .console(.remote))
    #expect(store.state.menu.leaveAction == .leaveOn)
    #expect(store.state.menu.exitChoices == .disconnect)
}

@MainActor @Test func aStreamThatFailedDuringSleepStillResumesAfterWake() async {
    let clock = TestClock()
    let store = wakeStore(clock)
    await store.send(.view(.play(.local)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.send(.stream(.failed(StreamSessionID(uuid: UUID(0)), .renderer)))
    #expect(store.state.route == .stream)
    await store.send(.lifecycle(.delegate(.woke)))
    await clock.advance(by: WakeResumeFeature.resumeDelay)
    await store.receive(.wakeResume(.due(UUID(1))))
    await store.receive(.stream(.dismissFailure))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    #expect(store.state.route == .stream)
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func sleepingAgainBeforeTheResumeKeepsItPending() async {
    let clock = TestClock()
    let store = wakeStore(clock)
    await store.send(.view(.play(.local)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(StreamSessionID(uuid: UUID(0)), .left)))
    let target = StreamTarget(account: account, consoleID: consoleID, route: .local)
    await store.send(.lifecycle(.delegate(.woke)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.receive(\.wakeResume.sleeping)
    #expect(store.state.wakeResumption.machine == .interrupted(target))
    await store.send(.lifecycle(.delegate(.woke)))
    await clock.advance(by: WakeResumeFeature.resumeDelay)
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func aResumeTheLibraryCannotStartEndsAtOnce() async {
    let target = StreamTarget(account: account, consoleID: consoleID, route: .local)
    var state = readyPage()
    state.wakeResumption.machine = .waiting(UUID(9), target)
    state.stream.session = .stopping(StreamSessionID(), .disconnect)
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off
    await store.send(.wakeResume(.due(UUID(9))))
    await store.receive(.wakeResume(.refused))
    #expect(store.state.wakeResumption.machine == .idle)
    await store.finish()
}

@MainActor @Test func aReplayThatNeverStartsAStreamGivesUpAfterItsDeadline() async {
    let clock = TestClock()
    let target = StreamTarget(account: account, consoleID: consoleID, route: .local)
    var waiting = WakeResumeFeature.State()
    waiting.machine = .waiting(UUID(9), target)
    let store = TestStore(initialState: waiting) {
        WakeResumeFeature()
    } withDependencies: {
        $0.continuousClock = clock
    }
    await store.send(.due(UUID(9))) {
        $0.machine = .replaying(UUID(9), target)
    }
    await store.receive(.delegate(.resume(target)))
    await clock.advance(by: WakeResumeFeature.replayDeadline)
    await store.receive(.skipped(UUID(9))) {
        $0.machine = .idle
    }
    await store.finish()
}

@MainActor @Test func aLocalStreamResumesOnTheLocalNetworkWithoutAskingTheCore() async {
    let clock = TestClock()
    let store = wakeStore(clock)
    await store.send(.view(.play(.local)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    let session = StreamSessionID(uuid: UUID(0))
    await store.send(.stream(.event(session, .route(.home))))
    await store.send(.stream(.event(session, .firstFrame)))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.receive(\.wakeResume.sleeping)
    let target = StreamTarget(account: account, consoleID: consoleID, route: .local, played: true)
    #expect(store.state.wakeResumption.machine == .interrupted(target))
    await store.send(.stream(.stop))
    await store.receive(.stream(.stopped(session, .left)))
    await store.send(.lifecycle(.delegate(.woke)))
    await store.receive(.wakeResume(.woke))
    await clock.advance(by: WakeResumeFeature.resumeDelay)
    await store.receive(.wakeResume(.due(UUID(1))))
    await store.receive(.stream(.startConsole(
        account: account,
        console: console,
        route: .local,
        keepsRoute: true
    )))
    #expect(store.state.stream.source.map {
        if case .console(_, let route) = $0 {
            return route == .homeOnly
        }
        return false
    } == true)
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func aStreamTheCoreSentOverTheInternetResumesOverTheInternet() async {
    let clock = TestClock()
    let store = wakeStore(clock)
    await store.send(.view(.play(.local)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    let session = StreamSessionID(uuid: UUID(0))
    await store.send(.stream(.event(session, .route(.internet))))
    await store.send(.lifecycle(.delegate(.sleeping)))
    await store.receive(\.wakeResume.sleeping)
    #expect(store.state.wakeResumption.machine == .interrupted(
        StreamTarget(account: account, consoleID: consoleID, route: .remote, played: true)
    ))
    await store.send(.stream(.stop))
    await store.finish()
}
