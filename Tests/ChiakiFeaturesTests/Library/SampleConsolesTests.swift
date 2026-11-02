import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

private func isolatedDefaults() throws -> (UserDefaults, String) {
    let name = "chiaki-sample-consoles-\(UUID().uuidString)"
    return (try #require(UserDefaults(suiteName: name)), name)
}

private let alternating = SampleConsoleList((0..<5).map { index in
    SampleConsole(
        model: index.isMultiple(of: 2)
            ? .ps5
            : .ps4,
        recentlyPlayed: .withoutLayeredArt
    )
})

@Test func sampleConsolesAreDistinctPreviewsNamedByRoomAndModel() {
    let consoles = alternating.displayed()
    #expect(consoles.count == 5)
    #expect(Set(consoles).count == 5)
    #expect(Set(consoles.map(\.target.name)).count == 5)
    #expect(Set(consoles.map(\.target.remoteDeviceID)).count == 5)
    #expect(consoles.filter(\.preview).count == 5)
    #expect(consoles.map(\.target.kind) == [.ps5, .ps4, .ps5, .ps4, .ps5])
    #expect(consoles.map(\.target.name) == [
        "Bedroom PS5",
        "Office PS4",
        "Den PS5",
        "Loft PS4",
        "Basement PS5"
    ])
    #expect(consoles.filter { $0.target.remoteDeviceID == Data([1]) }.isEmpty)
    #expect(consoles.allSatisfy { $0.target.id == nil })
}

@Test func storedSampleConsolesDecodeDefensively() {
    #expect(SampleConsoleList(rawValue: "").consoles.isEmpty)
    #expect(SampleConsoleList(rawValue: "[]").consoles.isEmpty)
    #expect(SampleConsoleList(rawValue: "not json").consoles.isEmpty)
    #expect(SampleConsoleList(rawValue: "{\"model\":\"ps5\"}").consoles.isEmpty)
    #expect(SampleConsoleList(rawValue: "[{\"model\":\"ps6\",\"recentlyPlayed\":\"none\"}]").consoles.isEmpty)
    #expect(SampleConsoleList(rawValue: "[{\"model\":\"ps5\",\"recentlyPlayed\":\"sometimes\"}]").consoles
        .isEmpty)
    let valid = SampleConsoleList(
        rawValue: "[{\"model\":\"ps4\",\"recentlyPlayed\":\"none\"},"
            + "{\"model\":\"ps5\",\"recentlyPlayed\":\"withLayeredArt\"}]"
    )
    #expect(valid.consoles == [
        SampleConsole(model: .ps4, recentlyPlayed: .none),
        SampleConsole(model: .ps5, recentlyPlayed: .withLayeredArt)
    ])
    let many = Array(repeating: "{\"model\":\"ps5\",\"recentlyPlayed\":\"none\"}", count: 40)
        .joined(separator: ",")
    #expect(SampleConsoleList(rawValue: "[\(many)]").consoles.count == SampleConsoleList.limit)
    #expect(SampleConsoleList(Array(repeating: SampleConsole(), count: 500)).consoles.count == 12)
    #expect(SampleConsoleList(rawValue: valid.rawValue) == valid)
    #expect(valid.rawValue
        == "[{\"model\":\"ps4\",\"recentlyPlayed\":\"none\"},"
        + "{\"model\":\"ps5\",\"recentlyPlayed\":\"withLayeredArt\"}]")
}

@Test func eachRecentlyPlayedStateYieldsItsSample() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let list = SampleConsoleList([
        SampleConsole(model: .ps5, recentlyPlayed: .none),
        SampleConsole(model: .ps5, recentlyPlayed: .withoutLayeredArt),
        SampleConsole(model: .ps5, recentlyPlayed: .withLayeredArt)
    ])
    let shown = list.displayed(now: now)
    #expect(shown.map(\.sampleRecentlyPlayed) == [.none, .withoutLayeredArt, .withLayeredArt])
    #expect(shown[0].sampleTitle == nil)
    #expect(shown[1].sampleTitle?.name == "Harbor Lights")
    #expect(shown[2].sampleTitle?.name == "Iron Meridian")
    #expect(shown.compactMap(\.sampleTitle).allSatisfy { $0.imageURL.isEmpty && $0.launchID.isEmpty })
    #expect(shown.compactMap(\.sampleTitle?.lastPlayed)
        .allSatisfy { $0 < now && now.timeIntervalSince($0) <= 36 * 3600 })
    #expect(shown == list.displayed(now: now.addingTimeInterval(500)))
    let plan = ConsoleContinuePlan(consoles: shown, recentlyPlayed: nil, gridWidth: 1400)
    #expect(shown.map { plan.form(for: $0) } == [.hidden, .compact, .compact])
    #expect(plan.continuing.isEmpty)
    let full = SampleConsoleList(Array(repeating: SampleConsole(), count: 12)).displayed(now: now)
    #expect(Set(full.compactMap(\.sampleTitle?.name)).count == 12)
    #expect(Set(full.map(\.target.name)).count == 12)
}

@Test func aSamplePS4NeverCarriesATitleWhateverIsStored() {
    for stored in SampleConsole.RecentlyPlayed.allCases {
        let sample = SampleConsole(model: .ps4, recentlyPlayed: stored)
        #expect(sample.shownRecentlyPlayed == .none)
        let shown = SampleConsoleList([sample]).displayed()
        #expect(shown.count == 1)
        #expect(shown[0].sampleTitle == nil)
        #expect(shown[0].sampleRecentlyPlayed == .none)
        let plan = ConsoleContinuePlan(consoles: shown, recentlyPlayed: nil, gridWidth: 1400)
        #expect(plan.form(for: shown[0]) == .hidden)
    }
    var list = SampleConsoleList([SampleConsole(model: .ps5, recentlyPlayed: .withLayeredArt)])
    list.setModel(.ps4, at: 0)
    #expect(list.displayed()[0].sampleTitle == nil)
    list.setModel(.ps5, at: 0)
    #expect(list.displayed()[0].sampleRecentlyPlayed == .withLayeredArt)
}

@Test func samplesAreAddedChangedAndRemovedThroughTheStoredPreference() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer {
        defaults.removePersistentDomain(forName: suite)
    }
    #expect(SampleConsoleList.stored(in: defaults).consoles.isEmpty)
    var list = SampleConsoleList.stored(in: defaults)
    list.add()
    list.add()
    list.add()
    #expect(list.consoles == Array(
        repeating: SampleConsole(model: .ps5, recentlyPlayed: .withLayeredArt),
        count: 3
    ))
    list.setModel(.ps4, at: 1)
    list.setRecentlyPlayed(.none, at: 2)
    list.setRecentlyPlayed(.withoutLayeredArt, at: 9)
    list.store(in: defaults)
    let reread = SampleConsoleList.stored(in: defaults)
    #expect(reread == list)
    #expect(reread.consoles.map(\.model) == [.ps5, .ps4, .ps5])
    #expect(reread.consoles.map(\.shownRecentlyPlayed) == [.withLayeredArt, .none, .none])
    var shorter = reread
    shorter.remove(at: 0)
    shorter.remove(at: 7)
    shorter.store(in: defaults)
    #expect(SampleConsoleList.stored(in: defaults).consoles.map(\.model) == [.ps4, .ps5])
    #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("developer.preview") }
        == [DeveloperPreviewSetting.sampleConsoles])
    var full = SampleConsoleList(Array(repeating: SampleConsole(), count: 12))
    #expect(full.isFull)
    full.add()
    #expect(full.consoles.count == 12)
    defaults.set("garbage", forKey: DeveloperPreviewSetting.sampleConsoles)
    #expect(SampleConsoleList.stored(in: defaults).consoles.isEmpty)
    defaults.set(7, forKey: DeveloperPreviewSetting.sampleConsoles)
    #expect(SampleConsoleList.stored(in: defaults).consoles.isEmpty)
}
