import MenuFocus

/// Moves focus through stops laid out in rows, as the Notifications panel and its conversation views lay them
/// out: Left and Right along a row, Up and Down between rows keeping the column where they can, stopping at
/// every edge.
enum FocusRows {
    /// The stop a direction moves focus to.
    ///
    /// - Parameters:
    ///   - current: The focused stop.
    ///   - rows: The stops, row by row.
    ///   - direction: The direction pressed.
    /// - Returns: The next stop, or `nil` when focus stays.
    static func move<Stop: Hashable>(
        from current: Stop,
        in rows: [[Stop]],
        _ direction: MenuMoveDirection
    ) -> Stop? {
        guard let row = rows.firstIndex(where: { $0.contains(current) }),
              let column = rows[row].firstIndex(of: current) else {
            return nil
        }
        switch direction {
        case .left, .right:
            let next = column + (direction == .left
                ? -1
                : 1)
            return rows[row].indices.contains(next)
                ? rows[row][next]
                : nil
        case .up, .down:
            let next = row + (direction == .up
                ? -1
                : 1)
            guard rows.indices.contains(next), !rows[next].isEmpty else {
                return nil
            }
            return rows[next][min(column, rows[next].count - 1)]
        @unknown default:
            return nil
        }
    }
}
