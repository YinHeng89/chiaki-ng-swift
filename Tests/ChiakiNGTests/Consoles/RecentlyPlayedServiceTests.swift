import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures
@testable import ChiakiClientsLive
@testable import ChiakiNG

private let account = UUID()
private let accountBytes = Data(repeating: 7, count: 8)
private let living = UUID()
private let livingHardware = Data(repeating: 0xcd, count: 6)
private let title = RecentTitle(
    titleID: "PPSA01234_00", launchID: "PPSA01234_00", name: "Astro", imageURL: "", lastPlayedMs: 5,
    recent: true
)

private func service(
    consoles: [RecentlyPlayedConsole],
    listed: [ConsoleTitles],
    launch: @escaping @Sendable (Data, Data, RecentTitle) async throws -> ConsoleLaunchState = { _, _, _ in
        .starting
    }
) -> RecentlyPlayedService {
    RecentlyPlayedService(
        transport: ConsoleTitlesTransport(fetch: { _ in listed }, launch: launch),
        account: { _ in accountBytes },
        consoles: { _ in consoles }
    )
}

@Test func railsFollowTheConsolesTheCoreNamesByHardwareID() async throws {
    let other = Data(repeating: 0x11, count: 6)
    let subject = service(
        consoles: [RecentlyPlayedConsole(consoleID: living, hardwareID: livingHardware)],
        listed: [
            ConsoleTitles(hardwareID: HardwareID(bytes: other)!, titles: [title]),
            ConsoleTitles(hardwareID: HardwareID(bytes: livingHardware)!, titles: [title])
        ]
    )
    let result = try await subject.fetch(account: account)
    #expect(result.rails == [RecentlyPlayedRail(
        consoleID: living,
        hardwareID: livingHardware,
        titles: [title]
    )])
}

@Test func noRegisteredConsolesMeansNoRequest() async throws {
    let subject = RecentlyPlayedService(
        transport: ConsoleTitlesTransport(
            fetch: { _ in
                throw ConsoleTitlesFailure.unavailable
            },
            launch: { _, _, _ in .starting }
        ),
        account: { _ in accountBytes },
        consoles: { _ in [] }
    )
    #expect(try await subject.fetch(account: account).rails.isEmpty)
}

@Test func launchesNameTheAccountConsoleAndTitle() async throws {
    let seen = LockIsolated<[String]>([])
    let subject = service(consoles: [], listed: []) { owner, hardware, launched in
        seen
            .withValue {
                $0.append("\(owner == accountBytes):\(hardware == livingHardware):\(launched.titleID)") }
        return .completed
    }
    #expect(try await subject
        .launch(account: account, hardwareID: livingHardware, title: title) == .completed)
    #expect(seen.value == ["true:true:PPSA01234_00"])
}

@Test func signInFailuresPassThroughUnchanged() async throws {
    let subject = service(consoles: [], listed: []) { _, _, _ in
        throw ConsoleTitlesFailure.auth
    }
    await #expect(throws: ConsoleTitlesFailure.auth) {
        try await subject.launch(account: account, hardwareID: livingHardware, title: title)
    }
}

private let bedroom = UUID()
private let bedroomHardware = Data(repeating: 0x22, count: 6)

private func played(
    _ id: String, at milliseconds: Int64, concept: String = "",
    known: RecentTitle.LastPlayedKnown = .onThisConsole
) -> RecentTitle {
    RecentTitle(
        titleID: id, launchID: id, name: "Game \(id)", imageURL: "", lastPlayedMs: milliseconds, recent: true,
        conceptID: concept, lastPlayedKnown: known
    )
}

@Test func eachConsoleKeepsItsOwnTitlesInTheCoresOrder() async throws {
    let shared = "PPSA01234_00"
    let other = "PPSA05678_00"
    let onLiving = [played(shared, at: 300, concept: "10000001"), played(other, at: 900, concept: "10000002")]
    let onBedroom = [
        played(other, at: 100, concept: "10000002"),
        played(shared, at: 700, concept: "10000001", known: .onTheAccount),
        played("PPSA09999_00", at: 0)
    ]
    let subject = service(
        consoles: [
            RecentlyPlayedConsole(consoleID: bedroom, hardwareID: bedroomHardware),
            RecentlyPlayedConsole(consoleID: living, hardwareID: livingHardware)
        ],
        listed: [
            ConsoleTitles(hardwareID: HardwareID(bytes: livingHardware)!, titles: onLiving),
            ConsoleTitles(hardwareID: HardwareID(bytes: bedroomHardware)!, titles: onBedroom)
        ]
    )
    let rails = try await subject.fetch(account: account).rails
    #expect(rails.map(\.consoleID) == [bedroom, living])
    #expect(rails[0].titles == onBedroom)
    #expect(rails[1].titles == onLiving)
    #expect(rails[1].titles.map(\.lastPlayedMs) == [300, 900])
    #expect(rails[0].titles.map(\.conceptID) == ["10000002", "10000001", ""])
    #expect(rails[0].titles.map(\.lastPlayedKnown) == [.onThisConsole, .onTheAccount, .onThisConsole])
    #expect(rails[0].titles.map(\.playedOnThisConsole) == [true, false, false])
    var state = RecentlyPlayedReducer.State()
    state.selection = .init(profileID: account, eligible: true)
    state.phase = .loaded
    state.rails = rails
    #expect(state.rail(for: living)?.titles.first?.titleID == shared)
    #expect(state.rail(for: bedroom)?.titles.first?.titleID == other)
    #expect(state.rail(for: UUID()) == nil)
}

@Test func theLoadedLineCountsEachConsolesTitlesAndItsOwnTimes() async throws {
    let rails = [
        RecentlyPlayedRail(consoleID: living, hardwareID: livingHardware, titles: [
            played("PPSA01234_00", at: 300), played("PPSA05678_00", at: 200, known: .onTheAccount),
            played("PPSA09999_00", at: 0)
        ]),
        RecentlyPlayedRail(consoleID: bedroom, hardwareID: bedroomHardware, titles: [])
    ]
    #expect(RecentlyPlayedService.loadedLine(rails)
        == "Recently played loaded: console cdcdcdcd… 3 title(s), 1 with the console's own time; "
        + "console 22222222… 0 title(s), 0 with the console's own time")
    #expect(RecentlyPlayedService.loadedLine([]) == "Recently played loaded: no console listed titles")
    let logged = LockIsolated<[String]>([])
    let subject = RecentlyPlayedService(
        transport: ConsoleTitlesTransport(
            fetch: { _ in [ConsoleTitles(
                hardwareID: HardwareID(bytes: livingHardware)!,
                titles: [played("PPSA01234_00", at: 300)]
            )] },
            launch: { _, _, _ in .starting }
        ),
        account: { _ in accountBytes },
        consoles: { _ in [RecentlyPlayedConsole(consoleID: living, hardwareID: livingHardware)] },
        log: { level, message in
            logged.withValue { $0.append("\(level): \(message)") }
        }
    )
    _ = try await subject.fetch(account: account)
    #expect(logged.value.last
        == "info: Recently played loaded: console cdcdcdcd… 1 title(s), 1 with the console's own time")
}
