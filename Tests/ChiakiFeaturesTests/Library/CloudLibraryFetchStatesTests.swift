@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

private func running(
    _ step: CloudLibraryFetchState.Step,
    _ activity: CloudLibraryFetchState.Activity? = nil,
    read: Int = 0,
    of expected: Int? = nil,
    attempt: UInt64 = 1
) -> CloudLibraryFetchState {
    CloudLibraryFetchState(
        attempt: attempt,
        step: step,
        activity: activity,
        pagesRead: read,
        pagesExpected: expected,
        isRunning: true
    )
}

private func scriptedLibrary(
    _ states: [CloudLibraryFetchState],
    ending failure: CloudLibraryFailure?,
    forces: LockIsolated<[Bool]>
) -> @Sendable (UUID, Bool, String, @escaping @Sendable (CloudLibraryFetchState) -> Void) async throws
    -> CloudLibrarySnapshot {
    { _, force, _, observe in
        forces.withValue {
            $0.append(force)
        }
        for state in states {
            observe(state)
        }
        if let failure {
            throw failure
        }
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
}

@MainActor private func loadingStore(
    account: UUID,
    states: [CloudLibraryFetchState],
    ending failure: CloudLibraryFailure? = nil,
    forces: LockIsolated<[Bool]> = LockIsolated([])
) -> TestStoreOf<CloudLibraryFeature> {
    var state = CloudLibraryFeature.State()
    state.accountID = account
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.continuousClock = TestClock()
        $0.catalog.library = scriptedLibrary(states, ending: failure, forces: forces)
    }
    store.exhaustivity = .off
    return store
}

@Test func everyRunningStepHasALineAndEndedStepsHaveNone() {
    let lines = CloudLibraryFetchState.Step.allCases.compactMap(CloudLibraryFetchProgress.line(of:))
        .map { String(localized: $0) }
    #expect(lines == [
        "Checking your sign-in",
        "Reading the cloud catalog",
        "Reading your games",
        "Reading the Game Catalog",
        "Reading cloud games for sale",
        "Checking cloud streaming access",
        "Putting your library together",
        "Checking the time",
        "Checking which games are unavailable"
    ])
    for step in [CloudLibraryFetchState.Step.idle, .ready, .unanswered, .cancelled] {
        #expect(CloudLibraryFetchProgress(CloudLibraryFetchState(attempt: 1, step: step, isRunning: false)) ==
            nil)
    }
}

@Test func everyActivityHasItsDetail() {
    let details = CloudLibraryFetchState.Activity.allCases.map {
        String(localized: CloudLibraryFetchProgress.detail(of: $0))
    }
    #expect(details == [
        "Using what was saved earlier",
        "PlayStation Store",
        "PS Now shelves",
        "PlayStation Store, as a fallback",
        "Checking which copies stream",
        "PS5 store lists",
        "Your entitlements",
        "Your PS4 games",
        "Your PS5 games",
        "Store pages",
        "Your subscriptions",
        "Matching titles",
        "Trusted time",
        "Exclusion list"
    ])
}

@Test func aClockSyncNamesTheTimeServerItAsks() throws {
    let cloudflare = try #require(CloudLibraryFetchProgress(running(
        .trustedTime,
        .syncingClock(host: "time.cloudflare.com")
    )))
    #expect([cloudflare.step, cloudflare.detail].map { $0.map { String(localized: $0) } } == [
        "Checking the time", "time.cloudflare.com"
    ])
    let google = try #require(CloudLibraryFetchProgress(running(
        .trustedTime,
        .syncingClock(host: "time2.google.com")
    )))
    #expect(google.detail.map { String(localized: $0) } == "time2.google.com")
    let unnamed = try #require(CloudLibraryFetchProgress(running(.trustedTime, .syncingClock(host: nil))))
    #expect(unnamed.detail.map { String(localized: $0) } == "Trusted time")
}

@Test func pagesShowTheirTotalOnlyWhenTheCoreKnowsIt() {
    #expect(
        CloudLibraryFetchProgress.pages(read: 3, expected: 7).map { String(localized: $0) } == "Page 3 of 7"
    )
    #expect(CloudLibraryFetchProgress.pages(read: 3, expected: nil).map { String(localized: $0) } == "Page 3")
    #expect(CloudLibraryFetchProgress.pages(read: 0, expected: 7) == nil)
    #expect(CloudLibraryFetchProgress.pages(read: 0, expected: nil) == nil)
}

@MainActor @Test func theCoreFetchStatesDriveTheLoadingText() async throws {
    let account = UUID()
    let states = [
        running(.checkingSignIn),
        running(.cloudList, .walkingPublicStore),
        running(.cloudList, .walkingPublicStore, read: 3, of: 7),
        running(.ownedLibrary, .readingEntitlements, read: 2),
        running(.matching, .matchingGames)
    ]
    let store = loadingStore(account: account, states: states)
    await store.send(.refresh)
    #expect(store.state.phase == .loading(UUID(0), fetch: nil))
    #expect(store.state.phase.fetchProgress == nil)
    let expected: [[String?]] = [
        ["Checking your sign-in", nil, nil],
        ["Reading the cloud catalog", "PlayStation Store", nil],
        ["Reading the cloud catalog", "PlayStation Store", "Page 3 of 7"],
        ["Reading your games", "Your entitlements", "Page 2"],
        ["Putting your library together", "Matching titles", nil]
    ]
    for (index, state) in states.enumerated() {
        await store.receive(.fetchState(account, UUID(0), state))
        #expect(store.state.phase == .loading(UUID(0), fetch: state))
        let progress = try #require(store.state.phase.fetchProgress)
        let words = [progress.step, progress.detail, progress.pages].map { $0.map { String(localized: $0) } }
        #expect(words == expected[index])
    }
    await store.send(.stop)
    await store.finish()
}

@MainActor @Test func aStateFromAnAbandonedFetchNeverReachesTheView() async throws {
    let account = UUID()
    let attempt = UUID()
    let stale = running(.ownedLibrary, .scanningPS5Library, read: 1, of: 2)
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .loading(attempt, fetch: nil)
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    }
    await store.send(.fetchState(account, UUID(), stale))
    await store.send(.fetchState(UUID(), attempt, stale))
    await store.send(.stop) {
        $0.phase = .idle
    }
    await store.send(.fetchState(account, attempt, stale))
}

@MainActor @Test func anUnansweredStateLandsInTheErrorViewWithItsWording() async throws {
    let account = UUID()
    let failure = CatalogFailure(reason: .user, httpStatus: 401, needsSignIn: true)
    let signedOut = CloudLibraryFetchState(attempt: 1, step: .unanswered, failure: failure, isRunning: false)
    let store = loadingStore(
        account: account,
        states: [running(.checkingSignIn), signedOut],
        ending: failure.libraryFailure
    )
    await store.send(.refresh)
    await store.receive(.failed(account, UUID(0), .signInRequired))
    await store.finish()
    await store.skipReceivedActions(strict: false)
    #expect(store.state.phase == .failed(.signInRequired))
    await store.send(.fetchState(account, UUID(0), running(.cloudList)))
    #expect(store.state.phase == .failed(.signInRequired))
    await store.finish()
}

@MainActor @Test func aRefreshFollowsTheRunningAttemptIntoItsFreshOne() async throws {
    let account = UUID()
    let forces = LockIsolated<[Bool]>([])
    let earlier = running(.ownedLibrary, .readingEntitlements, read: 2, attempt: 5)
    let earlierEnded = CloudLibraryFetchState(
        attempt: 5,
        step: .unanswered,
        failure: CatalogFailure(reason: .unavailable, httpStatus: 503),
        isRunning: false
    )
    let fresh = running(.checkingSignIn, attempt: 6)
    let freshList = running(.cloudList, .walkingPublicStore, read: 1, of: 4, attempt: 6)
    let store = loadingStore(
        account: account,
        states: [earlier, earlierEnded, fresh, freshList],
        forces: forces
    )
    await store.send(.refresh)
    await store.receive(.fetchState(account, UUID(0), earlier))
    #expect(store.state.phase.fetchProgress.map { String(localized: $0.step) } == "Reading your games")
    await store.receive(.fetchState(account, UUID(0), earlierEnded))
    #expect(store.state.phase == .loading(UUID(0), fetch: earlierEnded))
    await store.receive(.fetchState(account, UUID(0), fresh))
    #expect(store.state.phase.fetchProgress.map { String(localized: $0.step) } == "Checking your sign-in")
    await store.receive(.fetchState(account, UUID(0), freshList))
    let progress = try #require(store.state.phase.fetchProgress)
    #expect([progress.step, progress.detail, progress.pages].map { $0.map { String(localized: $0) } } == [
        "Reading the cloud catalog", "PlayStation Store", "Page 1 of 4"
    ])
    #expect(store.state.phase == .loading(UUID(0), fetch: freshList))
    #expect(forces.value == [true])
    await store.send(.stop)
    await store.finish()
}

@MainActor @Test func aJoinedFetchShowsTheRunningStateFirst() async throws {
    let account = UUID()
    let joined = CloudLibraryFetchState(
        attempt: 4,
        step: .ownedLibrary,
        activity: .scanningPS5Library,
        pagesRead: 4,
        pagesExpected: 9,
        passed: [
            .init(step: .checkingSignIn, outcome: .held),
            .init(step: .cloudList, outcome: .fetched)
        ],
        isRunning: true
    )
    let next = running(.premiumCategory, .readingCategoryPages, attempt: 4)
    let store = loadingStore(account: account, states: [joined, next])
    await store.send(.refresh)
    await store.receive(.fetchState(account, UUID(0), joined))
    let first = try #require(store.state.phase.fetchProgress)
    #expect(String(localized: first.step) == "Reading your games")
    #expect(first.detail.map { String(localized: $0) } == "Your PS5 games")
    #expect(first.pages.map { String(localized: $0) } == "Page 4 of 9")
    await store.receive(.fetchState(account, UUID(0), next))
    #expect(store.state.phase.fetchProgress.map { String(localized: $0.step) } == "Reading the Game Catalog")
    await store.send(.stop)
    await store.finish()
}
