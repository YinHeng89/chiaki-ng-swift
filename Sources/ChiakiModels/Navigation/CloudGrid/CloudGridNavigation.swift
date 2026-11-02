/// Where each direction moves focus among the cards of one page of the cloud grid.
public struct CloudGridNavigation: Equatable, Sendable {
    /// The page's columns and rows.
    public let shape: CloudGridShape
    /// The cards on the page.
    public let count: Int
    /// The page shown.
    public let page: Int
    /// The pages in the listing.
    public let pageCount: Int

    /// Creates the navigation of a page.
    ///
    /// - Parameters:
    ///   - shape: The page's columns and rows.
    ///   - count: The cards on the page.
    ///   - page: The page shown.
    ///   - pageCount: The pages in the listing.
    public init(shape: CloudGridShape, count: Int, page: Int, pageCount: Int) {
        self.shape = shape
        self.count = count
        self.page = page
        self.pageCount = pageCount
    }

    /// Where a move from a card lands.
    ///
    /// - Parameters:
    ///   - index: The focused card's index on the page.
    ///   - move: The direction pressed.
    /// - Returns: The stop focus moves to.
    public func stop(from index: Int, _ move: CloudGridMove) -> CloudGridStop {
        guard (0..<count).contains(index) else {
            return .stay
        }
        let column = index % shape.columns
        let row = index / shape.columns
        switch move {
        case .left:
            if column > 0 {
                return .card(index - 1)
            }
            return page > 0
                ? .turn(forward: false, row: row)
                : .edge(.left)
        case .right:
            if column + 1 < shape.columns, index + 1 < count {
                return .card(index + 1)
            }
            return page + 1 < pageCount
                ? .turn(forward: true, row: row)
                : .edge(.right)
        case .up:
            return row > 0
                ? .card(index - shape.columns)
                : .header
        case .down:
            if index + shape.columns < count {
                return .card(index + shape.columns)
            }
            if (row + 1) * shape.columns < count {
                return .card(count - 1)
            }
            return pageCount > 1
                ? .pageBar
                : .edge(.down)
        }
    }

    /// The card focus lands on after a page turn.
    ///
    /// - Parameters:
    ///   - row: The row focus left from.
    ///   - forward: Whether the page turned forward, landing on the row's first card, or back, on its last.
    ///   - shape: The new page's columns and rows.
    ///   - count: The cards on the new page.
    /// - Returns: The card's index, or `nil` for an empty page.
    public static func landing(row: Int, forward: Bool, shape: CloudGridShape, count: Int) -> Int? {
        guard count > 0 else {
            return nil
        }
        let lastRow = (count - 1) / shape.columns
        let start = min(max(0, row), lastRow) * shape.columns
        return forward
            ? start
            : min(start + shape.columns - 1, count - 1)
    }
}

/// A direction focus moves in on the cloud grid.
public enum CloudGridMove: Equatable, Sendable {
    /// Towards the previous card in the row.
    case left
    /// Towards the next card in the row.
    case right
    /// Towards the row above.
    case up
    /// Towards the row below.
    case down
}

/// Where a move on the cloud grid lands.
public enum CloudGridStop: Equatable, Sendable {
    /// The card at this index of the page.
    case card(Int)
    /// The neighbouring page, landing on this row.
    case turn(forward: Bool, row: Int)
    /// The header controls above the grid.
    case header
    /// The page bar below the grid.
    case pageBar
    /// Out of the grid in this direction.
    case edge(CloudGridMove)
    /// Focus stays.
    case stay
}
