@testable import ChiakiFeatures
import ChiakiModels
import Testing

@Test func recentTitlesGrowIntoTheHeightTheConsolesPageLeavesFree() {
    let standard = RecentTitleWidth.standard
    #expect(RecentTitleWidth.fitting(viewport: 0, content: 600, current: standard) == standard)
    #expect(RecentTitleWidth.fitting(viewport: 700, content: 600, current: standard) == 252)
    #expect(RecentTitleWidth.fitting(viewport: 700, content: 684, current: 252) == 252)
    #expect(RecentTitleWidth.fitting(viewport: 1200, content: 600, current: standard) == RecentTitleWidth
        .largest)
    #expect(RecentTitleWidth.fitting(viewport: 700, content: 1400, current: standard) == standard)
    #expect(RecentTitleWidth.fitting(viewport: 700, content: 760, current: 280) == 204)
}

@Test func wholeCoversFillTheRow() {
    #expect(RecentTitleWidth.filling(row: 0, upTo: 250) == 250)
    #expect(RecentTitleWidth.filling(row: 1360, upTo: 252) == 252)
    #expect(RecentTitleWidth.filling(row: 1360, upTo: 260) == 256)
    #expect(RecentTitleWidth.fitting(viewport: 700, content: 600, current: 168, row: 1360) == 252)
    #expect(RecentTitleWidth.spacing(row: 1360, width: 252) == 25)
    #expect(RecentTitleWidth.spacing(row: 1360, width: 256) == 20)
    #expect(RecentTitleWidth.spacing(row: 0, width: 252) == RecentTitleWidth.gap)
}
