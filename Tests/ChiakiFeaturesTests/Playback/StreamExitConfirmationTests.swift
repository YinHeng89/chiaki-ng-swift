@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture

@MainActor @Test func leavingAStreamWaitsForConfirmation() async {
    let store = TestStore(initialState: StreamMenuReducer.State(context: .console(.local))) {
        StreamMenuReducer()
    }
    await store.send(.requestExit("the Back to library button")) {
        $0.exitRequest = "the Back to library button"
    }
    await store.send(.requestExit("Escape"))
    await store.send(.cancelExit) {
        $0.exitRequest = nil
    }
    await store.send(.confirmExit(.disconnect))
    await store.send(.requestExit("Escape")) {
        $0.exitRequest = "Escape"
    }
    await store.send(.confirmExit(.disconnect)) {
        $0.exitRequest = nil
    }
    await store.receive(.delegate(.stopRequested(.disconnect)))
}

@MainActor @Test func exitChoicesFollowTheLeaveSettingOnlyForConsoleStreams() {
    var state = StreamMenuReducer.State(context: .console(.local))
    #expect(state.exitChoices == .disconnectOrRestMode)
    state.leaveAction = .restMode
    #expect(state.exitChoices == .restMode)
    state.leaveAction = .leaveOn
    #expect(state.exitChoices == .disconnect)
    for context in [StreamTuningContext.cloud("pscloud"), .guest] {
        var other = StreamMenuReducer.State(context: context)
        other.leaveAction = .restMode
        #expect(other.exitChoices == .disconnect)
        #expect(!other.consoleCommandsAvailable)
    }
}

@MainActor @Test func confirmedExitIsLimitedToTheOfferedChoices() async {
    var initial = StreamMenuReducer.State(context: .console(.local))
    initial.leaveAction = .restMode
    initial.exitRequest = "Escape"
    let store = TestStore(initialState: initial) {
        StreamMenuReducer()
    }
    await store.send(.confirmExit(.disconnect)) {
        $0.exitRequest = nil
    }
    await store.receive(.delegate(.stopRequested(.restMode)))

    var cloud = StreamMenuReducer.State(context: .cloud("pscloud"))
    cloud.exitRequest = "Escape"
    let cloudStore = TestStore(initialState: cloud) {
        StreamMenuReducer()
    }
    await cloudStore.send(.confirmExit(.restMode)) {
        $0.exitRequest = nil
    }
    await cloudStore.receive(.delegate(.stopRequested(.disconnect)))
    await cloudStore.send(.goHome)
}

private let console = RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5)

@MainActor @Test func confirmingTheExitStopsTheConsoleStream() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let id = StreamSessionID(uuid: UUID(0))
    await store.send(.startConsole(account: UUID(), console: console, route: .local))
    await store.send(.event(id, .firstFrame))
    await store.send(.view(.requestExit("Escape")))
    await store.receive(.menu(.requestExit("Escape")))
    await store.send(.menu(.confirmExit(.disconnect)))
    await store.receive(.menu(.delegate(.stopRequested(.disconnect))))
    await store.receive(.stopped(id, .left))
    #expect(calls.exits.value == [.disconnect])
    #expect(store.state.status == .idle)
}

@MainActor @Test func restModeExitAsksPlaybackToRestBeforeStopping() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let id = StreamSessionID(uuid: UUID(0))
    await store.send(.startConsole(account: UUID(), console: console, route: .local))
    await store.send(.event(id, .firstFrame))
    await store.send(.menu(.requestExit("Escape")))
    await store.send(.menu(.confirmExit(.restMode)))
    await store.receive(.menu(.delegate(.stopRequested(.restMode))))
    await store.receive(.stopped(id, .left))
    #expect(calls.exits.value == [.restMode])
}

@MainActor @Test func goHomeOnlyReachesPlaybackWhilePlaying() async {
    let calls = StreamSessionCalls()
    let idle = calls.store()
    await idle.send(.menu(.goHome))
    await idle.finish()
    #expect(calls.homes.value == 0)
    let store = calls.store()
    let id = StreamSessionID(uuid: UUID(0))
    await store.send(.startConsole(account: UUID(), console: console, route: .local))
    await store.send(.menu(.goHome))
    #expect(calls.homes.value == 0)
    await store.send(.event(id, .firstFrame))
    await store.send(.menu(.goHome))
    await store.receive(.menu(.delegate(.goHomeRequested)))
    await store.send(.stop)
    await store.receive(.stopped(id, .left))
    #expect(calls.homes.value == 1)
}

@MainActor @Test func restModeExitReachesPlaybackBeforeTheSessionIsCancelled() async {
    let events = LockIsolated([String]())
    let store = StreamSessionCalls().store {
        $0.streamSession.start = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in
                    events.withValue {
                        $0.append("cancelled")
                    }
                }
            }
        }
        $0.streamSession.leave = { _, exit in
            events.withValue {
                $0.append(exit == .restMode
                    ? "rest"
                    : "stop")
            }
            return .left
        }
    }
    let id = StreamSessionID(uuid: UUID(0))
    await store.send(.startConsole(account: UUID(), console: console, route: .local))
    await store.send(.event(id, .firstFrame))
    await store.send(.leave(.restMode))
    await store.receive(.stopped(id, .left))
    await store.finish()
    #expect(events.value == ["rest", "cancelled"])
}

@MainActor @Test func restModeBeforeTheStreamPlaysDisconnectsAndReportsTheRefusal() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let id = StreamSessionID(uuid: UUID(0))
    await store.send(.startConsole(account: UUID(), console: console, route: .local))
    await store.send(.leave(.restMode))
    await store.receive(.stopped(id, .restRefused))
    #expect(calls.exits.value == [.disconnect])
    #expect(store.state.restNotice != .hidden)
}

@MainActor @Test func theLeavePolicyLoadsEvenWhenPictureSettingsFail() async {
    struct Failure: Error {
    }
    let store = TestStore(initialState: StreamMenuReducer.State(context: .console(.local))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.streamSession.loadTuning = { _ in
            throw Failure()
        }
        $0.streamSession.saveTuning = { _, _ in
        }
        $0.settings = .inMemory([ConsolePowerSettings(leaveAction: .leaveOn)])
    }
    store.exhaustivity = .off
    await store.send(.load)
    await store.finish()
    await store.skipReceivedActions()
    #expect(store.state.phase == .failed)
    #expect(store.state.leaveAction == .leaveOn)
    #expect(store.state.exitChoices == .disconnect)
}

@MainActor @Test func theExitConfirmationHandlesNavigationOnlyForItsOwnWindow() {
    final class Window {
    }
    let own = Window()
    let other = Window()
    #expect(StreamExitConfirmationOverlay.owns(own, host: own))
    #expect(!StreamExitConfirmationOverlay.owns(other, host: own))
    #expect(!StreamExitConfirmationOverlay.owns(other, host: nil))
}

@MainActor @Test func leavingStopsAtOnceEvenWhenTheMenuSettingsCannotBeSaved() async {
    struct Failure: Error {
    }
    let saves = LockIsolated(0)
    var initial = StreamMenuReducer.State(context: .console(.local))
    initial.hasLoaded = true
    initial.phase = .ready
    initial.draft.volume = 0.5
    initial.exitRequest = "Escape"
    let store = TestStore(initialState: initial) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.loadTuning = { _ in
            StreamTuningConfiguration()
        }
        $0.streamSession.saveTuning = { _, _ in
            saves.withValue {
                $0 += 1
            }
            throw Failure()
        }
    }
    await store.send(.confirmExit(.disconnect)) {
        $0.exitRequest = nil
        $0.phase = .saving(UUID(0))
    }
    await store.receive(.delegate(.stopRequested(.disconnect)))
    await store.receive(.failed(UUID(0))) {
        $0.phase = .failed
    }
    #expect(saves.value == 1)
}
