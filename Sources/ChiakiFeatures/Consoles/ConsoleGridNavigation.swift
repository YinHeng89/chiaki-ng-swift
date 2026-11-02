import SwiftUI
import MenuFocus

/// Where a controller move from a card of the console grid lands.
enum ConsoleGridNavigation: Equatable {
    /// The card at this index.
    case console(Int)
    /// Outside the grid.
    case outside

    /// The card a move reaches from a card, by row and column.
    ///
    /// - Parameters:
    ///   - index: The index of the card focus leaves.
    ///   - count: The number of cards.
    ///   - columns: The number of columns.
    ///   - direction: The direction of the move.
    /// - Returns: The neighbouring card, or outside at the grid's edge.
    static func from(_ index: Int, count: Int, columns: Int, _ direction: MenuMoveDirection) -> Self {
        let column = index % columns
        switch direction {
        case .left:
            return column > 0
                ? .console(index - 1)
                : .outside
        case .right:
            return column < columns - 1 && index + 1 < count
                ? .console(index + 1)
                : .outside
        case .up:
            return index >= columns
                ? .console(index - columns)
                : .outside
        case .down:
            return index + columns < count
                ? .console(index + columns)
                : .outside
        @unknown default:
            return .outside
        }
    }

    /// The stop a move reaches from a card's Play or continue button.
    ///
    /// - Parameters:
    ///   - origin: The card focus leaves, and whether its continue button held focus.
    ///   - count: The number of cards.
    ///   - columns: The number of columns.
    ///   - direction: The direction of the move.
    ///   - continues: Whether the card at an index shows a continue button.
    /// - Returns: The continue button of the target card when moving left onto it, or vertically from a
    ///   continue
    ///   button; its Play button otherwise; outside at the grid's edge.
    static func stop(
        from origin: ConsoleGridOrigin, count: Int, columns: Int, _ direction: MenuMoveDirection,
        continues: (Int) -> Bool
    ) -> ConsoleGridStop {
        guard case .console(let target) = from(origin.index, count: count, columns: columns, direction) else {
            return .outside
        }
        switch direction {
        case .left:
            return continues(target)
                ? .resume(target)
                : .play(target)
        case .up, .down:
            return origin.onContinue && continues(target)
                ? .resume(target)
                : .play(target)
        default:
            return .play(target)
        }
    }

    /// The library focus of the landing card.
    ///
    /// - Parameter consoles: The cards of the grid.
    /// - Returns: The card's Play button, or `nil` outside the grid.
    func focus(in consoles: [DisplayedConsole]) -> ConsoleLibraryFocus? {
        switch self {
        case .console(let index):
            .console(consoles[index])
        case .outside:
            nil
        }
    }
}

/// The button of a grid card that a controller move lands on.
enum ConsoleGridStop: Equatable {
    /// The Play button of the card at this index.
    case play(Int)
    /// The continue button of the card at this index.
    case resume(Int)
    /// Outside the grid.
    case outside

    /// The library focus of the landing button.
    ///
    /// - Parameter consoles: The cards of the grid.
    /// - Returns: The button's focus, or `nil` outside the grid.
    func focus(in consoles: [DisplayedConsole]) -> ConsoleLibraryFocus? {
        switch self {
        case .play(let index):
            .console(consoles[index])
        case .resume(let index):
            .action(consoles[index], .resume)
        case .outside:
            nil
        }
    }
}

/// The card a controller move leaves.
struct ConsoleGridOrigin: Equatable {
    /// The index of the card.
    let index: Int
    /// Whether the card's continue button held focus.
    let onContinue: Bool
}
