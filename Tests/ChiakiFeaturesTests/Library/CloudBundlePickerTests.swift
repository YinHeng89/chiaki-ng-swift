import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

private let firstID = "EP9000-PPSA00002_00-FIRSTGAME0000000"
private let secondID = "EP9000-PPSA00003_00-SECONDGAME000000"

private let first = CloudGame(
    productId: firstID, name: "First Game", imageUrl: "https://image.api.playstation.com/first.png",
    isOwned: true, visible: false, standing: .inLibrary, ownershipId: firstID
)

private let bundle = CloudGame(
    productId: "EP9000-PPSA00001_00-BUNDLE0000000000", name: "Double Pack",
    imageUrl: "https://image.api.playstation.com/bundle.png", launchRefusal: .chooseAGame,
    bundle: CloudBundle(isOwned: true, games: [
        CloudBundledGame(productId: firstID, entitlementId: firstID, isOwned: true),
        CloudBundledGame(
            productId: secondID, entitlementId: secondID, isOwned: false, launchRefusal: .addToLibrary
        )
    ])
)

private let single = CloudGame(
    productId: "EP9000-PPSA01234_00-ASTROBOT00000000", name: "Astro Bot", isOwned: true
)

@MainActor private func pickerStore(
    selecting game: CloudGame, events: [CloudLaunchClearanceEvent], asked: LockIsolated<[String]>
) -> TestStoreOf<CloudLibraryFeature> {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-US", games: [bundle, first, single])
    state.selection = game.id
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.clearForLaunch = { _, product in
            asked.withValue {
                $0.append(product.rawValue)
            }
            return AsyncStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    store.exhaustivity = .off
    return store
}

@MainActor private func settle(_ store: TestStoreOf<CloudLibraryFeature>) async {
    await store.finish()
    await store.skipReceivedActions(strict: false)
}

@Test func bundleChoicesNameEachGameFromItsListedRowAndKeepTheCoreVerdict() {
    let choices = bundle.bundleChoices(among: [bundle, first, single])
    #expect(choices.map(\.id) == [firstID, secondID])
    #expect(choices.map(\.game.name) == ["First Game", "Game 2"])
    #expect(choices.map(\.refusal) == [nil, .addToLibrary])
    #expect(choices.map(\.reason) == [
        nil, "Add this title to your library on PlayStation Store to stream it."
    ])
    #expect(choices.map(\.game.imageUrl) == [first.imageUrl, bundle.imageUrl])
    #expect(choices.allSatisfy { $0.game.streamServiceType == "pscloud" && $0.game.platform == "PS5" })
    #expect(single.bundleChoices(among: [bundle, first, single]).isEmpty)
}

@Test func onlyABundleTheCoreRefusesToLaunchItselfOpensThePicker() {
    #expect(bundle.opensBundlePicker)
    #expect(!single.opensBundlePicker)
    let hiddenBundle = CloudGame(
        productId: bundle.productId, name: bundle.name, launchRefusal: .hidden, bundle: bundle.bundle
    )
    #expect(!hiddenBundle.opensBundlePicker)
}

@MainActor @Test func playOnABundleOpensItsGamesWithoutCheckingTheBundle() async {
    let asked = LockIsolated<[String]>([])
    let store = pickerStore(selecting: bundle, events: [], asked: asked)
    await store.send(.openBundlePicker(bundle.id))
    #expect(store.state.bundlePicker == bundle.id)
    #expect(store.state.bundleChoices.map(\.id) == [firstID, secondID])
    #expect(store.state.launchChecks == nil)
    #expect(asked.value.isEmpty)
}

@MainActor @Test func aGameThatIsNotABundleOpensNoPicker() async {
    let store = pickerStore(selecting: single, events: [], asked: LockIsolated([]))
    await store.send(.openBundlePicker(single.id))
    #expect(store.state.bundlePicker == nil)
    await store.send(.openBundlePicker(bundle.id))
    #expect(store.state.bundlePicker == nil)
    #expect(store.state.bundleChoices.isEmpty)
}

@MainActor @Test func choosingAPlayableGameChecksThatGameOnTheBundleCard() async throws {
    let asked = LockIsolated<[String]>([])
    let events: [CloudLaunchClearanceEvent] = [
        .check(.loadingLibrary), .check(.cloudStreaming), .check(.entitlement), .check(.cloudGame),
        .check(.exclusions), .check(.release), .finished(.success(.cleared(nil)))
    ]
    let store = pickerStore(selecting: bundle, events: events, asked: asked)
    await store.send(.cardChecked(store.state.accountID!, bundle.id, .streams))
    await store.send(.openBundlePicker(bundle.id))
    await store.send(.playBundleGame(firstID))
    await store.receive(\.delegate.play)
    await settle(store)
    #expect(asked.value == [firstID])
    let checks = try #require(store.state.launchChecks)
    #expect(checks.gameID == bundle.id)
    #expect(checks.launchedID == firstID)
    #expect(checks.steps == [.premium, .yourCopy, .cloudGame, .restrictions, .release])
    #expect(checks.request.game.name == "First Game")
    #expect(checks.phase == .launched)
    #expect(store.state.bundlePicker == bundle.id)
}

@MainActor @Test func aGameTheCoreRefusesIsNotLaunchedFromThePicker() async {
    let asked = LockIsolated<[String]>([])
    let store = pickerStore(selecting: bundle, events: [], asked: asked)
    await store.send(.openBundlePicker(bundle.id))
    await store.send(.playBundleGame(secondID))
    await store.send(.playBundleGame(bundle.id))
    #expect(store.state.launchChecks == nil)
    #expect(asked.value.isEmpty)
}

@MainActor @Test func aGameIsOnlyLaunchedFromAnOpenPicker() async {
    let asked = LockIsolated<[String]>([])
    let store = pickerStore(selecting: bundle, events: [], asked: asked)
    await store.send(.playBundleGame(firstID))
    #expect(store.state.launchChecks == nil)
    #expect(asked.value.isEmpty)
}

@MainActor @Test func leavingThePickerStopsTheChecksStillRunning() async throws {
    let store = pickerStore(
        selecting: bundle, events: [.check(.loadingLibrary), .check(.cloudStreaming)], asked: LockIsolated([])
    )
    await store.send(.openBundlePicker(bundle.id))
    await store.send(.playBundleGame(firstID))
    await settle(store)
    let attempt = try #require(store.state.launchChecks?.attempt)
    #expect(store.state.launchChecks?.phase == .checking(.premium))
    await store.send(.closeTapped)
    #expect(store.state.bundlePicker == nil)
    #expect(store.state.launchChecks == nil)
    await store.send(.launchChecked(attempt, .finished(.success(.cleared(nil)))))
    #expect(store.state.launchChecks == nil)
}

@MainActor @Test func aRefusalForAChosenGameStaysWithThePicker() async throws {
    let refused = CloudClearanceRefusal(refusal: .purchaseNeeded)
    let store = pickerStore(
        selecting: bundle,
        events: [.check(.loadingLibrary), .check(.cloudStreaming), .finished(.success(.refused(refused)))],
        asked: LockIsolated([])
    )
    await store.send(.openBundlePicker(bundle.id))
    await store.send(.playBundleGame(firstID))
    await settle(store)
    let checks = try #require(store.state.launchChecks)
    #expect(checks.reason == CloudClearanceRefusalMessage.text(for: refused))
    #expect(checks.gameID == bundle.id)
    await store.send(.closeTapped)
    #expect(store.state.launchChecks == nil)
}

@MainActor @Test func closingTheDetailsClosesThePicker() async {
    let store = pickerStore(selecting: bundle, events: [], asked: LockIsolated([]))
    await store.send(.openBundlePicker(bundle.id))
    await store.send(.select(nil))
    #expect(store.state.bundlePicker == nil)
    #expect(store.state.selection == nil)
}
