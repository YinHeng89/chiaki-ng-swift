import ChiakiModels
import Foundation
import Testing

@Test func psCloudTitleFollowsTheBuildSetting() {
    let game = CloudGame(productId: "EP9000-PPSA01234_00-ASTROBOT00000000", name: "Astro Bot")
    let request = try? CloudLaunchRequest(accountID: UUID(), game: game)
    #expect((request != nil) == PS5CloudLaunchBuild.included)
}

@Test func psNowTitleLaunchesInEveryBuild() throws {
    let game = CloudGame(
        productId: "EP9000-CUSA01234_00-CLASSIC000000000",
        name: "Classic",
        platform: "PS4",
        streamServiceType: "psnow"
    )
    #expect(throws: Never.self) {
        try CloudLaunchRequest(accountID: UUID(), game: game)
    }
}
