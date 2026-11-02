/// The window of dots the page indicator shows around the shown page.
public enum CloudPageDots {
    /// The most dots shown at once.
    public static let window = 7

    /// The dots around a page, tapering towards pages hidden beyond the window.
    ///
    /// - Parameters:
    ///   - page: The shown page.
    ///   - count: The pages in the listing.
    /// - Returns: The dots, or none for a single page.
    public static func dots(page: Int, count: Int) -> [CloudPageDot] {
        guard count > 1 else {
            return []
        }
        let current = min(max(0, page), count - 1)
        let shown = min(window, count)
        let start = min(max(0, current - window / 2), count - shown)
        let hiddenBefore = start > 0
        let hiddenAfter = start + shown < count
        return (0..<shown).map { position in
            let shownPage = start + position
            guard shownPage != current else {
                return CloudPageDot(page: shownPage, size: .now)
            }
            let before = hiddenBefore
                ? position
                : CloudPageDot.Size.full.rawValue
            let after = hiddenAfter
                ? shown - 1 - position
                : CloudPageDot.Size.full.rawValue
            let rank = min(before, after, CloudPageDot.Size.full.rawValue)
            return CloudPageDot(page: shownPage, size: CloudPageDot.Size(rawValue: rank) ?? .full)
        }
    }
}

/// One dot of the cloud grid's page indicator.
public struct CloudPageDot: Equatable, Sendable {
    /// How large a dot is drawn, smallest first.
    public enum Size: Int, Equatable, Sendable {
        /// The outermost dot beside hidden pages.
        case edge
        /// The second dot from hidden pages.
        case far
        /// The third dot from hidden pages.
        case near
        /// A dot with no hidden pages close by.
        case full
        /// The shown page.
        case now
    }

    /// The page the dot stands for.
    public let page: Int
    /// How large the dot is drawn.
    public let size: Size

    /// Creates a dot.
    ///
    /// - Parameters:
    ///   - page: The page the dot stands for.
    ///   - size: How large the dot is drawn.
    public init(page: Int, size: Size) {
        self.page = page
        self.size = size
    }
}
