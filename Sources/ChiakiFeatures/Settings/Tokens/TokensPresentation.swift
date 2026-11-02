import Foundation
import ChiakiModels

/// Presentation of credential kinds in the Tokens panel.
extension CredentialKind {
    /// The credential's display name.
    public var title: String {
        switch self {
        case .signInSeed:
            "NPSSO"
        case .appToken:
            "App token"
        case .appRefreshToken:
            "App refresh token"
        case .remotePlayToken:
            "Remote Play token"
        case .remotePlayRefreshToken:
            "Remote Play refresh token"
        case .libraryToken:
            "Library token"
        case .oldServiceCheckoutToken:
            "Old service checkout token"
        }
    }
}

/// Presentation of credential states in the Tokens panel.
extension CredentialState {
    /// The state's display label.
    public var label: String {
        switch self {
        case .usable:
            "Usable"
        case .expired:
            "Expired"
        case .refused:
            "Refused"
        case .neverObtained:
            "Never obtained"
        case .unverified:
            "Unverified"
        }
    }
}

/// Presentation of what a credential is used for.
extension CredentialUse {
    /// The use's display label.
    public var label: String {
        switch self {
        case .exchangingTokens:
            "Exchanging tokens"
        case .cloudStreamingAuthorisation:
            "Cloud streaming authorisation"
        case .oldServiceStore:
            "Old service store"
        case .profile:
            "Profile"
        case .membership:
            "Membership"
        case .storefrontCheck:
            "Storefront check"
        case .consoleTitles:
            "Console titles"
        case .startingATitle:
            "Starting a title"
        case .ownedCopyConcepts:
            "Owned copy concepts"
        case .renewingTheAppToken:
            "Renewing the app token"
        case .accountConsoles:
            "Account consoles"
        case .internetPlay:
            "Internet play"
        case .renewingTheRemotePlayToken:
            "Renewing the Remote Play token"
        case .ownedLibrary:
            "Owned library"
        case .oldServiceCheckout:
            "Old service checkout"
        }
    }
}

/// Presentation of why a credential was not revealed.
extension NotRevealed.Reason {
    /// A sentence explaining why the credential could not be revealed.
    public var message: String {
        switch self {
        case .notHeld:
            "This credential is not held."
        case .signedOut:
            "This account is signed out."
        case .unknownUser:
            "This account is not signed in."
        case .coreClosed:
            "The credential could not be read."
        }
    }
}

/// The display strings for one credential row in the Tokens panel.
public struct HeldCredentialPresentation: Equatable, Identifiable {
    /// One labelled fact about a credential.
    public struct Fact: Equatable, Identifiable {
        /// The fact's label.
        public let label: String
        /// The fact's formatted value.
        public let value: String
        /// The label, which is unique within a credential.
        public var id: String {
            label
        }
    }

    /// The credential kind, which identifies the row.
    public let id: CredentialKind
    /// The credential's display name.
    public let title: String
    /// The credential's state, prefixed with Not held when the core does not hold it.
    public let status: String
    /// Whether the core holds the credential.
    public let held: Bool
    /// When the credential was obtained and expires, its scopes, the last reply status and what it is used
    /// for.
    public let facts: [Fact]

    /// Formats the credential, showing dates in the given locale and time zone.
    public init(_ credential: HeldCredential, locale: Locale = .current, timeZone: TimeZone = .current) {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
        id = credential.kind
        title = credential.kind.title
        held = credential.held
        if credential.held || credential.state == .neverObtained {
            status = credential.state.label
        } else {
            status = "Not held, \(credential.state.label.lowercased())"
        }
        facts = [
            Fact(label: "Obtained", value: credential.obtainedAt.map { $0.formatted(style) } ?? "Unknown"),
            Fact(label: "Expires", value: credential.expiresAt.map { $0.formatted(style) } ?? "Unknown"),
            Fact(
                label: "Scopes",
                value: credential.scopes.isEmpty
                    ? "None"
                    : credential.scopes
            ),
            Fact(label: "Last reply", value: credential.lastReplyStatus.map { "HTTP \($0)" } ?? "None"),
            Fact(
                label: "Used for",
                value: credential.usedFor.isEmpty
                    ? "Nothing"
                    : credential.usedFor.map(\.label).joined(separator: ", ")
            )
        ]
    }
}
