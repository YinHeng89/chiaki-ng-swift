import Foundation

/// One registered console's recently played titles, as a library rail shows them.
public struct RecentlyPlayedRail: Equatable, Sendable, Identifiable {
    /// The registered console, which identifies the rail.
    public var id: UUID {
        consoleID
    }

    /// The registered console.
    public let consoleID: UUID

    /// The console's hardware id bytes.
    public let hardwareID: Data

    /// The titles, most recent first.
    public let titles: [RecentTitle]

    /// Describes a rail.
    ///
    /// - Parameters:
    ///   - consoleID: The registered console.
    ///   - hardwareID: Its hardware id bytes.
    ///   - titles: Its titles.
    public init(consoleID: UUID, hardwareID: Data, titles: [RecentTitle]) {
        self.consoleID = consoleID
        self.hardwareID = hardwareID
        self.titles = titles
    }
}
