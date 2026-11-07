@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private let addable = "UP9000-PPSA09020_00-PLUSPICK00000000"
private let owned = "UP9000-PPSA09006_00-FULLGAME00000000"
private let browse = "UP9000-PPSA09030_00-STANDARD00000000"
private let refreshedAt = Date(timeIntervalSince1970: 1_800_000_000)
private let cooledAt = refreshedAt.addingTimeInterval(20)

private func row(_ id: String, name: String, isOwned: Bool, plus: Bool) -> [String: Any] {
    [
        "productId": id, "name": name, "platform": "ps5",
        "category": isOwned
            ? "owned"
            : "purchaseable",
        "isOwned": isOwned, "plusCatalog": plus, "streamServiceType": "pscloud", "streamIdentifier": id,
        "conceptUrl": "https://store.playstation.com/concept/1", "entitlementId": id
    ]
}

private func librarySnapshot() throws -> CloudLibrarySnapshot {
    try CloudLibrarySnapshot.decode(JSONSerialization.data(withJSONObject: [
        "games": [
            row(owned, name: "Owned", isOwned: true, plus: false),
            row(addable, name: "Plus pick", isOwned: false, plus: true),
            row(browse, name: "Store only", isOwned: false, plus: false)
        ]
    ]))
}

private func ownedPlusPick() -> CloudGame {
    CloudGame(fixture: row(addable, name: "Plus pick", isOwned: true, plus: true))
}

private func readyState(_ account: UUID) throws -> CloudLibraryFeature.State {
    let snapshot = try librarySnapshot()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    state.snapshot = snapshot
    state.selection = addable
    state.storeOpened = [addable]
    return state
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(UUID, String)] = []
    func record(_ account: UUID, _ game: CloudGame) {
        lock.withLock {
            requests.append((account, game.id))
        }
    }
    var count: Int {
        lock.withLock {
            requests.count
        }
    }
    var products: [String] {
        lock.withLock {
            requests.map(\.1)
        }
    }
}

private func expectOnlyTitleChanged(_ state: CloudLibraryFeature.State,
                                    from initial: CloudLibraryFeature.State) throws {
    let after = try #require(state.selectedGame)
    #expect(!after.needsLibraryAdd)
    #expect(String(localized: after.standing.label) == "In your library")
    #expect(state.matchingGames(in: .owned).map(\.id).contains(addable))
    for id in [owned, browse] {
        #expect(state.listedGames.first { $0.id == id } == initial.listedGames.first { $0.id == id })
    }
    #expect(state.snapshot?.games.map(\.id) == initial.snapshot?.games.map(\.id))
}

@MainActor @Test func titleRefreshOwnedUpdatesOnlyThatTitle() async throws {
    let account = UUID()
    let attempt = UUID(0)
    let clock = TestClock()
    let calls = Calls()
    let game = ownedPlusPick()
    let updated = game
    let initial = try readyState(account)
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.catalog.refreshTitle = { account, game in
            calls.record(account, game)
            return .owned(updated)
        }
    }
    #expect(store.state.selectedGame?.canBeAddedToLibrary == true)
    #expect(!store.state.matchingGames(in: .owned).contains { $0.id == addable })

    await store.send(.refreshTitle(addable)) {
        $0.titleRefresh = .checking(addable, attempt)
    }
    await store.receive(.titleRefreshed(account, attempt, .owned(game))) {
        $0.snapshot = initial.snapshot!.replacing(game)
        $0.titleRefresh = .coolingDown(attempt, until: cooledAt)
        $0.titleNotice[addable] = .added
    }
    #expect(calls.products == [addable])
    try expectOnlyTitleChanged(store.state, from: initial)
    #expect(
        store.state.titleNotice[addable].map { String(localized: $0.message) }
            == "Added. You can play it now."
    )

    await clock.advance(by: CloudLibraryFeature.titleRefreshCooldown)
    await store.receive(.titleRefreshCooled(attempt)) {
        $0.titleRefresh = .idle
        $0.titleNotice = [:]
    }
}

@MainActor @Test func titleRefreshNotOwnedLeavesTheLibraryAlone() async throws {
    let account = UUID()
    let attempt = UUID(0)
    let clock = TestClock()
    let initial = try readyState(account)
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.catalog.refreshTitle = { _, _ in
            .notOwned
        }
    }
    await store.send(.refreshTitle(addable)) {
        $0.titleRefresh = .checking(addable, attempt)
    }
    await store.receive(.titleRefreshed(account, attempt, .notOwned)) {
        $0.titleRefresh = .coolingDown(attempt, until: cooledAt)
        $0.titleNotice[addable] = .notInLibrary
    }
    #expect(store.state.titleNotice[addable].map { String(localized: $0.message) }
        == "Not in your library yet. Add it on the PS Store, then refresh again.")
    #expect(store.state.selectedGame?.needsLibraryAdd == true)
    await clock.advance(by: CloudLibraryFeature.titleRefreshCooldown)
    await store.receive(.titleRefreshCooled(attempt)) {
        $0.titleRefresh = .idle
    }
    #expect(store.state.titleNotice[addable] == .notInLibrary)
}

@MainActor @Test func titleRefreshFailureShowsTheDecodedError() async throws {
    let account = UUID()
    let attempt = UUID(0)
    let clock = TestClock()
    let failure = CloudTitleRefreshFailure.signInRefused
    #expect(String(localized: failure.message)
        == "PlayStation refused the ownership check. Sign in again in Accounts.")
    let message = failure.message
    let outcome = CloudTitleRefreshOutcome.failed(failure)
    let initial = try readyState(account)
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.catalog.refreshTitle = { _, _ in
            outcome
        }
    }
    await store.send(.refreshTitle(addable)) {
        $0.titleRefresh = .checking(addable, attempt)
    }
    await store.receive(.titleRefreshed(account, attempt, outcome)) {
        $0.titleRefresh = .coolingDown(attempt, until: cooledAt)
        $0.titleNotice[addable] = .failed(message)
    }
    await clock.advance(by: CloudLibraryFeature.titleRefreshCooldown)
    await store.receive(.titleRefreshCooled(attempt)) {
        $0.titleRefresh = .idle
    }
    #expect(store.state.titleNotice[addable] == .failed(message))
}

@MainActor @Test func titleRefreshIsRateLimitedForTwentySeconds() async throws {
    let account = UUID()
    let clock = TestClock()
    let calls = Calls()
    let initial = try readyState(account)
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.catalog.refreshTitle = { account, game in
            calls.record(account, game)
            return .notOwned
        }
    }
    await store.send(.refreshTitle(addable)) {
        $0.titleRefresh = .checking(addable, UUID(0))
    }
    await store.receive(.titleRefreshed(account, UUID(0), .notOwned)) {
        $0.titleRefresh = .coolingDown(UUID(0), until: cooledAt)
        $0.titleNotice[addable] = .notInLibrary
    }
    await store.send(.refreshTitle(addable))
    await clock.advance(by: .seconds(19))
    await store.send(.refreshTitle(addable))
    #expect(calls.count == 1)
    await store.send(.titleRefreshCooled(UUID(7)))
    await clock.advance(by: .seconds(1))
    await store.receive(.titleRefreshCooled(UUID(0))) {
        $0.titleRefresh = .idle
    }
    await store.send(.refreshTitle(addable)) {
        $0.titleRefresh = .checking(addable, UUID(1))
        $0.titleNotice[addable] = nil
    }
    await store.receive(.titleRefreshed(account, UUID(1), .notOwned)) {
        $0.titleRefresh = .coolingDown(UUID(1), until: cooledAt)
        $0.titleNotice[addable] = .notInLibrary
    }
    #expect(calls.count == 2)
    await store.send(.titleRefreshed(account, UUID(0), .notOwned))
    await store.send(.refreshTitle(browse))
    await clock.advance(by: CloudLibraryFeature.titleRefreshCooldown)
    await store.receive(.titleRefreshCooled(UUID(1))) {
        $0.titleRefresh = .idle
    }
    await store.send(.refreshTitle(browse))
    #expect(calls.count == 2)
}

@MainActor @Test(.enabled(if: CloudGameActions.showsStoreCode))
func refreshDoesNotWaitForAddToLibraryWhereTheStoreCodeIsShown() async throws {
    let account = UUID()
    let calls = Calls()
    var initial = try readyState(account)
    initial.storeOpened = []
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.catalog.refreshTitle = { account, game in
            calls.record(account, game)
            return .owned(game)
        }
    }
    store.exhaustivity = .off
    #expect(store.state.actions(for: try #require(store.state.selectedGame)).focusOrder
        .contains(.refreshTitle))
    await store.send(.refreshTitle(addable)) {
        $0.titleRefresh = .checking(addable, UUID(0))
    }
    await store.skipReceivedActions()
    #expect(calls.products == [addable])
}

@MainActor @Test(.enabled(if: !CloudGameActions.showsStoreCode))
func refreshWaitsUntilAddToLibraryHasBeenOpened() async throws {
    let account = UUID()
    var initial = try readyState(account)
    initial.storeOpened = []
    let opened = LockIsolated<[URL]>([])
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.continuousClock = ImmediateClock()
        $0.openURL = OpenURLEffect { url in
            opened.withValue {
                $0.append(url)
            }
            return true
        }
    }
    await store.send(.refreshTitle(addable))
    await store.send(.addToLibraryTapped(addable)) {
        $0.storeOpened = [addable]
        $0.storeOpening = [addable]
    }
    await store.receive(.storePageOpened(store.state.accountID, addable)) {
        $0.storeOpening = []
    }
    await store.finish()
    #expect(opened.value == [URL(string: "https://store.playstation.com/concept/1")])
}

@MainActor @Test func aStoreButtonIgnoresPressesUntilItsPageOpensAndStopsWaitingForTheLookup() async throws {
    let account = UUID()
    let clock = TestClock()
    let opened = LockIsolated<[URL]>([])
    let initial = try readyState(account)
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.date = .constant(refreshedAt)
        $0.continuousClock = clock
        $0.catalog.storePage = { _, _ in
            try? await Task.sleep(for: .seconds(3600))
            return URL(string: "https://store.playstation.com/product/late")
        }
        $0.openURL = OpenURLEffect { url in
            opened.withValue {
                $0.append(url)
            }
            return true
        }
    }
    await store.send(.storePageTapped(addable)) {
        $0.storeOpening = [addable]
    }
    await store.send(.storePageTapped(addable))
    await clock.advance(by: CloudLibraryFeature.storePageWait)
    await store.receive(.storePageOpened(store.state.accountID, addable)) {
        $0.storeOpening = []
    }
    await store.finish()
    #expect(opened.value == [URL(string: "https://store.playstation.com/concept/1")])
}

private extension CloudLibraryFeature.State {
    func matchingGames(in filter: CloudLibraryFilter) -> [CloudGame] {
        var copy = self
        copy.filter = filter
        return copy.matchingGames
    }
}

@MainActor @Test func aStorePageOpenedForAnotherAccountLeavesTheButtonWaiting() async throws {
    let account = UUID()
    var initial = try readyState(account)
    initial.storeOpening = [addable]
    let store = TestStore(initialState: initial) {
        CloudLibraryFeature()
    }
    await store.send(.storePageOpened(UUID(), addable))
    await store.send(.storePageOpened(account, addable)) {
        $0.storeOpening = []
    }
}
