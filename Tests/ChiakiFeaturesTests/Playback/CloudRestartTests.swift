@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let firstSession = StreamSessionID(uuid: UUID(0))

private func cloudSource() -> StreamSource {
    .cloud(CloudStreamRequest(
        profile: ProfileID(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!),
        title: CloudStreamTitle(
            product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
            name: "Example",
            service: .psCloud
        )
    ))
}

@MainActor @Test func aRestartClosesThePlayingCloudSessionAndStartsTheSameGameAgain() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    let source = cloudSource()
    await store.send(.start(source))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .closing(CloudClosingNotice(minutes: 5, reason: .timeLimit))))
    #expect(store.state.closingNotice != nil)
    await store.send(.menu(.delegate(.restartRequested))) {
        $0.session = .relaunching(firstSession)
        $0.closingNotice = nil
    }
    await store.receive(.relaunchClosed(firstSession))
    #expect(calls.started.value.count == 2)
    #expect(store.state.session.id == calls.started.value[1])
    #expect(store.state.session.stage?.cloudStep == .checking)
    #expect(store.state.source == source)
    await store.send(.stop)
    await store.skipReceivedActions()
}

@MainActor @Test func aCloudRestartIsIgnoredUntilTheGameIsPlaying() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .cloudStep(.connecting)))
    await store.send(.menu(.delegate(.restartRequested)))
    #expect(store.state.session.isStarting)
    #expect(calls.left.value.isEmpty)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func theStreamMenuAsksForARestartOnlyAfterSavingANewLaunchSetting() async {
    let saved = LockIsolated<[Int]>([])
    var state = StreamMenuReducer.State(context: .cloud("pscloud"))
    let loaded = StreamTuningConfiguration(nativeHeight: 1080, launchOptions: .cloud("pscloud"))
    state.configuration = loaded
    state.draft = loaded
    state.hasLoaded = true
    state.phase = .ready
    let store = TestStore(initialState: state) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.saveTuning = { _, configuration in
            saved.withValue {
                $0.append(configuration.launch.height)
            }
        }
    }
    store.exhaustivity = .off
    await store.send(.restartStream)
    #expect(saved.value.isEmpty)
    var raised = loaded
    raised.launch.height = 1440
    await store.send(.edit(raised))
    await store.send(.restartStream)
    await store.receive(\.saved)
    await store.receive(.delegate(.restartRequested))
    #expect(saved.value == [1440])
}
