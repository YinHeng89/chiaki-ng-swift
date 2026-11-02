import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reads an account's trophy level, trophy list and each game's trophies through the open core.
///
/// The core keeps answers for hours and paces requests per account, so repeated reads are usually answered
/// without asking PSN. Each call can block a core thread, so it runs on a dispatch queue while the calling task
/// waits; cancelling the task cancels the core request.
public struct PSNTrophiesBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// The account's trophy level and what it has earned.
    ///
    /// - Parameter account: The account.
    /// - Returns: The summary.
    /// - Throws: The `ChiakiModels/PSNTrophiesFailure` that stopped the read.
    public func summary(account: AccountID) async throws(PSNTrophiesFailure) -> TrophySummary {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.TrophiesBridge.summary(request, UsersBridge.vector(account))
            switch outcome.kind() {
            case .read:
                let facts = outcome.summary()
                return Result<TrophySummary, PSNTrophiesFailure>.success(TrophySummary(
                    level: Int(facts.level),
                    tier: Int(facts.tier),
                    progress: Int(facts.progress),
                    earned: Self.counts(of: facts.earned)
                ))
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// The games the account has trophies in, most recently updated first.
    ///
    /// - Parameter account: The account.
    /// - Returns: The titles.
    /// - Throws: The `ChiakiModels/PSNTrophiesFailure` that stopped the read.
    public func titles(account: AccountID) async throws(PSNTrophiesFailure) -> [TrophyTitle] {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.TrophiesBridge.titles(request, UsersBridge.vector(account))
            switch outcome.kind() {
            case .listed:
                return Result<[TrophyTitle], PSNTrophiesFailure>
                    .success(outcome.titles().map(Self.title(of:)))
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// One game's trophy groups and trophies with what the account earned.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - titleID: The game's trophy set id, from `ChiakiModels/TrophyTitle/id`.
    /// - Returns: The groups and trophies.
    /// - Throws: The `ChiakiModels/PSNTrophiesFailure` that stopped the read, `notFound` when the game left the
    ///   account's list.
    public func trophies(account: AccountID,
                         titleID: String) async throws(PSNTrophiesFailure) -> TitleTrophies {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.TrophiesBridge.trophies(
                request,
                UsersBridge.vector(account),
                std.string(titleID)
            )
            switch outcome.kind() {
            case .read:
                let facts = outcome.trophies()
                return Result<TitleTrophies, PSNTrophiesFailure>.success(TitleTrophies(
                    groups: facts.groups.map(Self.group(of:)),
                    trophies: facts.trophies.map(Self.trophy(of:))
                ))
            case .missing:
                return .failure(.notFound)
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// The trophies of the game being played, as PSN has them now.
    ///
    /// The core always asks PSN for the release's progress and reads the trophies again only when that progress
    /// moved, so a trophy earned a moment ago shows.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - titleID: The release being played, such as `CUSA00341_00`.
    /// - Returns: The game's trophy set and trophies, or `nil` when PSN knows no trophy set for the release.
    /// - Throws: The `ChiakiModels/PSNTrophiesFailure` that stopped the read.
    public func current(account: AccountID,
                        titleID: String) async throws(PSNTrophiesFailure) -> CurrentTrophies? {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.TrophiesBridge.current(
                request,
                UsersBridge.vector(account),
                std.string(titleID)
            )
            switch outcome.kind() {
            case .read:
                let facts = outcome.current()
                return Result<CurrentTrophies?, PSNTrophiesFailure>.success(CurrentTrophies(
                    title: Self.title(of: facts.title),
                    trophies: TitleTrophies(
                        groups: facts.groups.map(Self.group(of:)),
                        trophies: facts.trophies.map(Self.trophy(of:))
                    )
                ))
            case .missing:
                return .success(nil)
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// Forgets what the core keeps for the account, so the next reads ask PSN again.
    ///
    /// - Parameter account: The account.
    public func startOver(account: AccountID) async {
        _ = await CoreCancellation.run(qos: .utility) { _ in
            chiaki_bridge.TrophiesBridge.start_over(UsersBridge.vector(account))
        }
    }

    /// The model counts of the bridge's.
    ///
    /// - Parameter facts: The bridge's counts.
    /// - Returns: The counts.
    static func counts(of facts: chiaki_bridge.TrophyCountsFacts) -> TrophyCounts {
        TrophyCounts(
            bronze: Int(facts.bronze),
            silver: Int(facts.silver),
            gold: Int(facts.gold),
            platinum: Int(facts.platinum)
        )
    }

    /// The model title of the bridge's facts.
    ///
    /// - Parameter facts: The bridge's facts.
    /// - Returns: The title.
    static func title(of facts: chiaki_bridge.TrophyTitleFacts) -> TrophyTitle {
        TrophyTitle(
            id: String(facts.id),
            name: String(facts.name),
            iconURL: url(of: facts.icon_url),
            platforms: facts.platforms.compactMap {
                TrophyPlatform(rawValue: Int($0))
            },
            defined: counts(of: facts.defined),
            earned: counts(of: facts.earned),
            progress: Int(facts.progress),
            hidden: facts.hidden,
            updated: date(of: facts.updated_ms)
        )
    }

    /// The model group of the bridge's facts.
    ///
    /// - Parameter facts: The bridge's facts.
    /// - Returns: The group.
    static func group(of facts: chiaki_bridge.TrophyGroupFacts) -> TrophyGroup {
        TrophyGroup(
            id: String(facts.id),
            name: String(facts.name),
            iconURL: url(of: facts.icon_url),
            defined: counts(of: facts.defined),
            earned: counts(of: facts.earned),
            progress: Int(facts.progress)
        )
    }

    /// The model trophy of the bridge's facts.
    ///
    /// - Parameter facts: The bridge's facts.
    /// - Returns: The trophy.
    static func trophy(of facts: chiaki_bridge.TrophyFacts) -> PSNTrophy {
        PSNTrophy(
            id: Int(facts.id),
            group: String(facts.group),
            grade: TrophyGrade(rawValue: Int(facts.grade)) ?? .bronze,
            name: String(facts.name),
            detail: String(facts.detail),
            iconURL: url(of: facts.icon_url),
            hidden: facts.hidden,
            earned: facts.earned,
            earnedAt: date(of: facts.earned_ms),
            rarity: TrophyRarity(rawValue: Int(facts.rarity)),
            earnedRate: facts.has_earned_rate
                ? facts.earned_rate
                : nil,
            progress: facts.has_progress && facts.progress_target > 0
                ? TrophyProgress(value: Int(facts.progress_value), target: Int(facts.progress_target))
                : nil
        )
    }

    /// The URL of a text PSN gave, if it is one.
    ///
    /// - Parameter text: The text.
    /// - Returns: The URL, or `nil` for empty or unreadable text.
    static func url(of text: std.string) -> URL? {
        let spelled = String(text)
        guard !spelled.isEmpty else {
            return nil
        }
        return URL(string: spelled)
    }

    /// The date of milliseconds since the epoch.
    ///
    /// - Parameter milliseconds: The time, or 0 for none.
    /// - Returns: The date, or `nil` for none.
    static func date(of milliseconds: Int64) -> Date? {
        milliseconds > 0
            ? Timestamp.date(milliseconds: milliseconds)
            : nil
    }

    /// The model failure of a request PSN did not answer.
    ///
    /// - Parameter reason: Why PSN did not answer.
    /// - Returns: The failure.
    static func failure(of reason: libchiaking.users.Unanswered.Reason) -> PSNTrophiesFailure {
        switch reason {
        case .cancelled:
            .cancelled
        case .signed_out:
            .signedOut
        case .sign_in_expired, .store_access_lapsed, .remote_play_access_missing:
            .auth
        case .rate_limited:
            .rateLimited
        case .rejected, .unavailable, .malformed, .old_service_refused:
            .unavailable
        }
    }
}
