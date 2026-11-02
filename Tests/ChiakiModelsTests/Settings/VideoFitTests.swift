import ChiakiModels
import Foundation
import Testing

@Test func fitLetterboxesWideWindowsAndPillarboxesTallWindows() {
    let wide = VideoFit().frame(width: 2000, height: 900)
    #expect(wide == VideoFrame(originX: 200, originY: 0, width: 1600, height: 900))
    let tall = VideoFit().frame(width: 1600, height: 1200)
    #expect(tall == VideoFrame(originX: 0, originY: 150, width: 1600, height: 900))
}

@Test func zoomFillsTheWindowAndScalesAroundTheCentre() {
    let fill = VideoFit(mode: .zoom).frame(width: 1600, height: 1200)
    #expect(fill.height == 1200)
    #expect(fill.originX < 0 && fill.originY == 0)
    let doubled = VideoFit(mode: .zoom, zoom: 2).frame(width: 1600, height: 900)
    #expect(doubled == VideoFrame(originX: -800, originY: -450, width: 3200, height: 1800))
}

@Test func stretchCoversTheWholeWindow() {
    #expect(VideoFit(mode: .stretch).frame(width: 1000, height: 1000)
        == VideoFrame(originX: 0, originY: 0, width: 1000, height: 1000))
}

@Test func videoFitClampsZoomAndDefaultsMissingFields() throws {
    #expect(VideoFit(mode: .zoom, zoom: 9).zoom == VideoFit.zoomRange.upperBound)
    let decoded = try JSONDecoder().decode(VideoFit.self, from: Data(#"{"zoom":0.2}"#.utf8))
    #expect(decoded == VideoFit(mode: .fit, zoom: 1))
    let legacy = try JSONDecoder().decode(PictureSettings.self, from: Data(#"{"height":720}"#.utf8))
    #expect(legacy.videoFit == VideoFit())
}
