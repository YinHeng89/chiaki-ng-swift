import Foundation

/// The account, stored console and route of a console stream, kept to start it again after sleep.
public struct StreamTarget: Equatable, Sendable {
    /// The account.
    public let account: UUID

    /// The stored console.
    public let consoleID: UUID

    /// The route the stream played on, or the one the user asked for before it chose one.
    public let route: PlaybackRoute

    /// Whether ``route`` is the route the stream played on, which a stream started again after sleep keeps.
    public let played: Bool

    /// Creates a stream target.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - consoleID: The stored console.
    ///   - route: The route the stream played on, or the one asked for.
    ///   - played: Whether the route is the one the stream played on.
    public init(account: UUID, consoleID: UUID, route: PlaybackRoute, played: Bool = false) {
        self.account = account
        self.consoleID = consoleID
        self.route = route
        self.played = played
    }
}
