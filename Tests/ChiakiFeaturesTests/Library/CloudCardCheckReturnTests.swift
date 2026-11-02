import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let checked = CloudGame(
    productId: "EP9000-PPSA09999_00-STOREPAGECHECK00",
    name: "Store Checked",
    isOwned: true,
    needsStorefrontCheck: true
)

@MainActor private func libraryStore(
    card: CloudCardCheck?, asked: LockIsolated<Int>
) -> TestStoreOf<CloudLibraryFeature> {
    let account = UUID()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-US", games: [checked])
    state.selection = checked.id
    state.cardChecks[checked.id] = card
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.storefrontCheck = { _, _ in
            asked.withValue { $0 += 1 }
            return CloudStoreCheck(card: .streams)
        }
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func aSettledStorePageCheckSurvivesTheLibraryStoppingForAStream() async {
    let asked = LockIsolated(0)
    let store = libraryStore(card: .streams, asked: asked)
    await store.send(.stop)
    #expect(store.state.cardChecks[checked.id] == .streams)
    await store.send(.account(store.state.accountID))
    await store.finish()
    await store.skipReceivedActions(strict: false)
    #expect(store.state.cardChecks[checked.id] == .streams)
    #expect(asked.value == 0)
}

@MainActor @Test func aStorePageCheckCutShortByAStreamRunsAgainWhenTheLibraryReturns() async {
    let asked = LockIsolated(0)
    let store = libraryStore(card: .checking, asked: asked)
    await store.send(.stop)
    #expect(store.state.cardChecks[checked.id] == nil)
    await store.send(.account(store.state.accountID))
    await store.finish()
    await store.skipReceivedActions(strict: false)
    #expect(store.state.cardChecks[checked.id] == .streams)
    #expect(asked.value == 1)
}
