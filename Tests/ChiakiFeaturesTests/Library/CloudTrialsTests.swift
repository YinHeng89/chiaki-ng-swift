@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let launchDay = Date(timeIntervalSince1970: 1_800_000_000)

private func trialCatalog() -> CloudLibrarySnapshot {
    CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(productId: "owned", name: "Owned", isOwned: true, standing: .inLibrary),
        CloudGame(productId: "trial", name: "Trial game", isOwned: true, standing: .inLibrary, isTrial: true),
        CloudGame(productId: "sale", name: "For sale", standing: .store),
        CloudGame(
            productId: "unreleased",
            name: "Unreleased trial",
            isOwned: true,
            standing: .inLibrary,
            release: .unannounced,
            isTrial: true
        )
    ])
}

@Test func trialsAreListedAlongsideTheGamesThatStream() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = trialCatalog()
    listing.filter = .all
    #expect(listing.matching.map(\.id) == ["owned", "trial"])
    listing.filter = .owned
    #expect(listing.matching.map(\.id) == ["owned", "trial"])
    listing.filter = .browse
    #expect(listing.matching.map(\.id) == ["sale"])
    listing.filter = .preorders
    #expect(listing.matching.map(\.id) == ["unreleased"])
}

@Test func noTabIsKeptForTrials() {
    var state = CloudLibraryFeature.State()
    state.listing.now = launchDay
    state.snapshot = trialCatalog()
    #expect(state.filters == [.all, .owned, .plus, .browse, .preorders])
}

@Test func aTrialReadsTrialUnlessItCanOnlyBeBought() {
    let trial = CloudGame(
        productId: "trial",
        name: "Trial game",
        isOwned: true,
        standing: .inLibrary,
        isTrial: true,
        isPlayFirstTrial: true
    )
    #expect(String(localized: trial.standingLabel(after: nil)) == "Trial")
    #expect(trial.entitlementIcon == .trial)
    let demo = CloudGame(
        productId: "demo",
        name: "Demo game",
        isOwned: true,
        standing: .inLibrary,
        isTrial: true
    )
    #expect(String(localized: demo.standingLabel(after: nil)) == "Demo")
    #expect(demo.entitlementIcon == .demo)
    #expect(trial.standingLabel(after: .refused) == CloudStanding.store.label)
    let owned = CloudGame(productId: "owned", name: "Owned", isOwned: true, standing: .inLibrary)
    #expect(owned.standingLabel(after: nil) == CloudStanding.inLibrary.label)
}

@Test func listedTrialsGiveTheTitleIDsTheConsoleShelfMarks() {
    var listing = CloudLibraryListing()
    listing.now = launchDay
    listing.snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
        CloudGame(
            productId: "UP9000-PPSA07632_00-SAROS00000000000",
            name: "SAROS",
            isOwned: true,
            isTrial: true,
            isPlayFirstTrial: true
        ),
        CloudGame(
            productId: "EP0001-PPSA05555_00-LIESOFPDEMO00000",
            name: "Lies of P Demo",
            isOwned: true,
            isTrial: true
        ),
        CloudGame(productId: "EP9000-PPSA01284_00-RATCHETPS5GAME00", name: "Ratchet", isOwned: true),
        CloudGame(productId: "malformed", name: "Odd", isTrial: true)
    ])
    #expect(listing.trialMarks == [
        "PPSA07632_00": CloudTrialMark(icon: .trial, label: .libraryTrialTrial),
        "PPSA05555_00": CloudTrialMark(icon: .demo, label: .libraryTrialDemo)
    ])
}

@Test func onlyATrialTheStoreNamesADemoReadsDemo() {
    let named = CloudGame(
        productId: "re4",
        name: "Resident Evil 4 Chainsaw DEMO",
        isOwned: true,
        isTrial: true
    )
    #expect(named.trialLabel.map { String(localized: $0) } == "Demo")
    #expect(named.trialIcon == .demo)
    for name in ["MAIDEN", "STRANGER OF PARADISE FINAL FANTASY ORIGIN TRIAL VERSION", "Demonstration Racer"] {
        let trial = CloudGame(productId: "trial", name: name, isOwned: true, isTrial: true)
        #expect(trial.trialLabel.map { String(localized: $0) } == "Trial")
        #expect(trial.trialIcon == .trial)
    }
    let playFirst = CloudGame(
        productId: "saros",
        name: "SAROS Demo",
        isOwned: true,
        isTrial: true,
        isPlayFirstTrial: true
    )
    #expect(playFirst.trialLabel.map { String(localized: $0) } == "Trial")
    #expect(playFirst.trialIcon == .trial)
}
