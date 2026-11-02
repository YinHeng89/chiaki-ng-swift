@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import SwiftUI
import Testing
import MenuFocus

private let joinStops: [ConsoleLibraryFocus] = KakusanBuild.included
    ? [.joinGame]
    : []

private let afterSections: ConsoleLibraryFocus = KakusanBuild.included
    ? .joinGame
    : .notifications

@Test func railListsSectionsThenJoinThenNotificationsThenSettingsAccountAndQuit() {
    let rail = LibraryRail(sections: [.consoles, .cloud], showsQuit: true)
    #expect(rail.stops == [.librarySection(.consoles), .librarySection(.cloud)] + joinStops + [
        .notifications, .settings, .profile, .quit
    ])
    #expect(LibraryRail(sections: [.consoles], showsQuit: false).stops == [.librarySection(.consoles)]
        + joinStops + [.notifications, .settings, .profile])
}

@Test func railMovesVerticallyWithoutWrapping() {
    let rail = LibraryRail(sections: [.consoles, .cloud], showsQuit: true)
    #expect(rail.move(from: .librarySection(.consoles), .down) == .stop(.librarySection(.cloud)))
    #expect(rail.move(from: .librarySection(.cloud), .down) == .stop(afterSections))
    if KakusanBuild.included {
        #expect(rail.move(from: .joinGame, .down) == .stop(.notifications))
        #expect(rail.move(from: .notifications, .up) == .stop(.joinGame))
    } else {
        #expect(rail.move(from: .notifications, .up) == .stop(.librarySection(.cloud)))
    }
    #expect(rail.move(from: .notifications, .down) == .stop(.settings))
    #expect(rail.move(from: .profile, .down) == .stop(.quit))
    #expect(rail.move(from: .quit, .down) == .stay)
    #expect(rail.move(from: .settings, .up) == .stop(.notifications))
    #expect(rail.move(from: .librarySection(.consoles), .up) == .stay)
}

@Test func railRightEntersTheContentAndLeftStays() {
    let rail = LibraryRail(sections: [.consoles, .cloud], showsQuit: false)
    for stop in rail.stops {
        #expect(rail.move(from: stop, .right) == .content)
        #expect(rail.move(from: stop, .left) == .stay)
    }
}

@Test func railSkipsAnUnavailableSection() {
    let rail = LibraryRail(sections: [.consoles, .cloud], unavailableSections: [.cloud], showsQuit: false)
    #expect(rail.stops.contains(.librarySection(.cloud)))
    #expect(rail.move(from: .librarySection(.consoles), .down) == .stop(afterSections))
    #expect(rail.move(from: afterSections, .up) == .stop(.librarySection(.consoles)))
    #expect(rail.entry(for: .cloud) == .librarySection(.consoles))
}

@Test func railEntersAtTheShownSection() {
    let rail = LibraryRail(sections: [.consoles, .cloud], showsQuit: false)
    #expect(rail.entry(for: .consoles) == .librarySection(.consoles))
    #expect(rail.entry(for: .cloud) == .librarySection(.cloud))
    #expect(LibraryRail(sections: [.cloud], showsQuit: false)
        .entry(for: .consoles) == .librarySection(.cloud))
}

@Test func railTellsItsStopsFromContent() {
    let rail = LibraryRail(sections: [.consoles, .cloud], showsQuit: true)
    #expect(rail.contains(.settings))
    #expect(rail.contains(.quit))
    #expect(!rail.contains(.addConsole))
    #expect(!rail.contains(nil))
    #expect(!LibraryRail(sections: [.consoles], showsQuit: false).contains(.quit))
}

@Test func accountSheetMovesBetweenAccountsAndActions() {
    let first = UUID()
    let second = UUID()
    let rows: [[LibraryAccountSheet.Focus]] = [
        [.account(first), .account(second), .add],
        [.refresh, .signIn, .delete]
    ]
    #expect(LibraryAccountSheet.move(from: .account(first), in: rows, .right) == .account(second))
    #expect(LibraryAccountSheet.move(from: .add, in: rows, .right) == nil)
    #expect(LibraryAccountSheet.move(from: .account(first), in: rows, .left) == nil)
    #expect(LibraryAccountSheet.move(from: .account(second), in: rows, .down) == .signIn)
    #expect(LibraryAccountSheet.move(from: .add, in: rows, .down) == .delete)
    #expect(LibraryAccountSheet.move(from: .delete, in: rows, .up) == .add)
    #expect(LibraryAccountSheet.move(from: .refresh, in: rows, .down) == nil)
    #expect(LibraryAccountSheet.move(from: .account(first), in: rows, .up) == nil)
}

@Test func accountSheetWithoutActionsKeepsFocusOnTheAccounts() {
    let only = UUID()
    let rows: [[LibraryAccountSheet.Focus]] = [[.account(only), .add], []]
    #expect(LibraryAccountSheet.move(from: .account(only), in: rows, .down) == nil)
    #expect(LibraryAccountSheet.move(from: .add, in: rows, .left) == .account(only))
}

private struct EdgeMoves {
    let edge: LibraryRailEdge
    let forward: MenuMoveDirection
    let toward: MenuMoveDirection
    let away: MenuMoveDirection
}

@Test func eachEdgeMovesAlongItsOwnAxisAndBackTowardTheContent() {
    let expectations = [
        EdgeMoves(edge: .left, forward: .down, toward: .right, away: .left),
        EdgeMoves(edge: .right, forward: .down, toward: .left, away: .right),
        EdgeMoves(edge: .top, forward: .right, toward: .down, away: .up),
        EdgeMoves(edge: .bottom, forward: .right, toward: .up, away: .down)
    ]
    for moves in expectations {
        let rail = LibraryRail(edge: moves.edge, sections: [.consoles, .cloud], showsQuit: false)
        #expect(rail.move(from: .librarySection(.consoles), moves.forward) == .stop(.librarySection(.cloud)))
        #expect(rail.move(from: .settings, moves.toward) == .content)
        #expect(rail.move(from: .settings, moves.away) == .stay)
        #expect(rail.entered(leaving: moves.away))
        #expect(!rail.entered(leaving: moves.toward))
    }
}

@Test func aHorizontalRailIgnoresVerticalMovesAlongItself() {
    let rail = LibraryRail(edge: .top, sections: [.consoles, .cloud], showsQuit: false)
    #expect(rail.move(from: .librarySection(.cloud), .left) == .stop(.librarySection(.consoles)))
    #expect(rail.move(from: .librarySection(.cloud), .up) == .stay)
}

@Test func interfaceSettingsDefaultToTheLeftAndSurviveUnknownEdges() throws {
    #expect(InterfaceSettings().railEdge == .left)
    let decoded = try JSONDecoder().decode(
        InterfaceSettings.self,
        from: Data(#"{"railEdge":"diagonal"}"#.utf8)
    )
    #expect(decoded.railEdge == .left)
    let saved = try JSONDecoder().decode(
        InterfaceSettings.self,
        from: JSONEncoder().encode(InterfaceSettings(railEdge: .bottom))
    )
    #expect(saved.railEdge == .bottom)
}

@Test func railPutsTheLiveLogAfterSettingsWhenItIsTurnedOn() {
    #expect(LibraryRail(sections: [.consoles], showsQuit: true, showsLog: true).stops == [
        .librarySection(.consoles)
    ] + joinStops + [.notifications, .settings, .log, .profile, .quit])
    #expect(!LibraryRail(sections: [.consoles], showsQuit: true).stops.contains(.log))
}

@Test func theNotificationsPanelMovesByRowsWithRefreshAndClearOnTop() {
    let rows: [[PSNAlertsPanel.Focus]] = [
        [.refresh, .clearAll], [.mute("a")], [.invitations], [.messages], [.unmute("Pest")]
    ]
    #expect(PSNAlertsPanel.move(from: .refresh, in: rows, .right) == .clearAll)
    #expect(PSNAlertsPanel.move(from: .clearAll, in: rows, .right) == nil)
    #expect(PSNAlertsPanel.move(from: .clearAll, in: rows, .down) == .mute("a"))
    #expect(PSNAlertsPanel.move(from: .mute("a"), in: rows, .up) == .refresh)
    #expect(PSNAlertsPanel.move(from: .messages, in: rows, .down) == .unmute("Pest"))
    #expect(PSNAlertsPanel.move(from: .unmute("Pest"), in: rows, .down) == nil)
    #expect(PSNAlertsPanel.move(from: .refresh, in: rows, .up) == nil)
    #expect(PSNAlertsPanel.move(from: .invitations, in: rows, .left) == nil)
}

@Test func theCompactHeaderBellSitsBetweenJoinAndTheTabs() {
    let header = ConsoleShelfHeaderFocus(
        sections: [.consoles, .cloud],
        section: .consoles,
        cloudUnavailable: false,
        hasStatusAction: false,
        compact: true,
        tabCenters: [:],
        barAddConsole: false
    )
    #expect(header.moveJoin(.right) == .focus(.notifications))
    #expect(header.moveNotifications(.left) == (KakusanBuild.included
            ? .focus(.joinGame)
            : .stay))
    #expect(header.moveNotifications(.right) == .focus(.librarySection(.consoles)))
    #expect(header.beforeSections == .notifications)
}
