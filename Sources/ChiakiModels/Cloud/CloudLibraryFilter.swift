import Foundation

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
    public var title: LocalizedStringResource {
        switch self {
        case .recent:
            .cloudLibraryFilterRecent
        case .all:
            .cloudLibraryFilterAll
        case .owned:
            .cloudLibraryFilterOwned
        case .plus:
            .cloudLibraryFilterPlus
        case .browse:
            .cloudLibraryFilterBrowse
        case .preorders:
            .cloudLibraryFilterPreorders
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
    public var title: LocalizedStringResource {
        switch self {
        case .all:
            .cloudLibraryPlatformAll
        case .ps5:
            .cloudLibraryPlatformPs5
        case .ps4:
            .cloudLibraryPlatformPs4
        case .ps3:
            .cloudLibraryPlatformPs3
        }
    }

    /// The name read by VoiceOver.
    public var spokenTitle: LocalizedStringResource {
        self == .all
            ? .cloudLibraryPlatformAllSpoken
            : title
    }

    /// Tells whether a game of a platform passes the filter.
    ///
    /// - Parameter platform: The catalog's platform text, such as `"PS5"`; compared without case.
    /// - Returns: Whether the game is shown.
    public func admits(_ platform: String) -> Bool {
        self == .all || platform.caseInsensitiveCompare(catalogPlatform) == .orderedSame
    }

    private var catalogPlatform: String {
        switch self {
        case .all:
            ""
        case .ps5:
            "PS5"
        case .ps4:
            "PS4"
        case .ps3:
            "PS3"
        }
    }
}
