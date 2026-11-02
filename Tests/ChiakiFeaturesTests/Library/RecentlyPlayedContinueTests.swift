import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@MainActor
@Test func recentlyPlayedSkipsTheGameAlreadyOfferedAsContinue() {
    let consoleID = UUID()
    let console = RegistrationFlow.ConsoleTarget(address: "192.168.1.20", kind: .ps5, id: consoleID)
    let titles = (0 ..< 3).map { index in
        RecentTitle(
            titleID: "PPSA0000\(index)_00", launchID: "PPSA0000\(index)", name: "Game \(index)",
            imageURL: "", lastPlayedMs: 0, recent: true
        )
    }
    var state = RecentlyPlayedReducer.State()
    state.selection = .init(profileID: UUID(), eligible: true)
    state.phase = .loaded
    state.rails = [RecentlyPlayedRail(consoleID: consoleID, hardwareID: fixtureHardware, titles: titles)]
    let all = RecentlyPlayedSection.rows(state, consoles: [console])
    #expect(all.first?.titles?.map(\.name) == ["Game 0", "Game 1", "Game 2"])
    let continuing = RecentlyPlayedSection.rows(state, consoles: [console], continuing: [consoleID])
    #expect(continuing.first?.titles?.map(\.name) == ["Game 1", "Game 2"])
    state.rails = [RecentlyPlayedRail(consoleID: consoleID, hardwareID: fixtureHardware, titles: [titles[0]])]
    #expect(RecentlyPlayedSection.rows(state, consoles: [console], continuing: [consoleID]).isEmpty)
}

private let fixtureHardware = Data(repeating: 0xa1, count: 6)
