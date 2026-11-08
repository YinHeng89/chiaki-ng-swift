import Foundation
import ChiakiModels

/// Presentation of credential kinds in the Tokens panel.
extension CredentialKind {
    /// The credential's display name.
    public var title: LocalizedStringResource {
        switch self {
        case .signInSeed:
            .settingsTokensKindSignInSeed
        case .appToken:
            .settingsTokensKindAppToken
        case .appRefreshToken:
            .settingsTokensKindAppRefreshToken
        case .remotePlayToken:
            .settingsTokensKindRemotePlayToken
        case .remotePlayRefreshToken:
            .settingsTokensKindRemotePlayRefreshToken
        case .libraryToken:
            .settingsTokensKindLibraryToken
        case .oldServiceCheckoutToken:
            .settingsTokensKindOldServiceCheckoutToken
        }
    }
}

/// Presentation of credential states in the Tokens panel.
extension CredentialState {
    /// The state's display label.
    public var label: LocalizedStringResource {
        switch self {
        case .usable:
            .settingsTokensStateUsable
        case .expired:
            .settingsTokensStateExpired
        case .refused:
            .settingsTokensStateRefused
        case .neverObtained:
            .settingsTokensStateNeverObtained
        case .unverified:
            .settingsTokensStateUnverified
        }
    }
}

/// Presentation of what a credential is used for.
extension CredentialUse {
    /// The use's display label.
    public var label: LocalizedStringResource {
        switch self {
        case .exchangingTokens:
            .settingsTokensUseExchangingTokens
        case .cloudStreamingAuthorisation:
            .settingsTokensUseCloudStreamingAuthorisation
        case .oldServiceStore:
            .settingsTokensUseOldServiceStore
        case .profile:
            .settingsTokensUseProfile
        case .membership:
            .settingsTokensUseMembership
        case .storefrontCheck:
            .settingsTokensUseStorefrontCheck
        case .consoleTitles:
            .settingsTokensUseConsoleTitles
        case .startingATitle:
            .settingsTokensUseStartingATitle
        case .ownedCopyConcepts:
            .settingsTokensUseOwnedCopyConcepts
        case .renewingTheAppToken:
            .settingsTokensUseRenewingTheAppToken
        case .accountConsoles:
            .settingsTokensUseAccountConsoles
        case .internetPlay:
            .settingsTokensUseInternetPlay
        case .renewingTheRemotePlayToken:
            .settingsTokensUseRenewingTheRemotePlayToken
        case .ownedLibrary:
            .settingsTokensUseOwnedLibrary
        case .oldServiceCheckout:
            .settingsTokensUseOldServiceCheckout
        }
    }
}

/// Presentation of why a credential was not revealed.
extension NotRevealed.Reason {
    /// A sentence explaining why the credential could not be revealed.
    public var message: LocalizedStringResource {
        switch self {
        case .notHeld:
            .settingsTokensNotRevealedNotHeld
        case .signedOut:
            .settingsTokensNotRevealedSignedOut
        case .unknownUser:
            .settingsTokensNotRevealedUnknownUser
        case .coreClosed:
            .settingsTokensNotRevealedCoreClosed
        }
    }
}

/// The display strings for one credential row in the Tokens panel.
public struct HeldCredentialPresentation: Equatable, Identifiable {
    /// One labelled fact about a credential.
    public struct Fact: Equatable, Identifiable {
        /// What a fact is about.
        public enum Kind: Equatable, Hashable, Sendable {
            /// When the credential was obtained.
            case obtained
            /// When the credential expires.
            case expires
            /// The credential's scopes.
            case scopes
            /// The status of the last reply that used the credential.
            case lastReply
            /// What the credential is used for.
            case usedFor
        }

        /// What the fact is about, which is unique within a credential.
        public let kind: Kind
        /// The fact's formatted value.
        public let value: String

        /// What the fact is about, which identifies it within a credential.
        public var id: Kind {
            kind
        }

        /// The fact's label.
        public var label: LocalizedStringResource {
            switch kind {
            case .obtained:
                .settingsTokensFactObtained
            case .expires:
                .settingsTokensFactExpires
            case .scopes:
                .settingsTokensFactScopes
            case .lastReply:
                .settingsTokensFactLastReply
            case .usedFor:
                .settingsTokensFactUsedFor
            }
        }
    }

    /// The credential kind, which identifies the row.
    public let id: CredentialKind
    /// The credential's display name.
    public let title: LocalizedStringResource
    /// The credential's state, prefixed with Not held when the core does not hold it.
    public let status: LocalizedStringResource
    /// Whether the core holds the credential.
    public let held: Bool
    /// When the credential was obtained and expires, its scopes, the last reply status and what it is used
    /// for.
    public let facts: [Fact]

    /// Formats the credential, showing dates in the given locale and time zone.
    public init(_ credential: HeldCredential, locale: Locale = .current, timeZone: TimeZone = .current) {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
        let unknown = String(localized: .commonUnknown)
        let none = String(localized: .settingsTokensNoValue)
        id = credential.kind
        title = credential.kind.title
        held = credential.held
        if credential.held || credential.state == .neverObtained {
            status = credential.state.label
        } else {
            let state = String(localized: credential.state.label).localizedLowercase
            status = .settingsTokensNotHeldStatus(state: state)
        }
        facts = [
            Fact(kind: .obtained, value: credential.obtainedAt.map { $0.formatted(style) } ?? unknown),
            Fact(kind: .expires, value: credential.expiresAt.map { $0.formatted(style) } ?? unknown),
            Fact(
                kind: .scopes,
                value: credential.scopes.isEmpty
                    ? none
                    : credential.scopes
            ),
            Fact(
                kind: .lastReply,
                value: credential.lastReplyStatus.map {
                    String(localized: .settingsTokensLastReplyStatus(status: String($0)))
                } ?? none
            ),
            Fact(
                kind: .usedFor,
                value: credential.usedFor.isEmpty
                    ? String(localized: .settingsTokensUsedForNothing)
                    : credential.usedFor.map { String(localized: $0.label) }.joined(separator: ", ")
            )
        ]
    }
}
