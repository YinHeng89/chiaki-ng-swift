import ChiakiDiagnostics
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

@MainActor @Test func liveLogPausesClosesAndRejectsStaleSnapshots() async {
    let id = UUID(), clock = TestClock()
    let snapshot = LiveLogSnapshot(entries: [.init(id: 1, line: "Safe test event")])
    let store = TestStore(initialState: LiveLogReducer.State()) { LiveLogReducer() } withDependencies: {
        $0.uuid = .constant(id)
        $0.continuousClock = clock
        $0.liveLog.snapshot = { snapshot }
    }
    await store.send(.toggle) { $0.phase = .live(id) }
    await store.receive(.updated(id, snapshot)) { $0.snapshot = snapshot }
    await clock.advance(by: .milliseconds(500))
    await store.receive(.updated(id, snapshot))
    await store.send(.pauseResume) { $0.phase = .paused }
    await store.send(.updated(id, .init()))
    await store.send(.pauseResume) { $0.phase = .live(id) }
    await store.receive(.updated(id, snapshot))
    await store.send(.close) { $0.phase = .hidden }
    await store.send(.updated(id, .init()))
    await store.finish()
}
