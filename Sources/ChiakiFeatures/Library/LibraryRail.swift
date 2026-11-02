import ChiakiModels
import SwiftUI
import MenuFocus

/// The library rail's controller focus stops and how directional moves travel along it.
///
/// The section tabs and Join Game sit at the start, then settings, the live log when it is turned on, the
/// profile and, when shown, Quit; moving
/// toward the content leaves the rail and unavailable sections are skipped.
struct LibraryRail: Equatable {
    /// Where a move from a rail stop goes.
    enum Exit: Equatable {
        /// To another stop on the rail.
        case stop(ConsoleLibraryFocus)
        /// Out of the rail into the library content.
        case content
        /// Nowhere; focus stays where it is.
        case stay
    }

    /// The window edge the rail is docked to.
    let edge: LibraryRailEdge
    /// The section tabs followed by Join Game, when this build has Kakusan, and Notifications.
    let leading: [ConsoleLibraryFocus]
    /// Settings, the live log when it is turned on, the profile and, when shown, Quit.
    let trailing: [ConsoleLibraryFocus]
    /// The section stops that cannot be focused.
    let unavailable: Set<ConsoleLibraryFocus>

    /// Builds the rail's stops.
    ///
    /// - Parameters:
    /// - edge: The window edge the rail is docked to; left by default.
    /// - sections: The library sections, in rail order.
    /// - unavailableSections: Sections that are shown but cannot be focused.
    /// - showsQuit: Whether the rail ends with a Quit stop.
    /// - showsLog: Whether the rail has a live log stop after Settings.
    init(
        edge: LibraryRailEdge = .left,
        sections: [LibrarySection],
        unavailableSections: Set<LibrarySection> = [],
        showsQuit: Bool,
        showsLog: Bool = false
    ) {
        self.edge = edge
        leading = sections.map(ConsoleLibraryFocus.librarySection) + (KakusanBuild.included
            ? [.joinGame]
            : []) + [.notifications]
        trailing = [.settings] + (showsLog
            ? [.log]
            : []) + [.profile] + (showsQuit
            ? [.quit]
            : [])
        unavailable = Set(unavailableSections.map(ConsoleLibraryFocus.librarySection))
    }

    /// Every stop, leading then trailing.
    var stops: [ConsoleLibraryFocus] {
        leading + trailing
    }

    /// The direction that leaves the rail for the content, away from the docked edge.
    var towardContent: MenuMoveDirection {
        switch edge {
        case .top:
            .down
        case .left:
            .right
        case .right:
            .left
        case .bottom:
            .up
        }
    }

    /// The direction toward the docked edge, which brings focus from the content into the rail.
    var awayFromContent: MenuMoveDirection {
        switch edge {
        case .top:
            .up
        case .left:
            .left
        case .right:
            .right
        case .bottom:
            .down
        }
    }

    /// Whether a focus target is one of the rail's stops.
    func contains(_ focus: ConsoleLibraryFocus?) -> Bool {
        focus.map(stops.contains) ?? false
    }

    /// Whether a move out of the content in this direction enters the rail.
    func entered(leaving direction: MenuMoveDirection) -> Bool {
        direction == awayFromContent
    }

    /// The stop focus enters the rail on: the selected section when it can be focused, otherwise the first
    /// reachable stop.
    ///
    /// - Parameter section: The selected library section.
    func entry(for section: LibrarySection) -> ConsoleLibraryFocus {
        let selected = ConsoleLibraryFocus.librarySection(section)
        if stops.contains(selected), !unavailable.contains(selected) {
            return selected
        }
        return reachable.first ?? .joinGame
    }

    /// Resolves a directional move from a rail stop.
    ///
    /// Moves along the rail step between reachable stops and stay at the ends; any other direction except
    /// toward the content stays.
    ///
    /// - Parameters:
    /// - current: The focused stop.
    /// - direction: The direction of the move.
    func move(from current: ConsoleLibraryFocus, _ direction: MenuMoveDirection) -> Exit {
        if direction == towardContent {
            return .content
        }
        let backward: MenuMoveDirection = edge.isVertical
            ? .up
            : .left
        let forward: MenuMoveDirection = edge.isVertical
            ? .down
            : .right
        guard direction == backward || direction == forward,
              let index = reachable.firstIndex(of: current) else {
            return .stay
        }
        let next = index + (direction == backward
            ? -1
            : 1)
        return reachable.indices.contains(next)
            ? .stop(reachable[next])
            : .stay
    }

    private var reachable: [ConsoleLibraryFocus] {
        stops.filter { !unavailable.contains($0) }
    }
}
