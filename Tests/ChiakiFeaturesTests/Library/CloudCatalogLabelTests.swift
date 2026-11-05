import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func standingLabelsComeFromTheCoreStanding() {
    #expect(CloudStanding.inLibrary.label == "In your library")
    #expect(CloudStanding.included.label == "Included with Premium")
    #expect(CloudStanding.mayStream.label == "May stream")
    #expect(CloudStanding.store.label == "View in Store")
    #expect(CloudStanding.ownershipUnknown.label == "View in Store")
}

@Test(.enabled(if: PS5CloudLaunchBuild.included)) func launchRequestsNeedACloudServiceAndAProduct() throws {
    let game = CloudGame(productId: "UP9000-PPSA09006_00-FULLGAME00000000", name: "Owned", isOwned: true)
    #expect(try CloudLaunchRequest(accountID: UUID(), game: game).game == game)
    #expect(throws: CloudPlaybackFailure.invalidTitle) {
        try CloudLaunchRequest(accountID: UUID(), game: CloudGame(productId: "", name: "Blank"))
    }
    #expect(throws: CloudPlaybackFailure.invalidTitle) {
        try CloudLaunchRequest(
            accountID: UUID(), game: CloudGame(productId: "X", name: "Other", streamServiceType: "other")
        )
    }
}

@Test func releaseDatesAreDisplayFactsAgainstTheDeviceClock() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(CloudReleaseDate.unrestricted.label(now: now) == nil)
    #expect(CloudReleaseDate.unannounced.label(now: now) == "Release date not announced")
    #expect(CloudReleaseDate.scheduled(now.addingTimeInterval(75)).label(now: now) == "Releases in 00:01:15")
    #expect(CloudReleaseDate.scheduled(now.addingTimeInterval(-1)).label(now: now) == nil)
    #expect(CloudReleaseDate.scheduled(now.addingTimeInterval(3 * 86400 + 3600)).label(now: now)
        == "Releases in 3d 01:00:00")
}
