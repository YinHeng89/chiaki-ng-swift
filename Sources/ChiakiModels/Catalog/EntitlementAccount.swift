import Foundation

/// A saved PlayStation account that entitlements can be inspected for.
public struct EntitlementAccount: Equatable, Identifiable, Sendable {
    /// The local identifier of the saved account.
    public let id: UUID
    /// The account's online ID, or its saved name when no online ID is known.
    public let name: String
    /// The PlayStation account identifier used to ask the catalogue bridge for explanations.
    public let accountID: AccountID
    /// Creates an account entry from its local identifier, display name and PlayStation account identifier.
    public init(id: UUID, name: String, accountID: AccountID) {
        self.id = id
        self.name = name
        self.accountID = accountID
    }
}

/// A failure loading entitlements, carrying a message ready to show in the entitlements settings panel.
public struct EntitlementsFailure: Error, Equatable, Sendable {
    /// The human readable reason the entitlements could not be loaded.
    public let message: String
    /// Wraps a message describing why loading failed.
    public init(_ message: String) {
        self.message = message
    }
}
