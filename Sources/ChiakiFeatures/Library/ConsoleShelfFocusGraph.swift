import ChiakiModels
import CoreGraphics
import Foundation
import MenuFocus

/// Where a direction moves controller focus on the console shelf, its header and its recently played rows.
///
/// The graph is a pure value built from what the shelf shows; the library view asks it for each move and
/// applies the answer, so the walk is tested without a window.
struct ConsoleShelfFocusGraph {
    /// What a move asks the library to do.
    enum Move: Equatable {
        /// Focus this stop.
        case focus(ConsoleLibraryFocus)
        /// Leave the content towards the rail in this direction, if the rail lies that way.
        case leave(MenuMoveDirection)
        /// Focus the first console, or the stop that stands in for it.
        case firstConsole
        /// Enter the shown section's content.
        case content(LibraryContentFocus)
        /// Keep focus where it is.
        case stay
    }

    /// One row of recently played titles: the console it belongs to and its titles' ids.
    struct RecentRow: Equatable {
        /// The console's id.
        let consoleID: UUID
        /// The ids of the titles shown, in order.
        let titleIDs: [String]
    }

    /// The consoles shown, in order.
    var consoles: [DisplayedConsole] = []
    /// How many console cards one grid row holds.
    var columns = 1
    /// The consoles whose card shows a Continue pill.
    var continuing: Set<DisplayedConsole> = []
    /// The recently played rows shown below the shelf.
    var recentRows: [RecentRow] = []
    /// Whether a status line above the shelf has a button.
    var hasStatusAction = false
    /// Whether the window is compact, with the header bar instead of the rail.
    var compact = false
    /// Whether an account is selected.
    var accountSelected = true
    /// The sections the account can show.
    var sections: [LibrarySection] = LibrarySection.allCases
    /// Whether the cloud section cannot be shown.
    var cloudUnavailable = false
    /// The section shown.
    var section = LibrarySection.consoles
    /// The console the recently played rows were last entered from.
    var recentOrigin: UUID?
    /// The horizontal centre of each section tab in the compact header.
    var tabCenters: [LibrarySection: CGFloat] = [:]

    /// Whether the compact header shows its own Add console button.
    var barAddConsole: Bool {
        compact && section == .consoles && accountSelected && !consoles.isEmpty
    }

    /// How focus moves across the compact header's buttons and section tabs.
    var header: ConsoleShelfHeaderFocus {
        ConsoleShelfHeaderFocus(
            sections: sections,
            section: section,
            cloudUnavailable: cloudUnavailable,
            hasStatusAction: hasStatusAction,
            compact: compact,
            tabCenters: tabCenters,
            barAddConsole: barAddConsole
        )
    }

    /// The stop the shelf focuses first.
    var firstStop: ConsoleLibraryFocus {
        if !accountSelected {
            return .addAccount
        }
        return consoles.first.map(ConsoleLibraryFocus.console) ?? .addConsole
    }

    /// Moves focus from a console card or its Continue pill.
    ///
    /// - Parameters:
    ///   - current: The focused stop.
    ///   - direction: The direction pressed.
    /// - Returns: The move to apply.
    func moveConsole(from current: ConsoleLibraryFocus, _ direction: MenuMoveDirection) -> Move {
        if current == .addConsole {
            return moveAddConsole(direction)
        }
        let item: DisplayedConsole
        let onContinue: Bool
        switch current {
        case .console(let console):
            item = console
            onContinue = false
        case .action(let console, .resume):
            item = console
            onContinue = true
        default:
            return .stay
        }
        guard let index = consoles.firstIndex(of: item) else {
            return .stay
        }
        if let target = ConsoleGridNavigation.stop(
            from: ConsoleGridOrigin(index: index, onContinue: onContinue),
            count: consoles.count,
            columns: columns,
            direction,
            continues: { continuing.contains(consoles[$0]) }
        )
        .focus(in: consoles) {
            return .focus(target)
        }
        switch direction {
        case .up:
            return .focus(
                hasStatusAction
                    ? .statusAction
                    : aboveConsole(at: index)
            )
        case .down:
            return recentStop(below: .console(item)).map(Move.focus) ?? .leave(.down)
        default:
            return .leave(direction)
        }
    }

    /// Moves focus from the status line's button.
    ///
    /// - Parameter direction: The direction pressed.
    /// - Returns: The move to apply.
    func moveStatusAction(_ direction: MenuMoveDirection) -> Move {
        switch direction {
        case .up:
            if !consoles.isEmpty {
                return .focus(.addConsole)
            }
            return compact
                ? .focus(.librarySection(.consoles))
                : .leave(.up)
        case .down:
            return .firstConsole
        case .left, .right:
            return .leave(direction)
        }
    }

    /// Moves focus from a recently played title.
    ///
    /// - Parameters:
    ///   - current: The focused title.
    ///   - direction: The direction pressed.
    /// - Returns: The move to apply.
    func moveRecent(from current: ConsoleLibraryFocus, _ direction: MenuMoveDirection) -> Move {
        guard case let .recentTitle(consoleID, titleID) = current else {
            return .stay
        }
        guard let rowIndex = recentRows.firstIndex(where: { $0.consoleID == consoleID }),
              let index = recentRows[rowIndex].titleIDs.firstIndex(of: titleID) else {
            return .firstConsole
        }
        let titles = recentRows[rowIndex].titleIDs
        switch direction {
        case .left, .right:
            let next = index + (direction == .left
                ? -1
                : 1)
            return titles.indices.contains(next)
                ? .focus(.recentTitle(consoleID, titles[next]))
                : .leave(direction)
        case .up:
            if !compact, rowIndex > 0, !recentRows[rowIndex - 1].titleIDs.isEmpty {
                let above = recentRows[rowIndex - 1]
                return .focus(.recentTitle(
                    above.consoleID,
                    above.titleIDs[min(index, above.titleIDs.count - 1)]
                ))
            }
            return console(consoleID).map { .focus(.console($0)) } ?? .firstConsole
        case .down:
            guard !compact, recentRows.indices.contains(rowIndex + 1),
                  !recentRows[rowIndex + 1].titleIDs.isEmpty else {
                return .leave(.down)
            }
            let below = recentRows[rowIndex + 1]
            return .focus(.recentTitle(below.consoleID, below.titleIDs[min(index, below.titleIDs.count - 1)]))
        }
    }

    /// The stop focus moves to when it leaves the account menu towards the content.
    ///
    /// - Parameters:
    ///   - horizontalPosition: The horizontal centre of the control focus left.
    ///   - waiting: Whether the shelf still waits for the console catalog.
    /// - Returns: The move to apply.
    func trailingContent(horizontalPosition: CGFloat?, waiting: Bool) -> Move {
        guard compact, section == .consoles, accountSelected, consoles.count > 1, !waiting else {
            return .content(LibraryContentFocus(
                .platform,
                horizontalPosition: horizontalPosition.map(Double.init)
            ))
        }
        return .focus(.console(consoles[1]))
    }

    /// Tells whether a stop is still shown, so focus may return to it.
    ///
    /// - Parameter focus: The stop.
    /// - Returns: `true` when the stop is on screen.
    func shows(_ focus: ConsoleLibraryFocus) -> Bool {
        switch focus {
        case .console(let item), .action(let item, _):
            consoles.contains(item)
        case .addConsole:
            accountSelected
        case .addAccount:
            !accountSelected
        case .statusAction:
            hasStatusAction
        case .recentTitle(let consoleID, let titleID):
            recentRows.contains { $0.consoleID == consoleID && $0.titleIDs.contains(titleID) }
        case .profile, .librarySection, .joinGame, .notifications, .settings, .log, .quit:
            false
        }
    }

    /// Tells whether a focused stop still fits the shelf after the shelf changed.
    ///
    /// - Parameter focus: The focused stop.
    /// - Returns: `true` when focus may stay.
    func keeps(_ focus: ConsoleLibraryFocus?) -> Bool {
        guard accountSelected else {
            return focus == .addAccount
        }
        switch focus {
        case .addConsole, .profile, .librarySection, .joinGame, .notifications, .settings, .log, .quit:
            return true
        case .some(let stop):
            return shows(stop)
        case nil:
            return false
        }
    }

    /// The first recently played title below a stop, preferring the row of the console focus came from.
    ///
    /// - Parameter current: The stop focus leaves.
    /// - Returns: The title to focus, or `nil` when no row has titles.
    func recentStop(below current: ConsoleLibraryFocus) -> ConsoleLibraryFocus? {
        let preferred: UUID? =
            if case .console(let item) = current {
                item.target.id
            } else {
                recentOrigin
            }
        let row = recentRows.first { $0.consoleID == preferred } ?? recentRows.first
        guard let row, let title = row.titleIDs.first else {
            return nil
        }
        return .recentTitle(row.consoleID, title)
    }

    private func moveAddConsole(_ direction: MenuMoveDirection) -> Move {
        if barAddConsole {
            switch direction {
            case .left:
                return .focus(.notifications)
            case .right:
                return .focus(.librarySection(sections.first ?? .consoles))
            case .up:
                return .stay
            case .down:
                break
            }
        }
        switch direction {
        case .up:
            if hasStatusAction, consoles.isEmpty {
                return .focus(.statusAction)
            }
            return compact
                ? .focus(.librarySection(.consoles))
                : .leave(.up)
        case .left, .right:
            return .leave(direction)
        case .down:
            if consoles.isEmpty {
                return recentStop(below: .addConsole).map(Move.focus) ?? .leave(.down)
            }
            return .focus(
                hasStatusAction
                    ? .statusAction
                    : .console(consoles[0])
            )
        }
    }

    private func aboveConsole(at index: Int) -> ConsoleLibraryFocus {
        compact && index > 0
            ? .profile
            : .addConsole
    }

    private func console(_ id: UUID) -> DisplayedConsole? {
        consoles.first { $0.target.id == id }
    }
}

/// Where a direction moves controller focus across the compact library header: the Join a game and Add console
/// buttons and the section tabs.
///
/// Moving down from a tab enters the section's content below that tab; moving past the last tab reaches the
/// profile.
struct ConsoleShelfHeaderFocus {
    /// The sections the account can show.
    let sections: [LibrarySection]

    /// The section shown.
    let section: LibrarySection

    /// Whether the cloud section cannot be shown.
    let cloudUnavailable: Bool

    /// Whether a status line above the shelf has a button.
    let hasStatusAction: Bool

    /// Whether the window is compact, with the header bar instead of the rail.
    let compact: Bool

    /// The horizontal centre of each section tab.
    let tabCenters: [LibrarySection: CGFloat]

    /// Whether the header shows its own Add console button.
    let barAddConsole: Bool

    /// The stop left of the section tabs in the compact header.
    var beforeSections: ConsoleLibraryFocus {
        barAddConsole
            ? .addConsole
            : .notifications
    }

    /// Moves focus from a section tab in the compact header.
    ///
    /// - Parameters:
    ///   - current: The focused tab's section.
    ///   - direction: The direction pressed.
    /// - Returns: The move to apply.
    func moveSection(from current: LibrarySection, _ direction: MenuMoveDirection) -> ConsoleShelfFocusGraph
        .Move {
        if direction == .down, current == .consoles, section == .consoles, hasStatusAction {
            return .focus(.statusAction)
        }
        switch direction {
        case .down:
            return .content(LibraryContentFocus(
                current == .cloud
                    ? .browse
                    : .firstFilter,
                horizontalPosition: tabCenters[current].map(Double.init)
            ))
        case .left where current == .consoles:
            return .focus(beforeSections)
        case .up:
            return .stay
        case .left, .right:
            let reachable = sections.filter {
                $0 != .cloud || !cloudUnavailable || $0 == current
            }
            guard let index = reachable.firstIndex(of: current) else {
                return .stay
            }
            let next = index + (direction == .left
                ? -1
                : 1)
            guard reachable.indices.contains(next) else {
                return compact && direction == .right
                    ? .focus(.profile)
                    : .stay
            }
            return .focus(.librarySection(reachable[next]))
        }
    }

    /// Moves focus from the compact header's Join a game button.
    ///
    /// - Parameter direction: The direction pressed.
    /// - Returns: The move to apply.
    func moveJoin(_ direction: MenuMoveDirection) -> ConsoleShelfFocusGraph.Move {
        switch direction {
        case .right:
            return .focus(.notifications)
        case .down:
            return .content(LibraryContentFocus(.selectedFilter))
        default:
            return .stay
        }
    }

    /// Moves focus from the Notifications button in the compact header.
    ///
    /// - Parameter direction: The direction of the move.
    /// - Returns: Join a game to the left when this build has Kakusan; Add console or the first tab to the
    ///   right; the content below.
    func moveNotifications(_ direction: MenuMoveDirection) -> ConsoleShelfFocusGraph.Move {
        switch direction {
        case .left:
            return KakusanBuild.included
                ? .focus(.joinGame)
                : .stay
        case .right:
            return .focus(
                barAddConsole
                    ? .addConsole
                    : .librarySection(sections.first ?? .consoles)
            )
        case .down:
            return .content(LibraryContentFocus(.selectedFilter))
        case .up:
            return .stay
        }
    }
}
