import ChiakiModels
import Foundation

/// Something the library asks the app to do with the accounts, the consoles or a stream.
///
/// The library does not own accounts, pairings or streams; it sends each request to the app through
/// `LibraryFeature/Action/Delegate/requested(_:)`.
public enum LibraryRequest: Equatable, Sendable {
    /// Add an account.
    case addAccount
    /// Show the library for another account.
    case selectAccount(UUID)
    /// Sign an account in again.
    case reconnectAccount(UUID)
    /// Ask to remove an account.
    case removeAccount(UUID)
    /// Refresh the account details.
    case refreshAccounts
    /// Pair a console.
    case addConsole
    /// Stream a paired console over this route.
    case startConsole(RegistrationFlow.ConsoleTarget, PlaybackRoute)
    /// Edit a paired console.
    case editConsole(ConsoleDraft)
    /// Ask to remove a paired console.
    case deleteConsole(UUID)
    /// Launch a recently played title on a console and stream it.
    case playTitle(UUID, RecentTitle)
    /// Join someone else's game.
    case joinGame
    /// Load the layered art of the titles the console cards show.
    case showConsoleArt([ConsoleArtRequest])
}
