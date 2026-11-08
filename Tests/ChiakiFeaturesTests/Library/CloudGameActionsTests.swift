import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

private let concept = "https://store.playstation.com/en-gb/concept/1"

@Test(.enabled(if: PS5CloudLaunchBuild
        .included)) func anOwnedGameThatCanAlsoBeAddedShowsItsTitleNoticeOnce() {
    let game = CloudGame(
        productId: "owned", name: "Owned", isOwned: true, conceptUrl: concept, standing: .inLibrary,
        canBeAddedToLibrary: true
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: true
    )
    #expect(actions.play?.isEnabled == true)
    #expect(actions.addToLibrary != nil)
    #expect(actions.showsTitleNotice)
    #expect(actions.focusOrder == [.play, .addToLibrary, .refreshTitle])
}

@Test func aGameThatMustBeAddedFirstOffersOnlyTheStore() {
    let game = CloudGame(
        productId: "catalog", name: "Catalog", plusCatalog: true, conceptUrl: concept, standing: .included,
        needsLibraryAdd: true,
        canBeAddedToLibrary: true
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(actions.play == nil)
    #expect(!actions.showsLaunchChecks)
    #expect(actions.showsLibraryAddHint)
    #expect(actions.focusOrder == [.addToLibrary])
}

@Test func aGameTheStreamServiceRefusesOffersItsStorePageInsteadOfPlay() {
    let game = CloudGame(
        productId: "doubted", name: "Doubted", isOwned: true, conceptUrl: concept, standing: .mayStream,
        needsStorefrontCheck: true
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: .notStreamable, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(actions.play?.isEnabled == false)
    #expect(actions.store.map { String(localized: $0.title) } == "View in Store")
    #expect(actions.purchaseCode == URL(string: concept))
    #expect(actions.focusOrder == [.store, .purchaseCode])
}

@Test func aGameOnSaleOffersItsStorePageAsACodeToBuyIt() {
    let game = CloudGame(
        productId: "sale",
        name: "Sale",
        platform: "PS5",
        conceptUrl: concept,
        standing: .store
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(game.isStoreOnly)
    #expect(actions.store.map { String(localized: $0.title) } == "View in Store")
    #expect(actions.addToLibrary == nil)
    #expect(actions.purchaseCode == URL(string: concept))
    #expect(actions.focusOrder.suffix(2) == [.store, .purchaseCode])
}

@Test func aGameThatCanBeAddedOffersNoCodeToBuyIt() {
    let game = CloudGame(
        productId: "catalog", name: "Catalog", plusCatalog: true, conceptUrl: concept, standing: .included,
        needsLibraryAdd: true,
        canBeAddedToLibrary: true
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(actions.purchaseCode == nil)
    #expect(actions.addToLibrary != nil)
}
