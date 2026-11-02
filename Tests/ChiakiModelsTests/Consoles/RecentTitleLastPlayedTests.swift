import ChiakiModels
import Foundation
import Testing

@Test func aRecentTitleHasNoLastPlayedDateAtOrBeforeTheEpoch() {
    func title(_ milliseconds: Int64) -> RecentTitle {
        RecentTitle(titleID: "PPSA00001_00", launchID: "PPSA00001_00", name: "Game", imageURL: "",
                    lastPlayedMs: milliseconds)
    }
    #expect(title(0).lastPlayed == nil)
    #expect(title(-1).lastPlayed == nil)
    #expect(title(1).lastPlayed == Date(timeIntervalSince1970: 0.001))
    #expect(title(1_760_000_000_250).lastPlayed == Date(timeIntervalSince1970: 1_760_000_000.25))
}
