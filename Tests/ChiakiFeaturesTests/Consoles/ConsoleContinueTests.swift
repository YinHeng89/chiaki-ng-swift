import ChiakiModels
import Foundation
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus

private let hardware = Data(repeating: 0xa1, count: 6)

private func title(_ name: String) -> RecentTitle {
    RecentTitle(
        titleID: "\(name)_00",
        launchID: name,
        name: name,
        imageURL: "",
        lastPlayedMs: 1,
        recent: true
    )
}

private func console(_ kind: RegistrationFlow.ConsoleKind, _ id: UUID) -> DisplayedConsole {
    DisplayedConsole(
        target: RegistrationFlow.ConsoleTarget(
            address: "192.168.1.\(abs(id.hashValue) % 200)",
            kind: kind,
            id: id
        ),
        preview: false
    )
}

private func played(_ rails: [UUID: [String]]) -> RecentlyPlayedReducer.State {
    var state = RecentlyPlayedReducer.State()
    state.selection = .init(profileID: UUID(), eligible: true)
    state.phase = .loaded
    state.rails = rails.map { id, names in
        RecentlyPlayedRail(consoleID: id, hardwareID: hardware, titles: names.map(title))
    }
    return state
}

@Test func onlyAPS5WithItsOwnLastPlayedTitleOffersContinue() {
    let game = title("Game")
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 690) == .compact)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 660) == .compact)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 899) == .compact)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 900) == .wide)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 1400) == .wide)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: nil, cardWidth: 1400) == .hidden)
    #expect(ConsoleContinueForm.of(kind: .ps4, lastPlayed: game, cardWidth: 1400) == .hidden)
    #expect(ConsoleContinueForm.of(kind: .ps4, lastPlayed: game, cardWidth: 690) == .hidden)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 659) == .hidden)
    #expect(ConsoleContinueForm.of(kind: .ps5, lastPlayed: game, cardWidth: 0) == .hidden)
    #expect(ConsoleContinueForm.compactWidth == 660)
}

@MainActor @Test func aConsoleNeverBorrowsAnotherConsolesTitle() {
    let owner = console(.ps5, UUID())
    let other = console(.ps5, UUID())
    let old = console(.ps4, UUID())
    let state = played([
        owner.target.id ?? UUID(): ["Mine", "Older"],
        old.target.id ?? UUID(): ["Legacy"]
    ])
    let plan = ConsoleContinuePlan(consoles: [owner, other, old], recentlyPlayed: state, gridWidth: 1400)
    #expect(plan.columns == 2)
    #expect(plan.cardWidth == 691)
    #expect(plan.title(for: owner)?.name == "Mine")
    #expect(plan.title(for: other) == nil)
    #expect(plan.form(for: owner) == .compact)
    #expect(plan.form(for: other) == .hidden)
    #expect(plan.title(for: old)?.name == "Legacy")
    #expect(plan.form(for: old) == .hidden)
    #expect(ConsoleContinuePlan(consoles: [owner], recentlyPlayed: nil, gridWidth: 1400)
        .form(for: owner) == .hidden)
}

@MainActor @Test func theRailsSkipExactlyTheTitlesTheCardsOffer() {
    let first = console(.ps5, UUID())
    let second = console(.ps5, UUID())
    let third = console(.ps5, UUID())
    let old = console(.ps4, UUID())
    let consoles = [first, second, third, old]
    let ids = consoles.compactMap(\.target.id)
    let state = played([ids[0]: ["A1", "A2"], ids[1]: ["B1"], ids[3]: ["D1"]])
    for width in [CGFloat(700), 1000, 1099, 1100, 1337, 1338, 1400, 2000] {
        let plan = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: width)
        let shown = Set(consoles.filter { plan.form(for: $0) != .hidden }.compactMap(\.target.id))
        #expect(plan.continuing == shown)
    }
    let two = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 1400)
    #expect(two.columns == 2)
    #expect(two.continuing == [ids[0], ids[1]])
    let rows = RecentlyPlayedSection.rows(state, consoles: consoles.map(\.target), continuing: two.continuing)
    #expect(rows.map(\.consoleID) == [ids[0]])
    #expect(rows.first?.titles?.map(\.name) == ["A2"])
    let crowded = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 1337)
    #expect(crowded.columns == 2 && crowded.cardWidth < ConsoleContinueForm.compactWidth)
    #expect(crowded.continuing.isEmpty)
    #expect(ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 1338).continuing
        .count == 2)
    let stacked = ConsoleContinuePlan(consoles: consoles, recentlyPlayed: state, gridWidth: 1000)
    #expect(stacked.columns == 1)
    #expect(stacked.form(for: first) == .wide)
    #expect(stacked.continuing == [ids[0], ids[1]])
    let single = ConsoleContinuePlan(consoles: [first], recentlyPlayed: state, gridWidth: 1400)
    #expect(single.columns == 1 && single.form(for: first) == .wide)
    #expect(single.continuing == [ids[0]])
    let narrow = ConsoleContinuePlan(consoles: [first], recentlyPlayed: state, gridWidth: 640)
    #expect(narrow.continuing.isEmpty)
}

@Test func samplePS5sWithATitleOfferContinueAndSamplePS4sNever() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let samples = SampleConsoleList((0..<6).map { index in
        SampleConsole(
            model: index.isMultiple(of: 2)
                ? .ps5
                : .ps4,
            recentlyPlayed: index == 4
                ? .none
                : .withLayeredArt
        )
    }).displayed(now: now)
    #expect(samples.map { $0.sampleTitle != nil } == [true, false, true, false, false, false])
    let plan = ConsoleContinuePlan(consoles: samples, recentlyPlayed: nil, gridWidth: 1400)
    #expect(samples.map { plan.form(for: $0) } == [.compact, .hidden, .compact, .hidden, .hidden, .hidden])
    #expect(plan.continuing.isEmpty)
    let wide = ConsoleContinuePlan(consoles: [samples[0]], recentlyPlayed: nil, gridWidth: 1400)
    #expect(wide.form(for: samples[0]) == .wide)
    let older = DisplayedConsole(target: samples[0].target, preview: true)
    #expect(plan.form(for: older) == .hidden)
    #expect(older.sampleRecentlyPlayed == .none)
}

@Test func focusMovesToAndFromContinueAcrossATwoColumnGrid() {
    let continues: Set<Int> = [0, 2, 3]
    func stop(_ index: Int, onContinue: Bool = false, _ direction: MenuMoveDirection) -> ConsoleGridStop {
        ConsoleGridNavigation.stop(
            from: ConsoleGridOrigin(index: index, onContinue: onContinue), count: 5, columns: 2, direction,
            continues: { continues.contains($0) }
        )
    }
    #expect(stop(0, onContinue: true, .right) == .play(1))
    #expect(stop(1, .left) == .resume(0))
    #expect(stop(3, .left) == .resume(2))
    #expect(stop(0, onContinue: true, .down) == .resume(2))
    #expect(stop(0, .down) == .play(2))
    #expect(stop(2, onContinue: true, .up) == .resume(0))
    #expect(stop(3, onContinue: true, .up) == .play(1))
    #expect(stop(1, .down) == .play(3))
    #expect(stop(2, onContinue: true, .down) == .play(4))
    #expect(stop(0, onContinue: true, .up) == .outside)
    #expect(stop(0, onContinue: true, .left) == .outside)
    #expect(stop(3, onContinue: true, .right) == .outside)
    #expect(stop(4, .down) == .outside)
    #expect(stop(3, onContinue: true, .down) == .outside)
    #expect(stop(4, .right) == .outside)
    let single = ConsoleGridNavigation.stop(
        from: ConsoleGridOrigin(index: 0, onContinue: true), count: 1, columns: 1, .down,
        continues: { _ in true }
    )
    #expect(single == .outside)
    let consoles = SampleConsoleList([SampleConsole(), SampleConsole(model: .ps4)]).displayed()
    #expect(ConsoleGridStop.resume(0).focus(in: consoles) == .action(consoles[0], .resume))
    #expect(ConsoleGridStop.play(1).focus(in: consoles) == .console(consoles[1]))
    #expect(ConsoleGridStop.outside.focus(in: consoles) == nil)
}
