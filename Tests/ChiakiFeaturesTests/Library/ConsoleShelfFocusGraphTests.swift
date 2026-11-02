import ChiakiModels
import Foundation
import MenuFocus
import Testing
@testable import ChiakiFeatures

private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let first = DisplayedConsole(
    target: RegistrationFlow.ConsoleTarget(address: "first", kind: .ps5, id: firstID),
    preview: false
)
private let second = DisplayedConsole(
    target: RegistrationFlow.ConsoleTarget(address: "second", kind: .ps5, id: secondID),
    preview: false
)

private func graph(
    consoles: [DisplayedConsole] = [first, second],
    columns: Int = 2,
    recent: [ConsoleShelfFocusGraph.RecentRow] = [],
    status: Bool = false,
    compact: Bool = false
) -> ConsoleShelfFocusGraph {
    ConsoleShelfFocusGraph(
        consoles: consoles,
        columns: columns,
        recentRows: recent,
        hasStatusAction: status,
        compact: compact
    )
}

@Test func consolesWalkAcrossTheGridAndUpToAddConsole() {
    let shelf = graph()
    #expect(shelf.moveConsole(from: .console(first), .right) == .focus(.console(second)))
    #expect(shelf.moveConsole(from: .console(first), .up) == .focus(.addConsole))
    #expect(shelf.moveConsole(from: .console(first), .left) == .leave(.left))
    #expect(shelf.moveConsole(from: .console(first), .down) == .leave(.down))
    #expect(graph(status: true).moveConsole(from: .console(first), .up) == .focus(.statusAction))
}

@Test func downFromAConsoleEntersItsRecentlyPlayedRow() {
    let shelf = graph(recent: [
        .init(consoleID: secondID, titleIDs: ["b1"]),
        .init(consoleID: firstID, titleIDs: ["a1", "a2"])
    ])
    #expect(shelf.moveConsole(from: .console(first), .down) == .focus(.recentTitle(firstID, "a1")))
    #expect(shelf.moveRecent(from: .recentTitle(firstID, "a1"), .right) == .focus(.recentTitle(
        firstID,
        "a2"
    )))
    #expect(shelf.moveRecent(from: .recentTitle(firstID, "a2"), .right) == .leave(.right))
    #expect(shelf.moveRecent(from: .recentTitle(firstID, "a2"), .up) == .focus(.recentTitle(secondID, "b1")))
    #expect(shelf.moveRecent(from: .recentTitle(secondID, "b1"), .up) == .focus(.console(second)))
    #expect(shelf.moveRecent(from: .recentTitle(firstID, "a1"), .down) == .leave(.down))
}

@Test func addConsoleLeadsIntoTheShelfOrTheStatusButton() {
    #expect(graph().moveConsole(from: .addConsole, .down) == .focus(.console(first)))
    #expect(graph(status: true).moveConsole(from: .addConsole, .down) == .focus(.statusAction))
    #expect(graph().moveConsole(from: .addConsole, .up) == .leave(.up))
    #expect(graph(compact: true).moveConsole(from: .addConsole, .left) == .focus(.notifications))
    #expect(graph(consoles: []).moveConsole(from: .addConsole, .down) == .leave(.down))
    #expect(graph().moveStatusAction(.down) == .firstConsole)
    #expect(graph().moveStatusAction(.up) == .focus(.addConsole))
}

@Test func compactSectionTabsHandFocusToTheContentBelowThem() {
    var shelf = graph(compact: true)
    shelf.tabCenters = [.cloud: 240]
    #expect(shelf.header.moveSection(from: .consoles, .right) == .focus(.librarySection(.cloud)))
    #expect(shelf.header.moveSection(from: .cloud, .right) == .focus(.librarySection(.trophies)))
    #expect(shelf.header.moveSection(from: .trophies, .right) == .focus(.profile))
    #expect(shelf.header.moveSection(from: .consoles, .left) == .focus(.addConsole))
    #expect(shelf.header.moveSection(from: .cloud, .down) == .content(LibraryContentFocus(
        .browse,
        horizontalPosition: 240
    )))
    shelf.cloudUnavailable = true
    #expect(shelf.header.moveSection(from: .consoles, .right) == .focus(.librarySection(.trophies)))
    #expect(shelf.header.moveSection(from: .trophies, .left) == .focus(.librarySection(.consoles)))
    shelf.sections = [.consoles, .cloud]
    #expect(shelf.header.moveSection(from: .consoles, .right) == .focus(.profile))
}

@Test func theFirstStopFollowsTheAccountAndTheShelf() {
    #expect(graph().firstStop == .console(first))
    #expect(graph(consoles: []).firstStop == .addConsole)
    var signedOut = graph()
    signedOut.accountSelected = false
    #expect(signedOut.firstStop == .addAccount)
    #expect(signedOut.keeps(.addAccount))
    #expect(!signedOut.keeps(.console(first)))
    #expect(graph().keeps(.profile))
    #expect(!graph(consoles: [first]).keeps(.console(second)))
}
