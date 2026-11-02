import CoreGraphics

/// The cloud grid's spacing and card limits, and the fitting of the grid to an area.
public enum CloudGridMetrics {
    /// The usual gap between two columns.
    public static let columnSpacing: CGFloat = 20
    /// The gap between two rows.
    public static let rowSpacing: CGFloat = 26
    /// The narrowest card a full grid uses.
    public static let minimumCard: CGFloat = 190
    /// The widest card before the grid adds a column.
    public static let maximumCard: CGFloat = 280
    /// The widest card a grid grown to fill its area uses.
    public static let largestCard: CGFloat = 360
    /// The widest column gap a single grown row accepts.
    public static let widestGap: CGFloat = 48
    /// The narrowest card a single squeezed row uses.
    public static let smallestCard: CGFloat = 96
    /// The narrowest card a grid tightened to fit another row uses.
    public static let tightestCard: CGFloat = 160
    /// The share of a row left unused that makes the grid tighten to fit another row.
    public static let wastedRow: CGFloat = 0.45
    /// The share of a row left unused that makes the grid grow its cards.
    public static let slackRow: CGFloat = 0.15
    /// A cover's width over its height.
    public static let coverAspect: CGFloat = 0.75
    /// The height of a card's caption.
    public static let caption: CGFloat = 62

    /// Fits a full grid to an area.
    ///
    /// - Parameter area: The area the grid fills.
    /// - Returns: The shape and card width that use the area best.
    public static func fit(_ area: CGSize) -> CloudGridFit {
        guard area.width > 0, area.height > 0, area.width.isFinite, area.height.isFinite else {
            return CloudGridFit(shape: .unmeasured, cardWidth: minimumCard)
        }
        let columns = columns(of: minimumCard, in: area.width)
        let width = min(maximumCard, (area.width - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns))
        let height = width / coverAspect + caption
        let rows = Int((area.height + rowSpacing) / (height + rowSpacing))
        let taller = CGFloat(rows + 1)
        let tighter = ((area.height - rowSpacing * CGFloat(rows)) / taller - caption) * coverAspect
        let unused = area.height - CGFloat(rows) * height - CGFloat(max(0, rows - 1)) * rowSpacing
        if rows >= 1, unused >= height * wastedRow, tighter >= tightestCard {
            return CloudGridFit(
                shape: CloudGridShape(columns: Self.columns(of: tighter, in: area.width), rows: rows + 1),
                cardWidth: tighter
            )
        }
        guard rows < 1 else {
            return grown(area, rows: rows, width: width, unused: unused, height: height)
                ?? CloudGridFit(shape: CloudGridShape(columns: columns, rows: rows), cardWidth: width)
        }
        let squeezed = max(smallestCard, (area.height - caption) * coverAspect)
        return CloudGridFit(
            shape: CloudGridShape(columns: Self.columns(of: squeezed, in: area.width), rows: 1),
            cardWidth: squeezed
        )
    }

    /// Fits a single row of cards to an area.
    ///
    /// - Parameter area: The area the row fills.
    /// - Returns: One row of cards as tall as the area allows.
    public static func row(_ area: CGSize) -> CloudGridFit {
        guard area.width > 0, area.height > 0, area.width.isFinite, area.height.isFinite else {
            return CloudGridFit(shape: CloudGridShape(columns: 5, rows: 1), cardWidth: tightestCard)
        }
        let width = min(maximumCard, max(smallestCard, (area.height - caption) * coverAspect))
        return CloudGridFit(
            shape: CloudGridShape(columns: columns(of: width, in: area.width), rows: 1),
            cardWidth: width
        )
    }

    private static func grown(
        _ area: CGSize, rows: Int, width: CGFloat, unused: CGFloat, height: CGFloat
    ) -> CloudGridFit? {
        guard unused >= height * slackRow else {
            return nil
        }
        let rowHeight = (area.height - rowSpacing * CGFloat(rows - 1)) / CGFloat(rows)
        let tallest = min(largestCard, (rowHeight - caption) * coverAspect)
        guard tallest > width else {
            return nil
        }
        let ratio = (area.width + columnSpacing) / (tallest + columnSpacing)
        let nearest = max(1, Int(ratio.rounded()))
        let nearestCard = min(tallest, (area.width - columnSpacing * CGFloat(nearest - 1)) / CGFloat(nearest))
        let nearestGap = nearest > 1
            ? (area.width - nearestCard * CGFloat(nearest)) / CGFloat(nearest - 1)
            : columnSpacing
        if rows == 1, nearestGap <= widestGap, nearestCard > width {
            return CloudGridFit(
                shape: CloudGridShape(columns: nearest, rows: rows),
                cardWidth: nearestCard,
                columnGap: nearestGap
            )
        }
        let columns = max(1, Int(ratio.rounded(.up)))
        let fitted = (area.width - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        guard fitted > width else {
            return nil
        }
        return CloudGridFit(shape: CloudGridShape(columns: columns, rows: rows), cardWidth: fitted)
    }

    private static func columns(of card: CGFloat, in width: CGFloat) -> Int {
        max(1, Int((width + columnSpacing) / (card + columnSpacing)))
    }
}

/// The cloud grid fitted to an area: its shape, the card width and the gap between columns.
public struct CloudGridFit: Equatable, Sendable {
    /// The columns and rows of one page.
    public let shape: CloudGridShape
    /// The width of one card.
    public let cardWidth: CGFloat
    /// The gap between two columns.
    public var columnGap = CloudGridMetrics.columnSpacing

    /// Creates a fit.
    ///
    /// - Parameters:
    ///   - shape: The columns and rows of one page.
    ///   - cardWidth: The width of one card.
    ///   - columnGap: The gap between two columns.
    public init(
        shape: CloudGridShape,
        cardWidth: CGFloat,
        columnGap: CGFloat = CloudGridMetrics.columnSpacing
    ) {
        self.shape = shape
        self.cardWidth = cardWidth
        self.columnGap = columnGap
    }

    /// The height of a card's cover.
    public var coverHeight: CGFloat {
        cardWidth / CloudGridMetrics.coverAspect
    }

    /// The height of a card, cover and caption.
    public var cardHeight: CGFloat {
        coverHeight + CloudGridMetrics.caption
    }

    /// The size of one full page of cards.
    public var contentSize: CGSize {
        CGSize(
            width: CGFloat(shape.columns) * cardWidth
                + CGFloat(shape.columns - 1) * columnGap,
            height: CGFloat(shape.rows) * cardHeight + CGFloat(shape.rows - 1) * CloudGridMetrics.rowSpacing
        )
    }
}

/// How many columns and rows of game cards one page of the cloud grid holds.
public struct CloudGridShape: Equatable, Sendable {
    /// The shape used before the grid is measured.
    public static let unmeasured = CloudGridShape(columns: 8, rows: 5)

    /// The cards in one row, at least one.
    public let columns: Int
    /// The rows on one page, at least one.
    public let rows: Int

    /// Creates a shape.
    ///
    /// - Parameters:
    ///   - columns: The cards in one row; raised to one.
    ///   - rows: The rows on one page; raised to one.
    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    /// The cards on one page.
    public var size: Int {
        columns * rows
    }
}
