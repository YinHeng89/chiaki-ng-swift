import Foundation

/// The accounts after a refresh, with the ones that could not be refreshed.
public struct AccountRefreshResult: Equatable, Sendable {
    /// Why one account could not be refreshed.
    public enum Issue: String, Equatable, Sendable {
        /// PSN needs the account to sign in again.
        case signInRequired

        /// PSN could not be reached or did not answer.
        case unavailable
    }

    /// Every account after the refresh.
    public let accounts: [AccountProfile]

    /// The accounts that could not be refreshed, by profile id.
    public let issues: [UUID: Issue]

    /// Describes a refresh.
    ///
    /// - Parameters:
    ///   - accounts: Every account after the refresh.
    ///   - issues: The accounts that could not be refreshed.
    public init(accounts: [AccountProfile], issues: [UUID: Issue] = [:]) {
        self.accounts = accounts
        self.issues = issues
    }
}
