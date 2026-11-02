import Foundation

/// A PSN account the app knows, as the account list shows it.
public struct AccountProfile: Equatable, Sendable {
    /// How the account was added.
    public enum Method: String, Sendable {
        /// Signed in on the web; tokens are held for it.
        case npsso

        /// Added by account id only, for local play without a sign-in.
        case accountID = "account_id"
    }

    /// The profile's row id.
    public let id: UUID

    /// The display name.
    public let name: String

    /// How the account was added.
    public let method: Method

    /// The PSN account id.
    public let accountID: AccountID

    /// The PSN online id, once known.
    public let onlineID: String?

    /// The cached avatar image, if any.
    public var avatarData: Data?

    /// Whether the account has PS Plus, when that was last read.
    public var isPlus: Bool?

    /// When PS Plus membership was last read.
    public var membershipCheckedAt: Date?

    /// When the last membership reading goes stale.
    public var membershipExpiresAt: Date?

    /// Describes an account.
    ///
    /// - Parameters:
    ///   - id: The profile's row id.
    ///   - name: The display name.
    ///   - method: How the account was added.
    ///   - accountID: The PSN account id.
    ///   - onlineID: The PSN online id, once known.
    public init(id: UUID, name: String, method: Method, accountID: AccountID, onlineID: String? = nil) {
        self.id = id
        self.name = name
        self.method = method
        self.accountID = accountID
        self.onlineID = onlineID
    }
}
