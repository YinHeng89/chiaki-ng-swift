import Foundation

/// A signed-in account as the core saves and restores it.
///
/// The NPSSO and the tokens stay in wiping buffers from the core to the encrypted columns and back.
public final class StoredSignIn: Sendable {
    /// The PSN account id.
    public let account: AccountID

    /// The PSN online id.
    public let onlineID: String

    /// The NPSSO's text bytes.
    public let npsso: SecretBytes

    /// When the NPSSO was obtained, if known.
    public let npssoObtainedAt: Date?

    /// When the NPSSO expires, if known.
    public let npssoExpiresAt: Date?

    /// The tokens the core holds, by kind.
    public let tokens: [CredentialTokenKind: StoredToken]

    /// The country and language, if known.
    public let region: AccountRegion?

    /// What the account token stated.
    public let context: StatedAccountContext

    /// The installation's device id the core signs in with, if known.
    public let deviceID: String?

    /// Describes a sign-in.
    ///
    /// - Parameters:
    ///   - account: The PSN account id.
    ///   - onlineID: The PSN online id.
    ///   - npsso: The NPSSO's text bytes.
    ///   - npssoObtainedAt: When the NPSSO was obtained.
    ///   - npssoExpiresAt: When the NPSSO expires.
    ///   - tokens: The tokens by kind.
    ///   - region: The country and language.
    ///   - context: What the account token stated.
    ///   - deviceID: The installation's device id.
    public init(
        account: AccountID,
        onlineID: String,
        npsso: consuming SecretBytes,
        npssoObtainedAt: Date? = nil,
        npssoExpiresAt: Date? = nil,
        tokens: [CredentialTokenKind: StoredToken] = [:],
        region: AccountRegion? = nil,
        context: StatedAccountContext = StatedAccountContext(),
        deviceID: String? = nil
    ) {
        self.account = account
        self.onlineID = onlineID
        self.npsso = npsso
        self.npssoObtainedAt = npssoObtainedAt
        self.npssoExpiresAt = npssoExpiresAt
        self.tokens = tokens
        self.region = region
        self.context = context
        self.deviceID = deviceID
    }
}

/// One saved token and its dates; the token stays in a wiping buffer.
public final class StoredToken: Sendable {
    /// The token's text bytes.
    public let value: SecretBytes

    /// When the token was obtained, if known.
    public let obtainedAt: Date?

    /// When the token expires, if known. Always known for an access token.
    public let expiresAt: Date?

    /// Describes a token.
    ///
    /// - Parameters:
    ///   - value: The token's text bytes.
    ///   - obtainedAt: When it was obtained.
    ///   - expiresAt: When it expires.
    public init(value: consuming SecretBytes, obtainedAt: Date?, expiresAt: Date?) {
        self.value = value
        self.obtainedAt = obtainedAt
        self.expiresAt = expiresAt
    }
}

/// One of the four tokens the core holds for a signed-in account.
public enum CredentialTokenKind: CaseIterable, Hashable, Sendable {
    /// The PlayStation Store access token.
    case storeAccess

    /// The PlayStation Store refresh token.
    case storeRefresh

    /// The Remote Play access token.
    case remotePlayAccess

    /// The Remote Play refresh token.
    case remotePlayRefresh

    /// Whether this is an access token, which always has an expiry.
    public var isAccess: Bool {
        switch self {
        case .storeAccess, .remotePlayAccess:
            true
        case .storeRefresh, .remotePlayRefresh:
            false
        }
    }
}

/// What the account token stated about the account's audience.
public struct StatedAccountContext: Hashable, Sendable {
    /// The legal country, if stated.
    public let legalCountry: String?

    /// The locale, if stated.
    public let locale: String?

    /// The age, if stated.
    public let age: Int?

    /// Whether the account is a child account, if stated.
    public let isChild: Bool?

    /// When the token stating this was issued.
    public let issuedAt: Date?

    /// Describes a context.
    ///
    /// - Parameters:
    ///   - legalCountry: The legal country.
    ///   - locale: The locale.
    ///   - age: The age.
    ///   - isChild: Whether the account is a child account.
    ///   - issuedAt: When the token was issued.
    public init(
        legalCountry: String? = nil,
        locale: String? = nil,
        age: Int? = nil,
        isChild: Bool? = nil,
        issuedAt: Date? = nil
    ) {
        self.legalCountry = legalCountry
        self.locale = locale
        self.age = age
        self.isChild = isChild
        self.issuedAt = issuedAt
    }

    /// Whether nothing about the audience is stated; such a context is not stored.
    public var statesNothing: Bool {
        legalCountry == nil && locale == nil && age == nil && isChild == nil
    }
}
