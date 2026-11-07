@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let launchDay = Date(timeIntervalSince1970: 1_800_000_000)

@Test func storeGamesOfferingATrialVersionStayUnderAvailableToBuy() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: "sale", name: "For sale", standing: .store),
        CloudGame(productId: "demo-offer", name: "Demo offer", standing: .store, trialOffer: .demo),
        CloudGame(
            productId: "trial-offer",
            name: "Trial offer",
            standing: .store,
            trialOffer: .playFirstTrial
        ),
        CloudGame(productId: "owned", name: "Owned", isOwned: true, standing: .inLibrary)
    ])
    listing.filter = .browse
    #expect(listing.matching.map(\.id) == ["sale", "demo-offer", "trial-offer"])
    listing.filter = .all
    #expect(listing.matching.map(\.id) == ["owned"])
}

@Test func aTrialOfferIsLabelledOnTheStoreCardOnly() {
    let trialOffer = CloudGame(
        productId: "trial-offer",
        name: "Trial offer",
        standing: .store,
        trialOffer: .playFirstTrial
    )
    #expect(trialOffer.trialOfferLabel.map { String(localized: $0) } == "Trial available")
    #expect(trialOffer.trialOfferIcon == .trial)
    #expect(trialOffer.trialLabel == nil)
    #expect(trialOffer.standingLabel(after: nil) == CloudStanding.store.label)
    #expect(trialOffer.entitlementIcon == .store)
    let demoOffer = CloudGame(
        productId: "demo-offer",
        name: "Demo offer",
        standing: .store,
        trialOffer: .demo
    )
    #expect(demoOffer.trialOfferLabel.map { String(localized: $0) } == "Demo available")
    #expect(demoOffer.trialOfferIcon == .demo)
    let sale = CloudGame(productId: "sale", name: "For sale", standing: .store)
    #expect(sale.trialOfferLabel == nil)
    #expect(sale.trialOfferIcon == nil)
}

@Test func aStoreGameOfferingATrialOffersItsStorePageAndNoPlayableStream() {
    let game = CloudGame(
        productId: "trial-offer",
        name: "Trial offer",
        conceptUrl: "https://store.playstation.com/en-gb/concept/1",
        standing: .store,
        needsStorefrontCheck: true,
        trialOffer: .playFirstTrial
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(actions.play?.allowed != true)
    #expect(actions.store.map { String(localized: $0.title) } == "View in Store")
    #expect(actions.addToLibrary == nil)
}

private let usedTrial = CloudGame(
    productId: "EP7579-PPSA17599_00-EXP33000000PS5EU",
    name: "Clair Obscur: Expedition 33",
    standing: .store,
    needsStorefrontCheck: true,
    trialOffer: .playFirstTrial
)

private let storeDemo = CloudGame(
    productId: "EP0001-PPSA70001_00-DEMOGAME00000000",
    name: "Demo game",
    standing: .store,
    needsStorefrontCheck: true,
    trialOffer: .demo
)

@Test func aTrialTheStoreNoLongerOffersLosesItsLabelUntilTheStoreOffersItAgain() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [usedTrial, storeDemo])
    listing.trialsWithdrawn = [usedTrial.id, storeDemo.id]
    #expect(listing.listed.first { $0.id == usedTrial.id }?.trialOfferLabel == nil)
    #expect(
        listing.listed.first { $0.id == storeDemo.id }?.trialOfferLabel.map { String(localized: $0) }
            == "Demo available"
    )
    listing.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [usedTrial, storeDemo])
    #expect(listing.listed.first { $0.id == usedTrial.id }?.trialOfferLabel == nil)
    listing.trialsWithdrawn = []
    #expect(
        listing.listed.first { $0.id == usedTrial.id }?.trialOfferLabel.map { String(localized: $0) }
            == "Trial available"
    )
}

@MainActor @Test func openingAStoreGameWithdrawsATrialTheStoreNoLongerOffers() async {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.listing.now = launchDay
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [usedTrial, storeDemo])
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.storefrontCheck = { _, _ in
            CloudStoreCheck(card: .streams, offersTrial: false)
        }
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    store.exhaustivity = .off
    await store.send(.select(usedTrial.id))
    await store.receive(.trialChecked(state.accountID!, usedTrial.id, false))
    #expect(store.state.listing.trialsWithdrawn == [usedTrial.id])
    #expect(store.state.listing.listed.first { $0.id == usedTrial.id }?.trialOfferLabel == nil)
    await store.send(.trialChecked(UUID(), storeDemo.id, false))
    #expect(store.state.listing.trialsWithdrawn == [usedTrial.id])
    await store.send(.trialChecked(state.accountID!, usedTrial.id, true))
    #expect(store.state.listing.trialsWithdrawn.isEmpty)
    await store.send(.trialChecked(state.accountID!, usedTrial.id, false))
    await store.send(.stop)
    #expect(store.state.listing.trialsWithdrawn == [usedTrial.id])
    #expect(store.state.listing.listed.first { $0.id == usedTrial.id }?.trialOfferLabel == nil)
    await store.finish()
}

@Test func aTileSaysItsTrialStateAloud() {
    let offer = CloudGame(
        productId: "trial-offer",
        name: "Hail",
        standing: .store,
        trialOffer: .playFirstTrial
    )
    #expect(String(localized: offer.spokenTileLabel(after: nil)).hasSuffix(", trial available"))
    let held = CloudGame(
        productId: "demo",
        name: "Demo game",
        isOwned: true,
        standing: .inLibrary,
        isTrial: true
    )
    #expect(String(localized: held.spokenTileLabel(after: nil)).hasSuffix(", demo"))
    let plain = CloudGame(productId: "plain", name: "Plain", isOwned: true, standing: .inLibrary)
    #expect(!String(localized: plain.spokenTileLabel(after: nil)).contains("trial"))
}

@MainActor @Test func theConsoleShelfTakesTheCloudMarksOnceTheCloudLibraryLoadedForTheSameAccount() {
    let account = UUID()
    @Shared(.selectedAccount) var selected
    $selected.withLock {
        $0 = account
    }
    var state = LibraryFeature.State()
    state.recentlyPlayed.trialMarks = [
        "PPSA00001_00": CloudTrialMark(icon: .trial, label: .libraryTrialTrial)
    ]
    #expect(state.shelfTrialMarks == state.recentlyPlayed.trialMarks)
    state.cloudLibrary.accountID = account
    state.cloudLibrary.listing.now = launchDay
    state.cloudLibrary.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [])
    #expect(state.shelfTrialMarks.isEmpty)
    state.cloudLibrary.accountID = UUID()
    #expect(state.shelfTrialMarks == state.recentlyPlayed.trialMarks)
}

@MainActor @Test func anAccountChangeForgetsWithdrawnTrials() async {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.listing.trialsWithdrawn = [usedTrial.id]
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
    }
    store.exhaustivity = .off
    await store.send(.account(UUID()))
    #expect(store.state.listing.trialsWithdrawn.isEmpty)
    await store.finish()
}
