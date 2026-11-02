@testable import ChiakiFeatures
import ChiakiModels
import Testing

@Test func frameGenerationIsUnavailableWhenTheStreamRequestsHDR() {
    #expect(StreamTuningConfiguration(frameGenerationAvailable: true).frameGenerationAvailable)
    let hdr = StreamTuningConfiguration(frameGenerationAvailable: true, hdrRequested: true)
    #expect(!hdr.frameGenerationAvailable)
    #expect(hdr.hdrRequested)
}

@MainActor @Test func colourSlidersStepByFivePercentAndStopAtTheirLimits() throws {
    let brighter = try #require(StreamMenuColourControls.adjusted(
        PictureAdjustments(),
        .colourBrightness,
        by: 1
    ))
    #expect(abs(brighter.brightness - 0.05) < 1e-9)
    var top = PictureAdjustments(gamma: PictureAdjustments.gammaRange.upperBound)
    top = try #require(StreamMenuColourControls.adjusted(top, .colourGamma, by: 1))
    #expect(top.gamma == PictureAdjustments.gammaRange.upperBound)
    #expect(StreamMenuColourControls.adjusted(PictureAdjustments(), .colourReset, by: 1) == nil)
    #expect(StreamMenuColourControls.adjusted(PictureAdjustments(), .pictureZoom, by: 1) == nil)
    #expect(StreamMenuColourControls.controls.last == .colourReset)
}

@Test func streamMenuSliderAdjustmentHasExplicitEntryAndExit() {
    var navigation = StreamMenuSliderNavigationState.navigating
    #expect(StreamMenuControl.soundVolume.isSlider)
    #expect(!StreamMenuControl.colourReset.isSlider)
    #expect(!navigation.isAdjusting(.soundVolume))
    navigation.confirm(.soundVolume, current: StreamTuningConfiguration())
    #expect(navigation.isAdjusting(.soundVolume))
    navigation.confirm(.soundVolume, current: StreamTuningConfiguration())
    #expect(!navigation.isAdjusting(.soundVolume))
    navigation.confirm(.colourBrightness, current: StreamTuningConfiguration())
    navigation.leave()
    #expect(!navigation.isAdjusting(.colourBrightness))
}
