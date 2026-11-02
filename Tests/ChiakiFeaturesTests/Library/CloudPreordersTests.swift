@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let launchDay = Date(timeIntervalSince1970: 1_800_000_000)

private func preorderCatalog(unlockingIn seconds: TimeInterval = 3600,
                             sample: Bool = false) -> CloudLibrarySnapshot {
    CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: "owned", name: "Owned", isOwned: true, standing: .inLibrary),
        CloudGame(productId: "sale", name: "For sale", standing: .store),
        CloudGame(
            productId: sample
                ? "UP9000-PPSA99001_00-SAMPLEPREORDER01"
                : "soon",
            name: "Soon",
            isOwned: true,
            standing: .inLibrary,
            release: .scheduled(launchDay.addingTimeInterval(seconds))
        ),
        CloudGame(
            productId: "someday",
            name: "Someday",
            isOwned: true,
            standing: .inLibrary,
            release: .unannounced
        )
    ])
}

@Test func unreleasedGamesAreListedOnlyUnderPreorders() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = preorderCatalog()
    #expect(listing.hasPreorders)
    #expect(listing.nextUnlock == launchDay.addingTimeInterval(3600))
    for filter in [CloudLibraryFilter.all, .owned, .plus, .browse] {
        listing.filter = filter
        #expect(!listing.matching.contains { $0.id == "soon" || $0.id == "someday" })
    }
    listing.filter = .browse
    #expect(listing.matching.map(\.id) == ["sale"])
    listing.filter = .preorders
    #expect(listing.matching.map(\.id) == ["soon", "someday"])
    listing.query = "Soon"
    listing.filter = .all
    #expect(listing.matching.map(\.id) == ["soon"])
}

@Test func aPassedReleaseLeavesPreordersForItsOwnTab() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = preorderCatalog()
    listing.filter = .owned
    #expect(listing.matching.map(\.id) == ["owned"])
    listing.now = launchDay.addingTimeInterval(3601)
    #expect(listing.matching.map(\.id) == ["owned", "soon"])
    #expect(listing.nextUnlock == nil)
    listing.filter = .preorders
    #expect(listing.matching.map(\.id) == ["someday"])
}

@Test func thePreordersTabIsShownOnlyWhileAGameAwaitsRelease() {
    var state = CloudLibraryFeature.State()
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: "owned", name: "Owned", isOwned: true, standing: .inLibrary)
    ])
    #expect(state.filters == [.all, .owned, .plus, .browse])
    state.snapshot = preorderCatalog()
    #expect(state.filters == [.all, .owned, .plus, .browse, .preorders])
}

@MainActor @Test func theLibraryReloadsWhenAPreorderUnlocks() async {
    let clock = TestClock()
    let loads = LockIsolated(0)
    let account = UUID()
    let now = LockIsolated(launchDay)
    let store = TestStore(initialState: CloudLibraryFeature.State()) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = DateGenerator {
            now.value
        }
        $0.continuousClock = clock
        $0.catalog.recentlyPlayed = { _ in
            []
        }
        $0.catalog.library = { _, _, _, _ in
            loads.withValue {
                $0 += 1
            }
            return preorderCatalog(unlockingIn: 60)
        }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.account(account))
    await store.receive(\.loaded)
    #expect(store.state.filters.contains(.preorders))
    await store.send(.filter(.preorders))
    await clock.advance(by: .seconds(60))
    #expect(loads.value == 1)
    now.setValue(launchDay.addingTimeInterval(65))
    await clock.advance(by: CloudLibraryFeature.unlockMargin)
    await store.receive(\.releaseDue)
    await store.receive(\.loaded)
    #expect(loads.value == 2)
    await store.send(.stop)
    await store.finish()
}

@MainActor @Test func aSamplePreorderUnlockingMovesItWithoutReloading() async {
    let clock = TestClock()
    let loads = LockIsolated(0)
    let now = LockIsolated(launchDay)
    let store = TestStore(initialState: CloudLibraryFeature.State()) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = DateGenerator {
            now.value
        }
        $0.continuousClock = clock
        $0.catalog.recentlyPlayed = { _ in
            []
        }
        $0.catalog.library = { _, _, _, _ in
            loads.withValue {
                $0 += 1
            }
            return CloudLibrarySnapshot(
                settledLocale: "en-GB",
                games: Array(preorderCatalog(unlockingIn: 60, sample: true).games.prefix(3))
            )
        }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.account(UUID()))
    await store.receive(\.loaded)
    await store.send(.filter(.preorders))
    now.setValue(launchDay.addingTimeInterval(65))
    await clock.advance(by: .seconds(65))
    await store.receive(\.releaseDue)
    #expect(loads.value == 1)
    #expect(store.state.filter == .all)
    #expect(!store.state.filters.contains(.preorders))
    #expect(store.state.matchingGames.map(\.id).contains("UP9000-PPSA99001_00-SAMPLEPREORDER01"))
    await store.send(.stop)
    await store.finish()
}

@MainActor @Test func aReleaseThatPassedWhileTheLibraryWasAwayReloadsOnReturn() async {
    let clock = TestClock()
    let loads = LockIsolated(0)
    let account = UUID()
    let now = LockIsolated(launchDay)
    let store = TestStore(initialState: CloudLibraryFeature.State()) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = DateGenerator {
            now.value
        }
        $0.continuousClock = clock
        $0.catalog.recentlyPlayed = { _ in
            []
        }
        $0.catalog.library = { _, _, _, _ in
            loads.withValue {
                $0 += 1
            }
            return preorderCatalog(unlockingIn: 60)
        }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.account(account))
    await store.receive(\.loaded)
    await store.send(.stop)
    now.setValue(launchDay.addingTimeInterval(600))
    await clock.advance(by: .seconds(600))
    #expect(loads.value == 1)
    await store.send(.account(account))
    await store.receive(\.loaded)
    #expect(loads.value == 2)
    #expect(store.state.listing.now == launchDay.addingTimeInterval(600))
    await store.send(.stop)
    await store.finish()
}
