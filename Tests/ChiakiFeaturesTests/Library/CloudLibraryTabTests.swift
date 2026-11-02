import ChiakiDiagnostics
import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

private let oneOfEachKind = CloudLibrarySnapshot(settledLocale: "en-US", games: [
    CloudGame(productId: "catalog", name: "Catalog", plusCatalog: true, standing: .included),
    CloudGame(
        productId: "catalog-held",
        name: "Catalog held",
        isOwned: true,
        plusCatalog: true,
        standing: .inLibrary
    ),
    CloudGame(productId: "purchase", name: "Purchase", isOwned: true, standing: .inLibrary),
    CloudGame(
        productId: "old-owned", name: "Old owned", platform: "PS4", isOwned: true, plusCatalog: true,
        streamServiceType: "psnow", standing: .included
    ),
    CloudGame(
        productId: "old", name: "Old", platform: "PS3", streamServiceType: "psnow", standing: .included
    ),
    CloudGame(productId: "marked", name: "Marked", plusCatalog: true, standing: .mayStream),
    CloudGame(productId: "unknown", name: "Unknown", plusCatalog: true, standing: .ownershipUnknown),
    CloudGame(productId: "store", name: "Store", standing: .store),
    CloudGame(productId: "store-unknown", name: "Store unknown", standing: .ownershipUnknown),
    CloudGame(productId: "hidden", name: "Hidden", plusCatalog: true, visible: false, standing: .included)
])

private func tab(_ filter: CloudLibraryFilter, platform: CloudPlatformFilter = .all) -> [String] {
    var state = CloudLibraryFeature.State()
    state.snapshot = oneOfEachKind
    state.filter = filter
    state.platform = platform
    return state.matchingGames.map(\.id)
}

@Test func thePlusTabListsEveryCatalogTitleWhateverItsStanding() {
    #expect(tab(.plus) == ["catalog", "catalog-held", "old-owned", "old", "marked", "unknown"])
    #expect(tab(.plus, platform: .ps5) == ["catalog", "catalog-held", "marked", "unknown"])
}

@Test func theLibraryTabListsHeldPS5TitlesOnly() {
    #expect(tab(.owned) == ["catalog-held", "purchase"])
}

@Test func theBrowseTabListsPS5TitlesOutsideTheCatalogThatAreNotHeld() {
    #expect(tab(.browse) == ["store", "store-unknown"])
}

@Test func theAllTabListsEveryVisibleTitleExceptThoseOnlyForSale() {
    let forSale = Set(tab(.browse))
    #expect(tab(.all) == oneOfEachKind.games.map(\.id).filter { $0 != "hidden" && !forSale.contains($0) })
    #expect(!forSale.isEmpty)
}

@Test func aCatalogTitleKeepsTheLabelOfItsStanding() {
    let labels = Dictionary(uniqueKeysWithValues: oneOfEachKind.games.map { ($0.id, $0.standing.label) })
    #expect(labels["catalog"] == "Included with Premium")
    #expect(labels["catalog-held"] == "In your library")
    #expect(labels["purchase"] == "In your library")
    #expect(labels["old-owned"] == "Included with Premium")
    #expect(labels["marked"] == "May stream")
    #expect(labels["store"] == "View in Store")
}

@Test func theLoggedCatalogCountIsThePlusTabsCount() {
    let line = CloudLibraryLog.loaded(oneOfEachKind, who: "someone", locale: "en-US", milliseconds: 1)
    #expect(tab(.plus).count == 6)
    #expect(line.contains(", \(tab(.plus).count) in the PS Plus catalog, "))
    #expect(line.contains("1 hidden"))
}
