import Foundation

/// What the core reports about one credential of a user, without its secret.
public struct HeldCredential: Hashable, Sendable {
    /// Which credential this is.
    public let kind: CredentialKind

    /// Whether the user holds it.
    public let held: Bool

    /// Where it is kept.
    public let kept: CredentialKept

    /// What is known about whether it works.
    public let state: CredentialState

    /// When it was obtained, when known.
    public let obtainedAt: Date?

    /// When it expires, when known.
    public let expiresAt: Date?

    /// The scopes it was granted, or an empty string.
    public let scopes: String

    /// The HTTP status of the last reply that used it, when one was seen.
    public let lastReplyStatus: Int?

    /// What it is used for.
    public let usedFor: [CredentialUse]

    /// Describes a credential.
    ///
    /// - Parameters:
    ///   - kind: Which credential.
    ///   - held: Whether it is held.
    ///   - kept: Where it is kept.
    ///   - state: Whether it works.
    ///   - obtainedAt: When it was obtained.
    ///   - expiresAt: When it expires.
    ///   - scopes: The granted scopes.
    ///   - lastReplyStatus: The last reply's HTTP status.
    ///   - usedFor: What it is used for.
    public init(
        kind: CredentialKind,
        held: Bool,
        kept: CredentialKept = .inMemory,
        state: CredentialState = .neverObtained,
        obtainedAt: Date? = nil,
        expiresAt: Date? = nil,
        scopes: String = "",
        lastReplyStatus: Int? = nil,
        usedFor: [CredentialUse] = []
    ) {
        self.kind = kind
        self.held = held
        self.kept = kept
        self.state = state
        self.obtainedAt = obtainedAt
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.lastReplyStatus = lastReplyStatus
        self.usedFor = usedFor
    }
}

/// Where a credential is kept.
public enum CredentialKept: Hashable, Sendable, CaseIterable {
    /// Part of the saved sign-in; it survives a restart.
    case withTheUser

    /// Only in memory; it is obtained again when needed.
    case inMemory
}

/// A credential the core may hold for a signed-in user.
public enum CredentialKind: Hashable, Sendable, CaseIterable {
    /// The NPSSO every other credential is obtained from.
    case signInSeed

    /// The app token for store, profile and library calls.
    case appToken

    /// The refresh token that renews the app token.
    case appRefreshToken

    /// The Remote Play token for console listing and internet play.
    case remotePlayToken

    /// The refresh token that renews the Remote Play token.
    case remotePlayRefreshToken

    /// The token that reads the owned-games library.
    case libraryToken

    /// The checkout token of the older PlayStation Now store service.
    case oldServiceCheckoutToken
}

/// What is known about whether a held credential works.
public enum CredentialState: Hashable, Sendable, CaseIterable {
    /// Held and, as far as is known, accepted by PSN.
    case usable

    /// Held but past its expiry.
    case expired

    /// PSN refused the credential or the request to obtain it.
    case refused

    /// Not held, and no attempt to obtain it was refused.
    case neverObtained

    /// Held and not past any known expiry, but not confirmed against PSN.
    case unverified
}

/// Something a held credential is used for.
public enum CredentialUse: Hashable, Sendable, CaseIterable {
    /// Obtaining other tokens.
    case exchangingTokens

    /// Authorising a cloud streaming session.
    case cloudStreamingAuthorisation

    /// Opening a session with the older PlayStation Now store service.
    case oldServiceStore

    /// Fetching the user's profile.
    case profile

    /// Fetching the user's PlayStation Plus membership.
    case membership

    /// Checking a title against the storefront.
    case storefrontCheck

    /// Listing the titles installed on the user's consoles.
    case consoleTitles

    /// Starting a title on a console.
    case startingATitle

    /// Reading the concepts of owned copies.
    case ownedCopyConcepts

    /// Renewing the app token.
    case renewingTheAppToken

    /// Listing the consoles on the account.
    case accountConsoles

    /// Streaming from a console over the internet.
    case internetPlay

    /// Renewing the Remote Play token.
    case renewingTheRemotePlayToken

    /// Reading the owned-games library.
    case ownedLibrary

    /// Checking out a title on the older PlayStation Now store service.
    case oldServiceCheckout
}

/// A saved account signed in to PlayStation Network, with the credentials the core holds for it.
public struct TokenAccount: Equatable, Identifiable, Sendable {
    /// The local identifier of the saved account.
    public let id: UUID
    /// The account's online ID, or its saved name when no online ID is known.
    public let name: String
    /// The raw bytes of the PlayStation account identifier, used to ask the core for a credential.
    public let accountID: Data
    /// The state of each credential the core keeps for the account.
    public let credentials: [HeldCredential]

    /// Creates an account entry from its identifiers, display name and credentials.
    public init(id: UUID, name: String, accountID: Data, credentials: [HeldCredential]) {
        self.id = id
        self.name = name
        self.accountID = accountID
        self.credentials = credentials
    }
}
