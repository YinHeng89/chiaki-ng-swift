import Foundation
import ChiakiAssets
import Testing
import Video
@testable import ChiakiNG

@MainActor @Test func videoEffectsResourcesCreateNativePlayer() throws {
    let shaderURL = try #require(ChiakiAssets.url(forResource: "VideoColour", withExtension: "txt"))
    let weightsURL = try #require(ChiakiAssets.url(forResource: "FSRCNNX16", withExtension: "bin"))
    let player = CNLiveVideoPlayer(
        shader: try String(contentsOf: shaderURL, encoding: .utf8),
        fsrcnnWeights: try Data(contentsOf: weightsURL)
    )
    #expect(player != nil)
}
