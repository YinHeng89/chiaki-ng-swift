import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

private let ps5 = "UP9000-PPSA01289_00-SACKBOYADVENTURE"
private let ps4 = "UP9000-CUSA18886_00-SACKBOYADVENTURE"

private func versions(ps5Visible: Bool = true) -> CloudLibrarySnapshot {
    CloudLibrarySnapshot(settledLocale: "en-US", games: [
        CloudGame(
            productId: ps5, name: "Sackboy", platform: "PS5", plusCatalog: true, visible: ps5Visible,
            otherVersion: CloudOtherVersion(productId: ps4, leads: true)
        ),
        CloudGame(
            productId: ps4, name: "Sackboy PS4", platform: "PS4", plusCatalog: true,
            streamServiceType: "psnow",
            otherVersion: CloudOtherVersion(productId: ps5, leads: false)
        ),
        CloudGame(productId: "UP9000-CUSA00001_00-OTHERGAME0000000", name: "Other", platform: "PS4",
                  plusCatalog: true, streamServiceType: "psnow")
    ])
}

private func listing(_ snapshot: CloudLibrarySnapshot, platform: CloudPlatformFilter = .all,
                     query: String = "") -> CloudLibraryListing {
    var listing = CloudLibraryListing()
    listing.snapshot = snapshot
    listing.platform = platform
    listing.query = query
    return listing
}

@Test func bothVersionsOfAGameShowAsOneCardUnderThePS5Version() {
    #expect(listing(versions()).matching.map(\.id) == [ps5, "UP9000-CUSA00001_00-OTHERGAME0000000"])
    #expect(listing(versions(), query: "Sackboy").matching.map(\.id) == [ps5])
    #expect(listing(versions()).game(ps4)?.name == "Sackboy PS4")
}

@Test func aPlatformFilterShowsTheVersionOnThatPlatform() {
    #expect(listing(versions(), platform: .ps4).matching.map(\.id)
        == [ps4, "UP9000-CUSA00001_00-OTHERGAME0000000"])
    #expect(listing(versions(), platform: .ps5).matching.map(\.id) == [ps5])
}

@Test func aHiddenPS5VersionLeavesThePS4VersionShown() {
    #expect(listing(versions(ps5Visible: false)).matching.map(\.id)
        == [ps4, "UP9000-CUSA00001_00-OTHERGAME0000000"])
}

@Test func theCardOfALinkedGameNamesBothPlatforms() {
    let snapshot = versions()
    #expect(snapshot.games[0].otherPlatform == "PS4")
    #expect(snapshot.games[1].otherPlatform == nil)
    #expect(snapshot.games[2].otherPlatform == nil)
}

@Test func theDetailOffersTheOtherVersionLastInItsFocusOrder() {
    let snapshot = versions()
    let actions = CloudGameActions(
        game: snapshot.games[0], accountID: UUID(), check: nil, bundleChoices: nil, titleRefreshIdle: true,
        mayRefreshTitle: false, otherVersion: snapshot.games[1]
    )
    #expect(actions.otherVersion == CloudGameActions.VersionSwitch(to: snapshot.games[1]))
    #expect(actions.otherVersion.map { String(localized: $0.title) } == "Show PS4 version")
    #expect(actions.focusOrder.last == .otherVersion)
    let picking = CloudGameActions(
        game: snapshot.games[0], accountID: UUID(), check: nil, bundleChoices: [], titleRefreshIdle: true,
        mayRefreshTitle: false, otherVersion: snapshot.games[1]
    )
    #expect(picking.otherVersion == nil)
}

@Test func theLibraryOffersOnlyAListedOtherVersion() {
    var state = CloudLibraryFeature.State()
    state.listing.snapshot = versions()
    #expect(state.actions(for: state.listing.game(ps4)!).otherVersion?.productId == ps5)
    state.listing.snapshot = versions(ps5Visible: false)
    #expect(state.actions(for: state.listing.game(ps4)!).otherVersion == nil)
}
