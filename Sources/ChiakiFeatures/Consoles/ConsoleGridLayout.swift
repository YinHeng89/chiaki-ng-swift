import SwiftUI

/// Lays out console cards in rows of one or two equal columns, each row as tall as its tallest card.
public struct ConsoleGridLayout: Layout {
    /// The width from which two or more cards are laid out in two columns.
    public nonisolated static let twoColumnWidth: CGFloat = 1100

    /// The gap between columns and between rows.
    public var spacing: CGFloat = 18

    /// Creates a console grid layout.
    ///
    /// - Parameter spacing: The gap between columns and between rows.
    public init(spacing: CGFloat = 18) {
        self.spacing = spacing
    }

    /// The number of columns for a width.
    ///
    /// - Parameters:
    ///   - width: The width available to the grid.
    ///   - cards: The number of cards.
    /// - Returns: Two from ``twoColumnWidth`` when there is more than one card, otherwise one.
    public nonisolated static func columns(for width: CGFloat, cards: Int = 2) -> Int {
        width >= twoColumnWidth && cards > 1
            ? 2
            : 1
    }

    /// Measures the grid at the proposed width, or at ``twoColumnWidth`` when none is proposed, returning that
    /// width and the height of every row with the gaps between them.
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? Self.twoColumnWidth
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(0) { total, row in
            total + row.height
        } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    /// Places the cards row by row inside the grid's bounds, each in a cell of the column width and the row's
    /// height.
    public func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            for (offset, index) in row.indices.enumerated() {
                let x = bounds.minX + CGFloat(offset) * (row.cellWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: row.cellWidth, height: row.height)
                )
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int]
        var cellWidth: CGFloat
        var height: CGFloat
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        let columns = Self.columns(for: width, cards: subviews.count)
        let cellWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var result = [Row]()
        var pending = [Int]()
        func flush() {
            guard !pending.isEmpty else {
                return
            }
            let height = pending.map { index in
                subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            }.max() ?? 0
            result.append(Row(indices: pending, cellWidth: cellWidth, height: height))
            pending = []
        }
        for index in subviews.indices {
            pending.append(index)
            if pending.count == columns {
                flush()
            }
        }
        flush()
        return result
    }
}
