import Foundation

/// What the core knows about one user it holds.
public struct SignedInUser: Hashable, Sendable {
    /// The user's PSN account.
    public let accountID: AccountID

    /// The user's online id, or the name a home user was given.
    public let onlineID: String

    /// Whether the user signed in with PSN rather than being added by account id.
    public let hasPSNAccount: Bool

    /// Where the sign-in stands.
    public let state: SignInState

    /// The PlayStation Plus tier, when it is known.
    public let tier: PlusTier?

    /// Whether the user is a PlayStation Plus member, when it is known.
    public let plusMember: Bool?

    /// The profile picture, when the profile names one.
    public let avatarURL: URL?

    /// The storefront region, once the core has learned it.
    public let region: AccountRegion?

    /// Describes a user.
    ///
    /// - Parameters:
    ///   - accountID: The PSN account.
    ///   - onlineID: The online id or home user name.
    ///   - hasPSNAccount: Whether the user signed in with PSN.
    ///   - state: Where the sign-in stands.
    ///   - tier: The PlayStation Plus tier, when known.
    ///   - plusMember: Whether the user is a member, when known.
    ///   - avatarURL: The profile picture, when named.
    ///   - region: The storefront region, when known.
    public init(
        accountID: AccountID,
        onlineID: String,
        hasPSNAccount: Bool,
        state: SignInState,
        tier: PlusTier? = nil,
        plusMember: Bool? = nil,
        avatarURL: URL? = nil,
        region: AccountRegion? = nil
    ) {
        self.accountID = accountID
        self.onlineID = onlineID
        self.hasPSNAccount = hasPSNAccount
        self.state = state
        self.tier = tier
        self.plusMember = plusMember
        self.avatarURL = avatarURL
        self.region = region
    }
}

/// Where a user's PSN sign-in stands.
public enum SignInState: Hashable, Sendable, CaseIterable {
    /// The sign-in is accepted and store access is held.
    case signedIn

    /// The sign-in is accepted but store access lapsed; a refresh renews it.
    case storeAccessLapsed

    /// PSN refused the sign-in; the user must sign in again.
    case signInExpired

    /// The user has no PSN sign-in.
    case signedOut
}
