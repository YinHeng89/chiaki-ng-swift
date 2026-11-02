import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let session = StreamSessionID(uuid: UUID(42))

@MainActor private func homeRequestStore(_ clock: TestClock<Duration>) -> TestStoreOf<StreamFeature> {
    var state = StreamFeature.State()
    state.session = .playing(session)
    state.source = StreamFeature.source(
        account: UUID(),
        console: RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5),
        route: .local
    )
    let store = TestStore(initialState: state) {
        StreamFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.streamSession.goHome = { _ in
            true
        }
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func goingHomeFromAHiddenScreenWaitsUntilTheConsoleShowsItsPicture() async {
    let store = homeRequestStore(TestClock())
    await store.send(.event(session, .displayProhibited(true)))
    await store.send(.view(.goHome))
    await store.skipReceivedActions()
    guard case .waiting = store.state.homeRequest else {
        Issue.record("The request did not wait for the console")
        return
    }
    await store.send(.event(session, .displayProhibited(false)))
    #expect(store.state.homeRequest == .idle)
}

@MainActor @Test func goingHomeGivesUpWaitingAfterItsPatience() async {
    let clock = TestClock()
    let store = homeRequestStore(clock)
    await store.send(.event(session, .displayProhibited(true)))
    await store.send(.view(.goHome))
    await store.skipReceivedActions()
    await clock.advance(by: StreamFeature.homeRequestPatience)
    await store.skipReceivedActions()
    #expect(store.state.homeRequest == .idle)
    #expect(store.state.displayProhibited)
}

@MainActor @Test func goingHomeWithThePictureShownDoesNotWait() async {
    let store = homeRequestStore(TestClock())
    await store.send(.view(.goHome))
    await store.skipReceivedActions()
    #expect(store.state.homeRequest == .idle)
}
