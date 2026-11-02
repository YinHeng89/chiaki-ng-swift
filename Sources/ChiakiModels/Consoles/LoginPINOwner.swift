import Foundation

/// The account and console a saved login PIN belongs to.
public struct LoginPINOwner: Equatable, Sendable {
    /// The id of the saved console.
    public let consoleID: UUID
    /// The id of the account streaming from it.
    public let accountID: UUID

    /// Names an account on a console.
    ///
    /// - Parameters:
    ///   - consoleID: The id of the saved console.
    ///   - accountID: The id of the account streaming from it.
    public init(consoleID: UUID, accountID: UUID) {
        self.consoleID = consoleID
        self.accountID = accountID
    }
}
