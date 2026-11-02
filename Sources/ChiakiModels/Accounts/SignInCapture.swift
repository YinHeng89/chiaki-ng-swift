import Foundation

/// What a finished web sign-in hands over: the NPSSO and when it stops working.
///
/// The value is move-only because it owns the ``NPSSO``; it travels from the browser straight into the
/// sign-in without being copied into state or actions.
public struct SignInCapture: ~Copyable, Sendable {
    /// The captured session token.
    public let npsso: NPSSO

    /// When the token expires, if the token response or the cookie said.
    public let expiresAt: Date?

    /// Where ``expiresAt`` came from; ``NPSSOExpirySource/unknown`` when there is no expiry.
    public let expirySource: NPSSOExpirySource

    /// Describes a capture.
    ///
    /// - Parameters:
    ///   - npsso: The captured token.
    ///   - expiresAt: When the token expires, if known.
    ///   - expirySource: Where the expiry came from.
    public init(npsso: consuming NPSSO, expiresAt: Date?, expirySource: NPSSOExpirySource) {
        self.npsso = npsso
        self.expiresAt = expiresAt
        self.expirySource = expiresAt == nil
            ? .unknown
            : expirySource
    }
}

/// The profile the app expects the core's next sign-in or home user save to create.
///
/// The core does not know the app's profile ids; the app announces the id and name it chose before asking
/// the core to sign in, and the credential store uses them when the save creates a new profile.
public struct PendingProfile: Hashable, Sendable {
    /// The profile id to create the account under.
    public let id: UUID

    /// The display name to create the account with.
    public let name: String

    /// Where the NPSSO's expiry came from, for a sign-in.
    public let expirySource: NPSSOExpirySource

    /// Describes the expected profile.
    ///
    /// - Parameters:
    ///   - id: The profile id to create.
    ///   - name: The display name.
    ///   - expirySource: Where the NPSSO's expiry came from.
    public init(id: UUID, name: String, expirySource: NPSSOExpirySource = .unknown) {
        self.id = id
        self.name = name
        self.expirySource = expirySource
    }
}

/// Where a stored NPSSO's expiry came from.
public enum NPSSOExpirySource: String, Hashable, Sendable {
    /// The expiry is not known.
    case unknown

    /// Read from the sign-in cookie.
    case cookie

    /// Reported in the token response when the core signed in.
    case tokenResponse = "token_response"

    /// Whether the expiry was read from the server, from the cookie or the token response, so it may be handed
    /// to the core.
    public var isReadFromServer: Bool {
        switch self {
        case .cookie, .tokenResponse:
            true
        case .unknown:
            false
        }
    }
}
