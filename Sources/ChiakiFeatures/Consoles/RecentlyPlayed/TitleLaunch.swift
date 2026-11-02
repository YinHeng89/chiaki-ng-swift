import ChiakiModels
import Foundation

/// A request to launch a recently played title on a console and stream it.
public struct TitleLaunch: Equatable, Sendable {
    /// The account that launches the title.
    public let accountID: UUID
    /// The id of the saved console.
    public let consoleID: UUID
    /// The console's hardware id.
    public let hardwareID: Data
    /// The title to launch.
    public let title: RecentTitle
    /// Creates a request.
    ///
    /// - Parameters:
    ///   - accountID: The account that launches the title.
    ///   - consoleID: The id of the saved console.
    ///   - hardwareID: The console's hardware id.
    ///   - title: The title to launch.
    public init(accountID: UUID, consoleID: UUID, hardwareID: Data, title: RecentTitle) {
        self.accountID = accountID
        self.consoleID = consoleID
        self.hardwareID = hardwareID
        self.title = title
    }
}
