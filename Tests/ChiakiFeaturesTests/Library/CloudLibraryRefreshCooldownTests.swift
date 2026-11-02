@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func emptyLibrary() throws -> CloudLibrarySnapshot {
    try CloudLibrarySnapshot.decode(JSONSerialization.data(withJSONObject: ["games": [Any]()]))
}

@MainActor private func refreshStore(
    account: UUID,
    cooldownMinutes: UInt32,
    clock: some Clock<Duration>,
    loads: LockIsolated<Int>,
    failing: Bool = false
) throws -> TestStoreOf<CloudLibraryFeature> {
    let snapshot = try emptyLibrary()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = .constant(now)
        $0.continuousClock = clock
        $0.settings = .inMemory([DeveloperSettings(libraryRefreshCooldownMinutes: cooldownMinutes)])
        $0.catalog.recentlyPlayed = { _ in
            []
        }
        $0.catalog.library = { _, _, _, _ in
            loads.withValue {
                $0 += 1
            }
            if failing {
                throw CloudLibraryFailure.network
            }
            return snapshot
        }
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func aLibraryRefreshBlocksTheNextOneForTheDeveloperCooldown() async throws {
    let account = UUID()
    let clock = TestClock()
    let loads = LockIsolated(0)
    let store = try refreshStore(account: account, cooldownMinutes: 15, clock: clock, loads: loads)
    await store.send(.refresh) {
        $0.libraryRefresh = .coolingDown(UUID(0), until: nil)
    }
    await store.receive(.libraryRefreshCooldownRead(UUID(0), .seconds(900))) {
        $0.libraryRefresh = .coolingDown(UUID(0), until: now.addingTimeInterval(900))
    }
    await store.receive(\.loaded)
    await store.send(.refresh)
    #expect(loads.value == 1)
    await clock.advance(by: .seconds(899))
    #expect(!store.state.libraryRefresh.isReady)
    await clock.advance(by: .seconds(1))
    await store.receive(.libraryRefreshCooled(UUID(0))) {
        $0.libraryRefresh = .ready
    }
    await store.send(.refresh)
    await store.receive(\.libraryRefreshCooldownRead)
    #expect(loads.value == 2)
    await store.send(.stop)
    await store.skipInFlightEffects()
}

@MainActor @Test func aLibraryRefreshWithTheCooldownOffLetsTheNextOneThrough() async throws {
    let loads = LockIsolated(0)
    let store = try refreshStore(account: UUID(), cooldownMinutes: 0, clock: ImmediateClock(), loads: loads)
    await store.send(.refresh)
    await store.receive(\.libraryRefreshCooldownRead) {
        $0.libraryRefresh = .ready
    }
    await store.receive(\.loaded)
    await store.send(.refresh)
    await store.receive(\.loaded)
    #expect(loads.value == 2)
}

@MainActor @Test func aFailedLibraryRefreshFreesTheButton() async throws {
    let account = UUID()
    let loads = LockIsolated(0)
    let store = try refreshStore(
        account: account, cooldownMinutes: 15, clock: TestClock(), loads: loads, failing: true
    )
    await store.send(.refresh)
    await store.receive(\.libraryRefreshCooldownRead)
    await store.receive(.failed(account, UUID(0), .network)) {
        $0.libraryRefresh = .ready
    }
    #expect(store.state.libraryRefresh.availableAt == nil)
}
