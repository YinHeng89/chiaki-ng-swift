import Foundation

/// A title installed on a console, as the console titles list reports it.
public struct RecentTitle: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// How the last-played time was learned.
    public enum LastPlayedKnown: String, Codable, Equatable, Hashable, Sendable {
        /// The console itself reported when it was last played.
        case onThisConsole = "on_this_console"

        /// The account reported when it was last played, on any console.
        case onTheAccount = "on_the_account"
    }

    /// The title id, which identifies the row.
    public var id: String {
        titleID
    }

    /// The title id.
    public let titleID: String

    /// The id the console starts the title with.
    public let launchID: String

    /// The title's name.
    public let name: String

    /// The cover image.
    public let imageURL: String

    /// The store category, when known.
    public let category: String

    /// The platform label, `PS5` or `PS4`.
    public let platform: String

    /// When the title was last played, in Unix milliseconds, or 0 when unknown.
    public let lastPlayedMs: Int64

    /// Whether the title is on the recently played list.
    public let recent: Bool

    /// The concept id, or an empty string.
    public let conceptID: String

    /// How the last-played time was learned.
    public let lastPlayedKnown: LastPlayedKnown

    /// Describes a title.
    ///
    /// - Parameters:
    ///   - titleID: The title id.
    ///   - launchID: The id the console starts it with.
    ///   - name: The title's name.
    ///   - imageURL: The cover image.
    ///   - category: The store category.
    ///   - platform: The platform label.
    ///   - lastPlayedMs: When it was last played, in Unix milliseconds.
    ///   - recent: Whether it is on the recently played list.
    ///   - conceptID: The concept id.
    ///   - lastPlayedKnown: How the last-played time was learned.
    public init(
        titleID: String,
        launchID: String,
        name: String,
        imageURL: String,
        category: String = "",
        platform: String = "PS5",
        lastPlayedMs: Int64 = 0,
        recent: Bool = false,
        conceptID: String = "",
        lastPlayedKnown: LastPlayedKnown = .onThisConsole
    ) {
        self.titleID = titleID
        self.launchID = launchID
        self.name = name
        self.imageURL = imageURL
        self.category = category
        self.platform = platform
        self.lastPlayedMs = lastPlayedMs
        self.recent = recent
        self.conceptID = conceptID
        self.lastPlayedKnown = lastPlayedKnown
    }

    /// When the title was last played, or `nil` when unknown.
    public var lastPlayed: Date? {
        guard lastPlayedMs > 0 else {
            return nil
        }
        return Timestamp.date(milliseconds: lastPlayedMs)
    }

    /// Whether this console reported a last-played time.
    public var playedOnThisConsole: Bool {
        lastPlayed != nil && lastPlayedKnown == .onThisConsole
    }

    /// Maps each property to its snake_case key in the stored and reported JSON.
    enum CodingKeys: String, CodingKey {
        /// The title id, stored as `title_id`.
        case titleID = "title_id"
        /// The launch id, stored as `launch_id`.
        case launchID = "launch_id"
        /// The title's name.
        case name
        /// The cover image, stored as `image_url`.
        case imageURL = "image_url"
        /// The title's category.
        case category
        /// The platform the title runs on.
        case platform
        /// The last-played time in milliseconds, stored as `last_played_ms`.
        case lastPlayedMs = "last_played_ms"
        /// Whether the title counts as recently played.
        case recent
        /// The store concept id, stored as `concept_id`.
        case conceptID = "concept_id"
        /// How the last-played time was learned, stored as `last_played_known`.
        case lastPlayedKnown = "last_played_known"
    }
}
