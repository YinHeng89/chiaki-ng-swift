/// The tab the cloud library grid shows.
public enum CloudLibraryFilter: CaseIterable, Hashable, Sendable {
    /// Games played recently, most recent first.
    case recent
    /// Every game that can be streamed.
    case all
    /// PS5 games the account owns.
    case owned
    /// Games in the PlayStation Plus catalog.
    case plus
    /// Games that can be bought in the store.
    case browse
    /// Pre-ordered and unreleased games, which no other tab lists until they unlock.
    case preorders

    /// The tab's title.
    public var title: String {
        switch self {
        case .recent:
            "Recently played"
        case .all:
            "All streamable"
        case .owned:
            "My library"
        case .plus:
            "PlayStation Plus"
        case .browse:
            "Available to buy"
        case .preorders:
            "Pre-orders"
        }
    }
}

/// The platform the cloud library grid is narrowed to.
public enum CloudPlatformFilter: CaseIterable, Hashable, Sendable {
    /// Every platform.
    case all
    /// PlayStation 5 games.
    case ps5
    /// PlayStation 4 games.
    case ps4
    /// PlayStation 3 games.
    case ps3

    /// The chip's title, such as `"PS5"`.
    public var title: String {
        switch self {
        case .all:
            "All"
        case .ps5:
            "PS5"
        case .ps4:
            "PS4"
        case .ps3:
            "PS3"
        }
    }

    /// The name read by VoiceOver.
    public var spokenTitle: String {
        self == .all
            ? "All platforms"
            : title
    }

    /// Tells whether a game of a platform passes the filter.
    ///
    /// - Parameter platform: The catalog's platform text, such as `"PS5"`; compared without case.
    /// - Returns: Whether the game is shown.
    public func admits(_ platform: String) -> Bool {
        self == .all || platform.caseInsensitiveCompare(title) == .orderedSame
    }
}
