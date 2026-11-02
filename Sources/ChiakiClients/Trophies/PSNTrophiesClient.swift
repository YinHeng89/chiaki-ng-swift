import ChiakiModels
import Dependencies

/// Reads a profile's trophy level, the games it has trophies in and each game's trophies.
///
/// The live value, in `ChiakiClientsLive`, asks PSN through the core, which keeps answers and paces requests; the
/// test value refuses everything.
public struct PSNTrophiesClient: Sendable {
    /// The profile's trophy level and earned trophies.
    public var summary: @Sendable (_ profile: ProfileID) async throws(PSNTrophiesFailure) -> TrophySummary

    /// The games the profile has trophies in, most recently updated first.
    public var titles: @Sendable (_ profile: ProfileID) async throws(PSNTrophiesFailure) -> [TrophyTitle]

    /// One game's groups and trophies.
    public var trophies: @Sendable (_ profile: ProfileID,
                                    _ titleID: String) async throws(PSNTrophiesFailure) -> TitleTrophies

    /// The trophies of the game being played, as PSN has them now, or `nil` when the game has no trophy set.
    public var current: @Sendable (_ profile: ProfileID,
                                   _ titleID: String) async throws(PSNTrophiesFailure) -> CurrentTrophies?

    /// Forgets what is kept for the profile, so the next reads ask PSN again.
    public var startOver: @Sendable (_ profile: ProfileID) async -> Void

    /// Creates a client from its operations.
    ///
    /// - Parameters:
    ///   - summary: Reads the trophy level.
    ///   - titles: Lists the games with trophies.
    ///   - trophies: Reads one game's trophies.
    ///   - current: Reads the trophies of the game being played.
    ///   - startOver: Forgets what is kept.
    public init(
        summary: @escaping @Sendable (ProfileID) async throws(PSNTrophiesFailure) -> TrophySummary,
        titles: @escaping @Sendable (ProfileID) async throws(PSNTrophiesFailure) -> [TrophyTitle],
        trophies: @escaping @Sendable (ProfileID, String) async throws(PSNTrophiesFailure) -> TitleTrophies,
        current: @escaping @Sendable (ProfileID, String) async throws(PSNTrophiesFailure)
            -> CurrentTrophies? = PSNTrophiesClient.unanswered,
        startOver: @escaping @Sendable (ProfileID) async -> Void = { _ in
        }
    ) {
        self.summary = summary
        self.titles = titles
        self.trophies = trophies
        self.current = current
        self.startOver = startOver
    }
}

extension PSNTrophiesClient {
    /// Refuses to read the current game's trophies, the default for a client made without that operation.
    ///
    /// - Parameters:
    ///   - profile: The profile asked about.
    ///   - titleID: The release asked about.
    /// - Returns: Never.
    /// - Throws: `PSNTrophiesFailure.unavailable`, always.
    @Sendable public static func unanswered(
        _ profile: ProfileID,
        _ titleID: String
    ) async throws(PSNTrophiesFailure) -> CurrentTrophies? {
        throw .unavailable
    }
}

extension PSNTrophiesClient: TestDependencyKey {
    /// Refuses everything, so tests never reach PSN.
    public static let testValue = Self(
        summary: { _ throws(PSNTrophiesFailure) in
            throw .unavailable
        },
        titles: { _ throws(PSNTrophiesFailure) in
            throw .unavailable
        },
        trophies: { _, _ throws(PSNTrophiesFailure) in
            throw .unavailable
        }
    )
}

extension DependencyValues {
    /// Reads PSN trophies.
    public var psnTrophies: PSNTrophiesClient {
        get {
            self[PSNTrophiesClient.self]
        }
        set {
            self[PSNTrophiesClient.self] = newValue
        }
    }
}
