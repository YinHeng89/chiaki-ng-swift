/// The account's cloud library as one fetch returned it.
public struct CloudLibrarySnapshot: Codable, Equatable, Sendable {
    /// The schema version this app writes.
    public static let supportedSchemaVersion = 12

    /// The schema version the snapshot was written with.
    public let schemaVersion: Int

    /// The store locale the titles were read in.
    public let settledLocale: String

    /// Every title, visible or hidden.
    public let games: [CloudGame]

    /// Describes a snapshot.
    ///
    /// - Parameters:
    ///   - settledLocale: The store locale.
    ///   - games: The titles.
    public init(settledLocale: String, games: [CloudGame]) {
        schemaVersion = Self.supportedSchemaVersion
        self.settledLocale = settledLocale
        self.games = games
    }

    /// The titles the library shows.
    public var listedGames: [CloudGame] {
        games.filter(\.visible)
    }

    /// The snapshot with one title replaced, or added when it was missing.
    ///
    /// - Parameter game: The title.
    /// - Returns: The new snapshot.
    public func replacing(_ game: CloudGame) -> Self {
        Self(settledLocale: settledLocale, games: games.map {
            $0.id == game.id
                ? game
                : $0
        } + (games.contains { $0.id == game.id }
            ? []
            : [game]))
    }
}

/// Why the cloud library could not be fetched.
public enum CloudLibraryFailure: Error, Equatable, Sendable {
    /// The library is not available.
    case unavailable

    /// The account must sign in again.
    case signInRequired

    /// The catalog could not be read.
    case invalidCatalog

    /// The network failed.
    case network
}
