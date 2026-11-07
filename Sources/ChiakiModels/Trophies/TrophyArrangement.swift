import Foundation

/// Which games the trophy list shows, by how far the player has got.
public enum TrophyTitleFilter: CaseIterable, Hashable, Sendable {
    /// Every game.
    case all
    /// Games with some trophies earned but not every one.
    case inProgress
    /// Games with every trophy earned.
    case completed
    /// Games with no trophy earned yet.
    case notStarted

    /// The choice's label.
    public var name: LocalizedStringResource {
        switch self {
        case .all:
            .trophiesTitleFilterAll
        case .inProgress:
            .trophiesTitleFilterInProgress
        case .completed:
            .trophiesTitleFilterCompleted
        case .notStarted:
            .trophiesTitleFilterNotStarted
        }
    }

    /// Whether a game belongs to the choice.
    ///
    /// - Parameter title: The game.
    /// - Returns: True when the game's progress matches.
    public func includes(_ title: TrophyTitle) -> Bool {
        switch self {
        case .all:
            true
        case .inProgress:
            title.progress < 100 && (title.progress > 0 || title.earned.total > 0)
        case .completed:
            title.progress >= 100
        case .notStarted:
            title.progress == 0 && title.earned.total == 0
        }
    }
}

/// The order of the games in the trophy list.
public enum TrophyTitleSort: CaseIterable, Hashable, Sendable {
    /// The most recently updated first, as PSN lists them.
    case recent
    /// The most complete first.
    case progress
    /// Alphabetical by name.
    case name

    /// The choice's label.
    public var name: LocalizedStringResource {
        switch self {
        case .recent:
            .trophiesTitleSortRecent
        case .progress:
            .trophiesTitleSortProgress
        case .name:
            .trophiesTitleSortName
        }
    }
}

/// Which of a game's trophies are shown, by whether they are earned.
public enum TrophyFilter: CaseIterable, Hashable, Sendable {
    /// Every trophy.
    case all
    /// Only the trophies earned.
    case earned
    /// Only the trophies not earned yet.
    case unearned

    /// The choice's label.
    public var name: LocalizedStringResource {
        switch self {
        case .all:
            .trophiesFilterAll
        case .earned:
            .trophiesFilterEarned
        case .unearned:
            .trophiesFilterNotEarned
        }
    }

    /// Whether a trophy belongs to the choice.
    ///
    /// - Parameter trophy: The trophy.
    /// - Returns: True when its earned state matches.
    public func includes(_ trophy: PSNTrophy) -> Bool {
        switch self {
        case .all:
            true
        case .earned:
            trophy.earned
        case .unearned:
            !trophy.earned
        }
    }
}

/// The order of a game's trophies.
public enum TrophySort: CaseIterable, Hashable, Sendable {
    /// The game's own order.
    case game
    /// Platinum first, then gold, silver and bronze.
    case grade
    /// The rarest first, by the share of players who earned it.
    case rarity
    /// The most recently earned first, then those not earned yet.
    case recentlyEarned
    /// Alphabetical by name.
    case name

    /// The choice's label.
    public var name: LocalizedStringResource {
        switch self {
        case .game:
            .trophiesSortDefaultOrder
        case .grade:
            .trophiesSortGrade
        case .rarity:
            .trophiesSortRarity
        case .recentlyEarned:
            .trophiesSortRecentlyEarned
        case .name:
            .trophiesSortName
        }
    }
}

/// Whether a sort runs in its own order or the opposite one.
public enum TrophySortDirection: Hashable, Sendable {
    /// The sort's own order, such as the highest progress first.
    case standard
    /// The opposite order, such as the lowest progress first.
    case reversed

    /// The other direction.
    public var flipped: Self {
        switch self {
        case .standard:
            .reversed
        case .reversed:
            .standard
        }
    }
}

/// Filters, sorts and searches trophy lists, keeping each list's own order wherever a choice ties.
public enum TrophyArrangement {
    /// The games a list shows.
    ///
    /// - Parameters:
    ///   - titles: The games, most recently updated first.
    ///   - filter: Which games to keep.
    ///   - sort: Their order.
    ///   - query: Text a game's name must contain, ignoring case and accents; blank keeps every game.
    ///   - direction: Whether the order runs as the sort has it or the other way round.
    /// - Returns: The games shown, in order.
    public static func titles(
        _ titles: [TrophyTitle],
        filter: TrophyTitleFilter,
        sort: TrophyTitleSort,
        query: String,
        direction: TrophySortDirection = .standard
    ) -> [TrophyTitle] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = titles.filter { title in
            filter.includes(title) && (text.isEmpty || title.name.localizedStandardContains(text))
        }
        return directed(sorted(kept, by: sort), direction)
    }

    private static func sorted(_ kept: [TrophyTitle], by sort: TrophyTitleSort) -> [TrophyTitle] {
        switch sort {
        case .recent:
            return kept
        case .progress:
            return kept.sorted { first, second in
                first.progress > second.progress
            }
        case .name:
            return kept.sorted { first, second in
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }

    /// The trophies a game shows.
    ///
    /// - Parameters:
    ///   - trophies: The trophies, in the game's order.
    ///   - filter: Which trophies to keep.
    ///   - sort: Their order.
    ///   - direction: Whether the order runs as the sort has it or the other way round.
    /// - Returns: The trophies shown, in order.
    public static func trophies(
        _ trophies: [PSNTrophy],
        filter: TrophyFilter,
        sort: TrophySort,
        direction: TrophySortDirection = .standard
    ) -> [PSNTrophy] {
        directed(sorted(trophies.filter(filter.includes), by: sort), direction)
    }

    private static func sorted(_ kept: [PSNTrophy], by sort: TrophySort) -> [PSNTrophy] {
        switch sort {
        case .game:
            return kept
        case .grade:
            return kept.sorted { first, second in
                first.grade > second.grade
            }
        case .rarity:
            return kept.sorted { first, second in
                (first.earnedRate ?? .infinity) < (second.earnedRate ?? .infinity)
            }
        case .recentlyEarned:
            return kept.sorted { first, second in
                (first.earnedAt ?? .distantPast) > (second.earnedAt ?? .distantPast)
            }
        case .name:
            return kept.sorted { first, second in
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }

    private static func directed<Item>(_ items: [Item], _ direction: TrophySortDirection) -> [Item] {
        switch direction {
        case .standard:
            items
        case .reversed:
            items.reversed()
        }
    }
}
