@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing

private let launchDay = Date(timeIntervalSince1970: 1_800_000_000)
private let concept = "https://store.playstation.com/en-gb/concept/1"

private func endedTrial() -> CloudGame {
    CloudGame(
        productId: "ended",
        name: "Ended trial",
        platform: "PS5",
        isOwned: true,
        conceptUrl: concept,
        standing: .inLibrary,
        launchRefusal: .purchaseNeeded,
        isTrial: true,
        trialEnded: true,
        isPlayFirstTrial: true
    )
}

private func endedTrialCatalog() -> CloudLibrarySnapshot {
    CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: "owned", name: "Owned", platform: "PS5", isOwned: true, standing: .inLibrary),
        CloudGame(
            productId: "trial",
            name: "Trial game",
            platform: "PS5",
            isOwned: true,
            standing: .inLibrary,
            isTrial: true
        ),
        endedTrial()
    ])
}

@Test func anEndedTrialIsNeverListed() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = endedTrialCatalog()
    for filter in [CloudLibraryFilter.all, .owned, .plus, .browse, .preorders] {
        listing.filter = filter
        #expect(!listing.matching.contains { $0.id == "ended" })
    }
    listing.query = "Ended"
    #expect(listing.matching.isEmpty)
}

@Test func anEndedTrialIsNeverOfferedAsRecentlyPlayed() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = endedTrialCatalog()
    listing.recentlyPlayed = [CloudRecentlyPlayed(productId: "ended", lastPlayed: launchDay)]
    #expect(!listing.hasRecentlyPlayed)
    listing.filter = .recent
    #expect(listing.matching.isEmpty)
}

@Test func anEndedTrialOffersItsStorePageAndNoPlayButton() {
    let actions = CloudGameActions(
        game: endedTrial(), accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(actions.play == nil)
    #expect(actions.store == CloudGameActions.StoreLink(
        title: .libraryActionsViewInStore,
        fallback: URL(string: concept)
    ))
    #expect(actions.addToLibrary == nil)
    #expect(!actions.showsLaunchChecks)
    #expect(!actions.showsTitleNotice)
    #expect(actions.purchaseCode == URL(string: concept))
    #expect(actions.focusOrder == [.store, .purchaseCode])
}

@Test func anEndedTrialWithoutAStorePageStillOffersTheStoreButton() {
    let game = CloudGame(
        productId: "ended",
        name: "Ended trial",
        platform: "PS5",
        isOwned: true,
        standing: .inLibrary,
        isTrial: true,
        trialEnded: true,
        isPlayFirstTrial: true
    )
    let actions = CloudGameActions(
        game: game, accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false
    )
    #expect(actions.play == nil)
    #expect(actions.store.map { String(localized: $0.title) } == "View in Store")
    #expect(actions.store?.fallback == nil)
    #expect(actions.purchaseCode == nil)
    #expect(actions.focusOrder == [.store])
}

@Test func aTrialLabelAndIconTellPlayFirstTrialsFromDemos() {
    let playable = CloudGame(
        productId: "trial",
        name: "Trial game",
        isOwned: true,
        isTrial: true,
        isPlayFirstTrial: true
    )
    #expect(playable.trialLabel.map { String(localized: $0) } == "Trial")
    #expect(playable.trialIcon == .trial)
    let demo = CloudGame(productId: "demo", name: "Demo game", isOwned: true, isTrial: true)
    #expect(demo.trialLabel.map { String(localized: $0) } == "Demo")
    #expect(demo.trialIcon == .demo)
    #expect(AppIcon.demo.rawValue == "play.square")
    let owned = CloudGame(productId: "owned", name: "Owned", isOwned: true)
    #expect(owned.trialLabel == nil)
    #expect(owned.trialIcon == nil)
}
