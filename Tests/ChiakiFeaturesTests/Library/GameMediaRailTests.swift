@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing

private func wheelOffset(
    _ current: CGFloat, deltaY: CGFloat, deltaX: CGFloat = 0, precise: Bool = false, content: CGFloat = 2_000
) -> CGFloat? {
    WheelScrollsAlongRow.offset(
        from: current, viewport: 900, content: content,
        wheel: .init(deltaX: deltaX, deltaY: deltaY, precise: precise)
    )
}

@Test func aMouseWheelMovesTheMediaRailUntilItsEndThenLeavesThePageToScroll() {
    #expect(wheelOffset(0, deltaY: -1) == 40)
    #expect(wheelOffset(400, deltaY: 3) == 280)
    #expect(wheelOffset(1_090, deltaY: -5) == 1_100)
    #expect(wheelOffset(1_100, deltaY: -1) == nil)
    #expect(wheelOffset(0, deltaY: 1) == nil)
    #expect(wheelOffset(20, deltaY: 2) == 0)
}

@Test func theMediaRailLeavesTrackpadsSidewaysWheelsAndShortRowsAlone() {
    #expect(wheelOffset(0, deltaY: -12, precise: true) == nil)
    #expect(wheelOffset(0, deltaY: -1, deltaX: -4) == nil)
    #expect(wheelOffset(0, deltaY: 0) == nil)
    #expect(wheelOffset(0, deltaY: -3, content: 700) == nil)
}

@Test func theMediaRailPagesByAViewportLessOneTileAndStopsAtItsEnds() {
    var metrics = GameMediaRail.Metrics(offset: 0, viewport: 900, content: 2_000)
    #expect(metrics.maximumOffset == 1_100)
    #expect(metrics.page(forward: true) == 666)
    #expect(metrics.page(forward: false) == 0)
    metrics.offset = 666
    #expect(metrics.page(forward: true) == 1_100)
    #expect(metrics.page(forward: false) == 0)
    metrics = GameMediaRail.Metrics(offset: 0, viewport: 200, content: 2_000)
    #expect(metrics.page(forward: true) == 234)
    #expect(GameMediaRail.Metrics(offset: 0, viewport: 900, content: 500).maximumOffset == 0)
}

@Test func mediaTilesAreNamedByKindAndPosition() throws {
    let trailer = try #require(URL(string: "https://video.example/a.mp4"))
    #expect(GameMediaRail.label(0, .screenshot("https://image.example/a.png")) == "Screenshot 1")
    #expect(GameMediaRail.label(4, .trailer(trailer)) == "Trailer 5")
}
