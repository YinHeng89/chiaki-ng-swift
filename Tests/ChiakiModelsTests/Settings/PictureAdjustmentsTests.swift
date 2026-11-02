import ChiakiModels
import Foundation
import Testing

@Test func pictureAdjustmentsStartNeutralAndClampToTheirRanges() {
    #expect(PictureAdjustments().isNeutral)
    let extreme = PictureAdjustments(brightness: 3, contrast: -1, saturation: 9, gamma: 0.1)
    #expect(extreme.brightness == PictureAdjustments.brightnessRange.upperBound)
    #expect(extreme.contrast == PictureAdjustments.contrastRange.lowerBound)
    #expect(extreme.saturation == PictureAdjustments.saturationRange.upperBound)
    #expect(extreme.gamma == PictureAdjustments.gammaRange.lowerBound)
    #expect(!extreme.isNeutral)
}

@Test func pictureAdjustmentsSnapToFivePercentStepsAndRejectNonFiniteValues() {
    let snapped = PictureAdjustments(brightness: 0.12, contrast: 1.074, saturation: 0.0249, gamma: 1.226)
    #expect(abs(snapped.brightness - 0.1) < 1e-9)
    #expect(abs(snapped.contrast - 1.05) < 1e-9)
    #expect(snapped.saturation == 0)
    #expect(abs(snapped.gamma - 1.25) < 1e-9)
    let broken = PictureAdjustments(brightness: .nan, contrast: .infinity, saturation: .nan, gamma: .nan)
    #expect(broken.brightness == 0)
    #expect(broken.contrast == PictureAdjustments.contrastRange.lowerBound)
    #expect(broken.saturation == 0)
    #expect(broken.gamma == PictureAdjustments.gammaRange.lowerBound)
}

@Test func savedPictureSettingsWithoutAdjustmentsLoadNeutralAndRoundTrip() throws {
    let console = try JSONDecoder().decode(PictureSettings.self, from: Data(#"{"height":720}"#.utf8))
    #expect(console.adjustments.isNeutral)
    #expect(console.reduceBanding)
    let cloud = try JSONDecoder().decode(CloudPictureSettings.self, from: Data("{}".utf8))
    #expect(cloud.adjustments.isNeutral)
    #expect(cloud.reduceBanding)
    let partial = try JSONDecoder().decode(PictureAdjustments.self, from: Data(#"{"gamma":1.5}"#.utf8))
    #expect(partial == PictureAdjustments(gamma: 1.5))
    var settings = PictureSettings()
    settings.adjustments = PictureAdjustments(brightness: -0.1, contrast: 1.2, saturation: 0.8, gamma: 0.9)
    settings.reduceBanding = false
    let decoded = try JSONDecoder().decode(PictureSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.adjustments == settings.adjustments)
    #expect(!decoded.reduceBanding)
}

@Test func cloudPictureSettingsKeepHighQualityUnlessStableWasSaved() throws {
    var cloud = try JSONDecoder().decode(CloudPictureSettings.self, from: Data("{}".utf8))
    #expect(cloud.psCloudQuality == .high)
    cloud.psCloudQuality = .stable
    let decoded = try JSONDecoder().decode(CloudPictureSettings.self, from: JSONEncoder().encode(cloud))
    #expect(decoded.psCloudQuality == .stable)
}
