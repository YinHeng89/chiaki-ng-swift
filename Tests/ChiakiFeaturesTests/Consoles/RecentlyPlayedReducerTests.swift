import ChiakiModels

@testable import ChiakiFeatures
import ComposableArchitecture
import Foundation
import Testing

private let profileA = UUID()
private let profileB = UUID()
private let consoleID = UUID()
private let hardware = Data(repeating: 0xab, count: 6)
private let title = RecentTitle(
    titleID: "PPSA01234_00", launchID: "PPSA01234", name: "Game",
    imageURL: "https://image.api.playstation.com/game.png", lastPlayedMs: 1_767_290_400_000, recent: true
)
private let rail = RecentlyPlayedRail(consoleID: consoleID, hardwareID: hardware, titles: [title])
private let emptyRail = RecentlyPlayedRail(
    consoleID: UUID(),
    hardwareID: Data(repeating: 1, count: 6),
    titles: []
)

private func launchRequest(_ account: UUID = profileA) -> TitleLaunch {
    TitleLaunch(accountID: account, consoleID: consoleID, hardwareID: hardware, title: title)
}

@MainActor @Test func oneFetchRunsPerProfileAndRefreshesWhileItRunsAreDropped() async {
    let clock = TestClock()
    let calls = LockIsolated(0)
    let store = TestStore(initialState: RecentlyPlayedReducer.State()) {
        RecentlyPlayedReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.recentlyPlayed = { _ in
            calls.withValue { $0 += 1 }
            try await clock.sleep(for: .seconds(1))
            return RecentlyPlayedFetch(rails: [rail, emptyRail])
        }
    }
    let selection = RecentlyPlayedReducer.Selection(profileID: profileA, eligible: true)
    await store.send(.select(selection)) {
        $0.selection = selection
        $0.phase = .fetching(UUID(0))
    }
    await store.receive(.trialsHeld(profileA, UUID(0), []))
    #expect(store.state.showsPlaceholders)
    await store.send(.refresh)
    await store.send(.select(selection))
    await clock.advance(by: .seconds(1))
    await store.receive(.fetched(profileA, UUID(0), RecentlyPlayedFetch(rails: [rail, emptyRail]))) {
        $0.phase = .loaded
        $0.rails = [rail]
    }
    #expect(calls.value == 1)
    #expect(store.state.rail(for: emptyRail.consoleID) == nil)
}

@MainActor @Test func theRailsMarkTheTrialsTheCoreHoldsForTheAccount() async {
    let trial = CloudGame(
        productId: "UP9000-PPSA01234_00-SAROS00000000000",
        name: "SAROS",
        isOwned: true,
        isTrial: true,
        isPlayFirstTrial: true
    )
    let store = TestStore(initialState: RecentlyPlayedReducer.State()) {
        RecentlyPlayedReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.recentlyPlayed = { _ in
            RecentlyPlayedFetch(rails: [rail])
        }
        $0.catalog.heldTrials = { account in
            account == profileA
                ? [trial]
                : []
        }
    }
    store.exhaustivity = .off
    await store.send(.select(.init(profileID: profileA, eligible: true)))
    await store.receive(.trialsHeld(profileA, UUID(0), [trial])) {
        $0.trialMarks = ["PPSA01234_00": CloudTrialMark(icon: .trial, label: "Trial")]
    }
    await store.send(.trialsHeld(profileB, UUID(0), [trial]))
    await store.send(.trialsHeld(profileA, UUID(7), []))
    #expect(store.state.trialMarks.count == 1)
    await store.send(.select(.init(profileID: profileB, eligible: true))) {
        $0.trialMarks = [:]
    }
    await store.receive(.trialsHeld(profileB, UUID(1), []))
    #expect(store.state.trialMarks.isEmpty)
    await store.finish()
}

@MainActor @Test func aStaleAnswerForAProfileNoLongerSelectedIsDropped() async {
    let clock = TestClock()
    let store = TestStore(initialState: RecentlyPlayedReducer.State()) {
        RecentlyPlayedReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.recentlyPlayed = { _ in
            try await clock.sleep(for: .seconds(1))
            return RecentlyPlayedFetch(rails: [rail])
        }
    }
    store.exhaustivity = .off
    await store.send(.select(.init(profileID: profileA, eligible: true)))
    await store.send(.select(.init(profileID: profileB, eligible: true))) {
        $0.phase = .fetching(UUID(1))
        $0.rails = []
    }
    await store.send(.fetched(profileA, UUID(0), RecentlyPlayedFetch(rails: [rail])))
    #expect(store.state.phase == .fetching(UUID(1)) && store.state.rails.isEmpty)
    await store.send(.fetched(profileB, UUID(0), RecentlyPlayedFetch(rails: [rail])))
    #expect(store.state.phase == .fetching(UUID(1)))
    await clock.advance(by: .seconds(1))
    await store.receive(.fetched(profileB, UUID(1), RecentlyPlayedFetch(rails: [rail]))) {
        $0.phase = .loaded
        $0.rails = [rail]
    }
    #expect(store.state.rail(for: consoleID) == rail)
}

@MainActor @Test func emptyRailsAreHiddenAndOnlyNonEmptyConsolesShow() async {
    var state = RecentlyPlayedReducer.State()
    state.selection = .init(profileID: profileA, eligible: true)
    state.phase = .loaded
    state.rails = []
    #expect(!state.showsPlaceholders && state.rail(for: consoleID) == nil)
    state.selection = .init(profileID: profileA, eligible: false)
    state.rails = [rail]
    #expect(state.rail(for: consoleID) == nil)
}

@MainActor @Test func failuresSettleIntoTheirDisplayStates() async {
    let store = TestStore(initialState: {
        var state = RecentlyPlayedReducer.State()
        state.selection = .init(profileID: profileA, eligible: true)
        state.phase = .fetching(UUID(9))
        state.rails = [rail]
        return state
    }()) {
        RecentlyPlayedReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.recentlyPlayed = { _ in
            try await Task.never()
        }
    }
    await store.send(.failed(profileA, UUID(9), .unavailable)) {
        $0.phase = .unavailable
    }
    #expect(store.state.rail(for: consoleID) == rail)
    store.exhaustivity = .off
    await store.send(.refresh)
    await store.send(.failed(profileA, UUID(0), .auth)) {
        $0.phase = .authExpired
        $0.rails = []
    }
    #expect(store.state.authExpired && store.state.rail(for: consoleID) == nil)
    await store.send(.refresh)
    await store.send(.failed(profileA, UUID(1), .signedOut)) {
        $0.phase = .signedOut
    }
    #expect(!store.state.visible && !store.state.authExpired)
    await store.skipInFlightEffects()
}

@MainActor @Test func aStreamEndingRefreshesNowAndFiveSecondsLaterWithOneQueuedFollowUp() async {
    let clock = TestClock()
    let calls = LockIsolated(0)
    let store = TestStore(initialState: {
        var state = RecentlyPlayedReducer.State()
        state.selection = .init(profileID: profileA, eligible: true)
        state.phase = .loaded
        return state
    }()) {
        RecentlyPlayedReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.consoles.recentlyPlayed = { _ in
            calls.withValue { $0 += 1 }
            try await clock.sleep(for: .seconds(2))
            return RecentlyPlayedFetch(rails: [rail])
        }
    }
    store.exhaustivity = .off
    await store.send(.streamEnded) {
        $0.phase = .fetching(UUID(0))
    }
    await store.send(.streamEnded) {
        $0.followUpQueued = true
    }
    await clock.advance(by: .seconds(2))
    await store.receive(.fetched(profileA, UUID(0), RecentlyPlayedFetch(rails: [rail]))) {
        $0.phase = .fetching(UUID(1))
        $0.followUpQueued = false
    }
    await clock.advance(by: .seconds(2))
    await store.receive(.fetched(profileA, UUID(1), RecentlyPlayedFetch(rails: [rail])))
    await clock.advance(by: .seconds(1))
    await store.receive(.followUpElapsed)
    await clock.advance(by: .seconds(2))
    await store.receive(.fetched(profileA, UUID(2), RecentlyPlayedFetch(rails: [rail])))
    await clock.advance(by: .seconds(10))
    #expect(calls.value == 3)
    #expect(store.state.phase == .loaded)
}
