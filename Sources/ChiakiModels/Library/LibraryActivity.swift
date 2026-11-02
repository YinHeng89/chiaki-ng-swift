import Foundation

/// What the app is doing with the selected account and its consoles, as the library shows it.
///
/// The app owns the accounts and the console catalog; it publishes this summary to the library whenever it
/// changes, and the library renders its status lines and waits for consoles from it.
public struct LibraryActivity: Equatable, Sendable {
    /// Where the refresh of the account details is.
    public enum Refresh: Equatable, Sendable {
        /// No refresh is running and the last one succeeded.
        case idle
        /// A refresh is running.
        case refreshing
        /// The last refresh left some details stale.
        case failed
    }

    /// Where the removal of an account is.
    public enum Removal: Equatable, Sendable {
        /// No account is being removed.
        case idle
        /// An account is being removed.
        case removing
        /// The last removal failed.
        case failed
    }

    /// Whether the console catalog has been read.
    public enum Catalog: Equatable, Sendable {
        /// The accounts or the paired consoles are still being read.
        case loading
        /// The catalog is read.
        case loaded
    }

    /// Whether a console is being edited or removed.
    public enum ConsoleOperation: Equatable, Sendable {
        /// No console operation is running.
        case idle
        /// A console is being edited, saved or removed, so the cards do not start anything.
        case busy
    }

    /// Where the refresh of the account details is.
    public var refresh: Refresh
    /// Where the removal of an account is.
    public var removal: Removal
    /// The accounts whose last refresh asked for a new sign-in.
    public var signInNeeded: Set<UUID>
    /// Whether the console catalog has been read.
    public var catalog: Catalog
    /// Whether a console is being edited or removed.
    public var consoleOperation: ConsoleOperation

    /// Creates an activity summary.
    ///
    /// - Parameters:
    ///   - refresh: Where the refresh of the account details is.
    ///   - removal: Where the removal of an account is.
    ///   - signInNeeded: The accounts that must sign in again.
    ///   - catalog: Whether the console catalog has been read.
    ///   - consoleOperation: Whether a console is being edited or removed.
    public init(
        refresh: Refresh = .idle,
        removal: Removal = .idle,
        signInNeeded: Set<UUID> = [],
        catalog: Catalog = .loaded,
        consoleOperation: ConsoleOperation = .idle
    ) {
        self.refresh = refresh
        self.removal = removal
        self.signInNeeded = signInNeeded
        self.catalog = catalog
        self.consoleOperation = consoleOperation
    }
}
