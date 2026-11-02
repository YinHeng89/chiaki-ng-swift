import Foundation
import Testing
import ChiakiModels
import ComposableArchitecture
@testable import ChiakiFeatures

@MainActor @Test func cloudStatusKeepsStaleCacheOnFailureAndIgnoresOldAccountCompletion() async {
    let old = CloudAccountScope(accountID: UUID(), locale: "en-GB")
    let current = CloudAccountScope(accountID: UUID(), locale: "en-GB")
    let attempt = UUID(), now = Date(timeIntervalSince1970: 2000)
    let snapshot = CloudStatusSnapshot(
        scope: current, catalog: .init(gameCount: 3, nativeCatalog: true, isPlus: true),
        checkedAt: now.addingTimeInterval(-1000), expiresAt: now.addingTimeInterval(-100)
    )
    let store = TestStore(initialState: CloudStatusFeature.State()) {
        CloudStatusFeature()
    } withDependencies: {
        $0.uuid = .constant(attempt)
        $0.date.now = now
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.plusTier = { _ in
            .premium
        }
        $0.cloud.cachedStatus = { _ in snapshot
        }
        $0.cloud.refreshStatus = { _ in throw CloudStatusFailure.network
        }
    }
    await store.send(.select(current.accountID)) {
        $0.scope = current
        $0.phase = .loading(attempt)
        $0.tierAttempt = attempt
    }
    await store.receive(.plusTierLoaded(attempt, .premium)) {
        $0.plusTier = .premium
        $0.tierAttempt = nil
    }
    await store.receive(.cached(attempt, snapshot)) {
        $0.snapshot = snapshot
        $0.phase = .ready
    }
    await store.receive(.refresh) {
        $0.phase = .refreshing(attempt)
        $0.lastAttempt = now
    }
    await store.receive(.failed(attempt, .network)) {
        $0.phase = .failed(.network)
    }
    let late = CloudStatusSnapshot(
        scope: old, catalog: snapshot.catalog, checkedAt: now,
        expiresAt: now.addingTimeInterval(900)
    )
    await store.send(.refreshed(UUID(), late))
    await store.send(.stop) {
        $0 = CloudStatusFeature.State()
    }
    await store.send(.refreshed(attempt, snapshot))
}

@MainActor @Test func cloudMonitorBacksOffFailuresAndStopsWithItsView() async {
    let scope = CloudAccountScope(accountID: UUID(), locale: "en-GB")
    let attempt = UUID(), now = Date(timeIntervalSince1970: 2000)
    let clock = TestClock()
    var state = CloudStatusFeature.State()
    state.scope = scope
    state.phase = .failed(.network)
    state.lastAttempt = now
    let store = TestStore(initialState: state) {
        CloudStatusFeature()
    } withDependencies: {
        $0.uuid = .constant(attempt)
        $0.date.now = now
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.plusTier = { _ in
            .premium
        }
        $0.continuousClock = clock
        $0.cloud.refreshStatus = { _ in throw CloudStatusFailure.network
        }
    }
    await store.send(.select(scope.accountID))
    await store.send(.watch)
    await clock.advance(by: .seconds(60))
    await store.receive(.tick)
    store.dependencies.date.now = now.addingTimeInterval(301)
    await clock.advance(by: .seconds(60))
    await store.receive(.tick)
    await store.receive(.refresh) {
        $0.phase = .refreshing(attempt)
        $0.lastAttempt = now.addingTimeInterval(301)
    }
    await store.receive(.failed(attempt, .network)) {
        $0.phase = .failed(.network)
    }
    await store.send(.stop) {
        $0 = .init()
    }
    await store.finish()
}

@Test func cloudIsUnavailableOnlyWhenTheStreamServiceRulesItOutForTheSelectedAccount() {
    let scope = CloudAccountScope(accountID: UUID(), locale: "en-GB")
    var state = CloudStatusFeature.State()
    state.scope = scope
    #expect(!state.unavailable(for: scope.accountID))
    state.phase = .failed(.network)
    #expect(!state.unavailable(for: scope.accountID))
    state.phase = .failed(.regionUnsupported)
    #expect(state.unavailable(for: scope.accountID))
    #expect(!state.unavailable(for: UUID()))
    #expect(!state.unavailable(for: nil))
}
