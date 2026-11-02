import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reads which credentials the open core holds for a user and reveals one secret on request.
///
/// A revealed secret is copied once from the core's wiping memory into a `ChiakiModels/RevealedSecret` and
/// never passes through a plain string.
public struct CredentialsBridge: Sendable {
    private final class Receiver {
        var secret: RevealedSecret?
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// The credentials a user holds, without their secrets.
    ///
    /// - Parameter account: The user's account.
    /// - Returns: One entry per credential the core knows, or `nil` when the core does not hold the user.
    public func held(by account: AccountID) -> [HeldCredential]? {
        chiaki_bridge.CredentialsBridge.held_by(UsersBridge.vector(account)).value.map { list in
            list.map(Self.credential(of:))
        }
    }

    /// Reveals one credential's secret.
    ///
    /// - Parameters:
    ///   - kind: The credential.
    ///   - account: The user's account.
    /// - Returns: The secret.
    /// - Throws: `ChiakiModels/NotRevealed` saying why nothing was revealed.
    public func reveal(_ kind: CredentialKind, of account: AccountID) throws(NotRevealed) -> RevealedSecret {
        let receiver = Receiver()
        let sink: chiaki_bridge.RevealedSink = { bytes, size, context in
            guard let bytes, let context else {
                return
            }
            Unmanaged<Receiver>.fromOpaque(context).takeUnretainedValue().secret = RevealedSecret(
                copying: UnsafeRawBufferPointer(start: bytes, count: size)
            )
        }
        let refusal = withExtendedLifetime(receiver) {
            chiaki_bridge.CredentialsBridge.reveal(
                UsersBridge.vector(account), Self.kind(of: kind), sink,
                Unmanaged.passUnretained(receiver).toOpaque()
            )
        }
        if let refusal = refusal.value {
            receiver.secret?.wipe()
            throw NotRevealed(Self.reason(of: refusal))
        }
        guard let secret = receiver.secret else {
            throw NotRevealed(.notHeld)
        }
        return secret
    }

    /// The model credential of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The credential.
    static func credential(of facts: chiaki_bridge.HeldCredentialFacts) -> HeldCredential {
        HeldCredential(
            kind: kind(of: facts.kind),
            held: facts.held,
            kept: kept(of: facts.kept),
            state: state(of: facts.state),
            obtainedAt: facts.obtained_at_ms.value.map(Timestamp.date(milliseconds:)),
            expiresAt: facts.expires_at_ms.value.map(Timestamp.date(milliseconds:)),
            scopes: String(facts.scopes),
            lastReplyStatus: facts.last_reply_status.value.map(Int.init),
            usedFor: facts.used_for.map(use(of:))
        )
    }

    /// The model reason of a refusal to reveal.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The reason.
    static func reason(of refusal: chiaki_bridge.RevealRefusal) -> NotRevealed.Reason {
        switch refusal {
        case .core_closed:
            .coreClosed
        case .unknown_user:
            .unknownUser
        case .not_held:
            .notHeld
        case .signed_out:
            .signedOut
        }
    }

    /// The model kind of a core credential kind.
    ///
    /// - Parameter kind: The core's kind.
    /// - Returns: The model kind.
    static func kind(of kind: libchiaking.users.CredentialKind) -> CredentialKind {
        switch kind {
        case .sign_in_seed:
            .signInSeed
        case .app_token:
            .appToken
        case .app_refresh_token:
            .appRefreshToken
        case .remote_play_token:
            .remotePlayToken
        case .remote_play_refresh_token:
            .remotePlayRefreshToken
        case .library_token:
            .libraryToken
        case .old_service_checkout_token:
            .oldServiceCheckoutToken
        }
    }

    /// The core kind of a model credential kind.
    ///
    /// - Parameter kind: The model kind.
    /// - Returns: The core's kind.
    static func kind(of kind: CredentialKind) -> libchiaking.users.CredentialKind {
        switch kind {
        case .signInSeed:
            .sign_in_seed
        case .appToken:
            .app_token
        case .appRefreshToken:
            .app_refresh_token
        case .remotePlayToken:
            .remote_play_token
        case .remotePlayRefreshToken:
            .remote_play_refresh_token
        case .libraryToken:
            .library_token
        case .oldServiceCheckoutToken:
            .old_service_checkout_token
        }
    }

    /// The model state of a core credential state.
    ///
    /// - Parameter state: The core's state.
    /// - Returns: The model state.
    static func state(of state: libchiaking.users.HeldCredential.State) -> CredentialState {
        switch state {
        case .usable:
            .usable
        case .expired:
            .expired
        case .refused:
            .refused
        case .never_obtained:
            .neverObtained
        case .unverified:
            .unverified
        }
    }

    /// The model keeping of a core keeping.
    ///
    /// - Parameter kept: Where the core keeps the credential.
    /// - Returns: The model keeping.
    static func kept(of kept: libchiaking.users.HeldCredential.Kept) -> CredentialKept {
        switch kept {
        case .with_the_user:
            .withTheUser
        case .in_memory:
            .inMemory
        }
    }

    /// The model use of a core credential use.
    ///
    /// - Parameter use: The core's use.
    /// - Returns: The model use.
    static func use(of use: libchiaking.users.CredentialUse) -> CredentialUse {
        switch use {
        case .exchanging_tokens:
            .exchangingTokens
        case .cloud_streaming_authorisation:
            .cloudStreamingAuthorisation
        case .old_service_store:
            .oldServiceStore
        case .profile:
            .profile
        case .membership:
            .membership
        case .storefront_check:
            .storefrontCheck
        case .console_titles:
            .consoleTitles
        case .starting_a_title:
            .startingATitle
        case .owned_copy_concepts:
            .ownedCopyConcepts
        case .renewing_the_app_token:
            .renewingTheAppToken
        case .account_consoles:
            .accountConsoles
        case .internet_play:
            .internetPlay
        case .renewing_the_remote_play_token:
            .renewingTheRemotePlayToken
        case .owned_library:
            .ownedLibrary
        case .old_service_checkout:
            .oldServiceCheckout
        }
    }
}
