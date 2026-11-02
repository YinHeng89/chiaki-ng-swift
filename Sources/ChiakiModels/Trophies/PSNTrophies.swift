import Foundation

/// A trophy's grade.
public enum TrophyGrade: Int, CaseIterable, Comparable, Sendable {
    /// A bronze trophy.
    case bronze
    /// A silver trophy.
    case silver
    /// A gold trophy.
    case gold
    /// The platinum trophy.
    case platinum

    /// Orders grades from bronze up to platinum.
    ///
    /// - Parameters:
    ///   - lhs: One grade.
    ///   - rhs: The other grade.
    /// - Returns: `true` when `lhs` is the lower grade.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The grade's name, such as "Gold".
    public var name: String {
        switch self {
        case .bronze:
            "Bronze"
        case .silver:
            "Silver"
        case .gold:
            "Gold"
        case .platinum:
            "Platinum"
        }
    }
}

/// How many trophies of each grade.
public struct TrophyCounts: Equatable, Sendable {
    /// Bronze trophies.
    public var bronze: Int
    /// Silver trophies.
    public var silver: Int
    /// Gold trophies.
    public var gold: Int
    /// Platinum trophies.
    public var platinum: Int

    /// Describes counts.
    ///
    /// - Parameters:
    ///   - bronze: Bronze trophies.
    ///   - silver: Silver trophies.
    ///   - gold: Gold trophies.
    ///   - platinum: Platinum trophies.
    public init(bronze: Int = 0, silver: Int = 0, gold: Int = 0, platinum: Int = 0) {
        self.bronze = bronze
        self.silver = silver
        self.gold = gold
        self.platinum = platinum
    }

    /// The count of one grade.
    ///
    /// - Parameter grade: The grade.
    /// - Returns: How many trophies of that grade.
    public subscript(grade: TrophyGrade) -> Int {
        switch grade {
        case .bronze:
            bronze
        case .silver:
            silver
        case .gold:
            gold
        case .platinum:
            platinum
        }
    }

    /// Every trophy counted, of any grade.
    public var total: Int {
        bronze + silver + gold + platinum
    }
}

/// The account's trophy level and what it has earned.
public struct TrophySummary: Equatable, Sendable {
    /// The trophy level, from 1 to 999.
    public var level: Int
    /// The level's tier, from 1 to 10, which picks the level badge.
    public var tier: Int
    /// How far the account is towards the next level, as a percentage.
    public var progress: Int
    /// The trophies earned.
    public var earned: TrophyCounts

    /// Describes a summary.
    ///
    /// - Parameters:
    ///   - level: The trophy level.
    ///   - tier: The level's tier.
    ///   - progress: The percentage towards the next level.
    ///   - earned: The trophies earned.
    public init(level: Int, tier: Int, progress: Int, earned: TrophyCounts) {
        self.level = level
        self.tier = tier
        self.progress = progress
        self.earned = earned
    }
}

/// A platform a trophy list belongs to.
public enum TrophyPlatform: Int, Sendable {
    /// PlayStation 3.
    case ps3
    /// PlayStation 4.
    case ps4
    /// PlayStation 5.
    case ps5
    /// PlayStation Vita.
    case psVita
    /// A PC release.
    case windows

    /// The platform's short name, such as "PS5".
    public var name: String {
        switch self {
        case .ps3:
            "PS3"
        case .ps4:
            "PS4"
        case .ps5:
            "PS5"
        case .psVita:
            "PS Vita"
        case .windows:
            "PC"
        }
    }
}

/// A game the account has trophies in.
public struct TrophyTitle: Equatable, Identifiable, Sendable {
    /// The trophy set's communication id, such as `NPWR12345_00`.
    public let id: String
    /// The game's name.
    public var name: String
    /// The trophy list's icon, or `nil`.
    public var iconURL: URL?
    /// The platforms the list belongs to.
    public var platforms: [TrophyPlatform]
    /// The trophies the list holds.
    public var defined: TrophyCounts
    /// The trophies the account earned in it.
    public var earned: TrophyCounts
    /// The account's progress through the list, as a percentage.
    public var progress: Int
    /// Whether the account hid the list from its profile.
    public var hidden: Bool
    /// When the account last earned a trophy in it, or `nil`.
    public var updated: Date?

    /// Describes a title.
    ///
    /// - Parameters:
    ///   - id: The trophy set id.
    ///   - name: The game's name.
    ///   - iconURL: The list's icon.
    ///   - platforms: The platforms.
    ///   - defined: The trophies the list holds.
    ///   - earned: The trophies earned.
    ///   - progress: The progress percentage.
    ///   - hidden: Whether the list is hidden.
    ///   - updated: When a trophy was last earned.
    public init(
        id: String,
        name: String,
        iconURL: URL? = nil,
        platforms: [TrophyPlatform] = [],
        defined: TrophyCounts = TrophyCounts(),
        earned: TrophyCounts = TrophyCounts(),
        progress: Int = 0,
        hidden: Bool = false,
        updated: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.platforms = platforms
        self.defined = defined
        self.earned = earned
        self.progress = progress
        self.hidden = hidden
        self.updated = updated
    }
}

/// How rare a trophy is among the players who own the game, in PSN's four bands.
public enum TrophyRarity: Int, Sendable {
    /// Earned by 5% of players or fewer.
    case ultraRare
    /// Earned by up to 15% of players.
    case veryRare
    /// Earned by up to 50% of players.
    case rare
    /// Earned by more than half of players.
    case common

    /// The band's name, such as "Very rare".
    public var name: String {
        switch self {
        case .ultraRare:
            "Ultra rare"
        case .veryRare:
            "Very rare"
        case .rare:
            "Rare"
        case .common:
            "Common"
        }
    }
}

/// A group of a game's trophies: the base game or one add-on.
public struct TrophyGroup: Equatable, Identifiable, Sendable {
    /// The group id, `default` for the base game.
    public let id: String
    /// The group's name.
    public var name: String
    /// The group's icon, or `nil`.
    public var iconURL: URL?
    /// The trophies in the group.
    public var defined: TrophyCounts
    /// The trophies the account earned in the group.
    public var earned: TrophyCounts
    /// The account's progress through the group, as a percentage.
    public var progress: Int

    /// Describes a group.
    ///
    /// - Parameters:
    ///   - id: The group id.
    ///   - name: The group's name.
    ///   - iconURL: The group's icon.
    ///   - defined: The trophies in it.
    ///   - earned: The trophies earned.
    ///   - progress: The progress percentage.
    public init(
        id: String,
        name: String,
        iconURL: URL? = nil,
        defined: TrophyCounts = TrophyCounts(),
        earned: TrophyCounts = TrophyCounts(),
        progress: Int = 0
    ) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.defined = defined
        self.earned = earned
        self.progress = progress
    }
}

/// The account's progress towards a trophy that counts towards a number.
public struct TrophyProgress: Equatable, Sendable {
    /// How far the account has got.
    public var value: Int
    /// The number that earns the trophy.
    public var target: Int

    /// Describes progress.
    ///
    /// - Parameters:
    ///   - value: How far the account has got.
    ///   - target: The number that earns the trophy.
    public init(value: Int, target: Int) {
        self.value = value
        self.target = target
    }
}

/// The trophy set of the game being played and its trophies, as PSN has them at the time of asking.
public struct CurrentTrophies: Equatable, Sendable {
    /// The game's trophy set, with the player's progress in it.
    public var title: TrophyTitle
    /// Its groups and trophies.
    public var trophies: TitleTrophies

    /// Describes a game's current trophies.
    ///
    /// - Parameters:
    ///   - title: The game's trophy set.
    ///   - trophies: Its groups and trophies.
    public init(title: TrophyTitle, trophies: TitleTrophies) {
        self.title = title
        self.trophies = trophies
    }
}

/// One trophy with what the account has earned of it.
public struct PSNTrophy: Equatable, Identifiable, Sendable {
    /// The trophy's number within its list.
    public let id: Int
    /// The group it belongs to.
    public var group: String
    /// Its grade.
    public var grade: TrophyGrade
    /// Its name, which PSN leaves empty for a hidden trophy not yet earned.
    public var name: String
    /// How to earn it.
    public var detail: String
    /// Its icon, or `nil`.
    public var iconURL: URL?
    /// Whether it stays secret until earned.
    public var hidden: Bool
    /// Whether the account earned it.
    public var earned: Bool
    /// When the account earned it, or `nil`.
    public var earnedAt: Date?
    /// How rare it is, or `nil` when PSN did not say.
    public var rarity: TrophyRarity?
    /// The percentage of players who earned it, or `nil`.
    public var earnedRate: Double?
    /// The account's progress towards it, for a trophy that counts towards a number, or `nil`.
    public var progress: TrophyProgress?

    /// Describes a trophy.
    ///
    /// - Parameters:
    ///   - id: The trophy number.
    ///   - group: The group id.
    ///   - grade: The grade.
    ///   - name: The name.
    ///   - detail: How to earn it.
    ///   - iconURL: The icon.
    ///   - hidden: Whether it is secret until earned.
    ///   - earned: Whether it is earned.
    ///   - earnedAt: When it was earned.
    ///   - rarity: How rare it is.
    ///   - earnedRate: The percentage of players who earned it.
    ///   - progress: The progress towards a counted trophy.
    public init(
        id: Int,
        group: String = "default",
        grade: TrophyGrade,
        name: String,
        detail: String = "",
        iconURL: URL? = nil,
        hidden: Bool = false,
        earned: Bool = false,
        earnedAt: Date? = nil,
        rarity: TrophyRarity? = nil,
        earnedRate: Double? = nil,
        progress: TrophyProgress? = nil
    ) {
        self.id = id
        self.group = group
        self.grade = grade
        self.name = name
        self.detail = detail
        self.iconURL = iconURL
        self.hidden = hidden
        self.earned = earned
        self.earnedAt = earnedAt
        self.rarity = rarity
        self.earnedRate = earnedRate
        self.progress = progress
    }
}

/// A game's trophy groups and trophies.
public struct TitleTrophies: Equatable, Sendable {
    /// The groups, base game first.
    public var groups: [TrophyGroup]
    /// The trophies in list order.
    public var trophies: [PSNTrophy]

    /// Describes a game's trophies.
    ///
    /// - Parameters:
    ///   - groups: The groups.
    ///   - trophies: The trophies.
    public init(groups: [TrophyGroup], trophies: [PSNTrophy]) {
        self.groups = groups
        self.trophies = trophies
    }
}

/// Why trophies could not be read.
public enum PSNTrophiesFailure: Error, Equatable, Sendable {
    /// The account has no PSN sign-in.
    case signedOut
    /// PSN refused the account's credentials.
    case auth
    /// PSN asked the app to slow down, or the account's request budget is spent.
    case rateLimited
    /// The game is no longer in the account's trophy list.
    case notFound
    /// PSN could not be reached, rejected the request or gave an unreadable answer.
    case unavailable
    /// The request was cancelled.
    case cancelled
}
