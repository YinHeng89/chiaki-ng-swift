import ChiakiModels
import ComposableArchitecture
import Foundation

/// Kakusan for features: hosting, joining and playing the guest's stream, this device's identity, the
/// remembered devices and the Kakusan preferences.
///
/// The live value talks to the core through the stream player's Kakusan entry points. Hosting meets the
/// console stream through `KakusanHostDesk` and guest commands reach the running guest session through
/// `KakusanGuestDesk`. The guest stream itself plays through ``StreamSessionClient``, which presents the shared
/// picture and routes input, and the preferences live in the app's settings store.
@DependencyClient
public struct KakusanClient: Sendable {
    /// Replaces the user's own STUN servers, or hands the choice back to the core.
    ///
    /// Sessions shared and joined afterwards use the new choice.
    ///
    /// - Parameter servers: The user's servers, as `host:port`; empty to use the core's.
    /// - Returns: Nothing on success, or why the list was refused.
    public var useStunServers: @Sendable (_ servers: [String]) async -> Result<Void, KakusanError> = { _ in
        .failure(.internal)
    }

    /// Arms hosting for the next console stream.
    ///
    /// - Parameters:
    ///   - configuration: The seats to offer.
    ///   - events: Receives the shared session's events in order.
    public var arm: @Sendable (
        _ configuration: KakusanHostConfiguration,
        _ events: @escaping @Sendable (KakusanHostEvent) async -> Void
    ) async -> Void

    /// Withdraws hosting.
    public var disarm: @Sendable () async -> Void

    /// Creates an invitation.
    ///
    /// - Returns: The new guest's id, or why no invitation was created.
    public var invite: @Sendable () async -> Result<KakusanGuestID, KakusanError> = {
        .failure(.internal)
    }

    /// Imports a guest's reply.
    ///
    /// - Parameter reply: The reply.
    /// - Returns: The guest the reply belongs to, or why it was refused.
    public var importReply: @Sendable (_ reply: KakusanBlock) async -> Result<
        KakusanGuestID,
        KakusanError
    > = { _ in
        .failure(.internal)
    }

    /// Sends a command to the hosted session.
    ///
    /// - Parameter command: The command.
    /// - Returns: Whether the session accepted it.
    public var send: @Sendable (_ command: KakusanHostCommand) async -> KakusanCommandOutcome = { _ in
        .rejected(.internal)
    }

    /// Reads what an invitation reveals before joining.
    ///
    /// - Parameter invitation: The invitation.
    /// - Returns: The preview, or why the invitation cannot be joined.
    public var preview: @Sendable (_ invitation: KakusanBlock) async -> Result<
        KakusanInvitationPreview,
        KakusanError
    > = { _ in
        .failure(.internal)
    }

    /// Enters the code the host reads out, on the running guest session.
    ///
    /// - Parameter code: The code.
    /// - Returns: Whether the session accepted it.
    public var enterCode: @Sendable (_ code: KakusanCode) async -> KakusanCommandOutcome = { _ in
        .rejected(.internal)
    }

    /// Loads this device's identity.
    ///
    /// - Returns: The identity.
    /// - Throws: `ChiakiModels/KakusanError` when the core has none.
    public var identity: @Sendable () async throws -> KakusanIdentity

    /// Lists the remembered devices, most recently seen first.
    ///
    /// - Returns: The devices.
    /// - Throws: `ChiakiModels/KakusanError/internal` when the store cannot be read.
    public var peers: @Sendable () async throws -> [KakusanPeer]

    /// Checks a device against the remembered ones.
    ///
    /// - Parameters:
    ///   - key: The device's public key.
    ///   - expecting: The name the user expects it to have.
    /// - Returns: How the device was recognised.
    public var recognize: @Sendable (_ key: KakusanPublicKey, _ expecting: String?) async throws
        -> KakusanRecognition

    /// Remembers a verified peer of the running session.
    ///
    /// - Parameters:
    ///   - peer: The peer.
    ///   - nickname: The normalised name to save it under.
    ///   - replacing: Whether to take the name from another device.
    /// - Returns: The saved device, or the device already holding the name.
    public var remember: @Sendable (
        _ peer: KakusanIdentity,
        _ nickname: String,
        _ replacing: Bool
    ) async throws
        -> KakusanRememberResult

    /// Renames a remembered device.
    ///
    /// - Parameters:
    ///   - key: The device's public key.
    ///   - nickname: The normalised new name.
    /// - Returns: The renamed device, or the device already holding the name.
    public var rename: @Sendable (_ key: KakusanPublicKey, _ nickname: String) async throws
        -> KakusanRememberResult

    /// Forgets a remembered device.
    ///
    /// - Parameter key: The device's public key.
    public var forget: @Sendable (_ key: KakusanPublicKey) async throws -> Void

    /// Normalises a typed nickname.
    ///
    /// - Parameter typed: What the user typed.
    /// - Returns: The name as it would be saved, or `nil` when it cannot be a nickname.
    public var nickname: @Sendable (_ typed: String) -> String? = { _ in
        nil
    }

    /// Joins with an invitation and plays the guest's stream until the session ends.
    ///
    /// - Parameters:
    ///   - session: The id of the guest session, tagging its events.
    ///   - configuration: What to join.
    ///   - events: Receives the session's events in order.
    /// - Throws: `ChiakiModels/KakusanError` when joining or playing failed, or `CancellationError`.
    public var playGuest: @Sendable (
        _ session: UUID,
        _ configuration: KakusanGuestConfiguration,
        _ events: @escaping @Sendable (KakusanGuestEvent) async -> Void
    ) async throws -> Void

    /// Stops the running guest stream.
    public var stopGuest: @Sendable () async -> Void

    /// Loads the saved Kakusan preferences, or the defaults when none are saved.
    ///
    /// - Returns: The preferences.
    public var loadSettings: @Sendable () async throws -> KakusanSettings

    /// Saves the Kakusan preferences.
    ///
    /// - Parameter settings: The validated preferences.
    public var saveSettings: @Sendable (_ settings: KakusanSettings) async throws -> Void
}

extension KakusanClient: TestDependencyKey {
    /// Fails the test when a feature uses Kakusan without overriding the operation.
    public static let testValue = KakusanClient()
}

extension KakusanClient {
    /// Kakusan for a build that leaves it out: hosting and joining refuse with
    /// `ChiakiModels/KakusanError/cryptoUnavailable`, arming and stopping do nothing, no device is remembered
    /// and nothing is saved.
    public static let unavailable = KakusanClient(
        useStunServers: { _ in
            .failure(.cryptoUnavailable)
        },
        arm: { _, _ in
        },
        disarm: {
        },
        invite: {
            .failure(.cryptoUnavailable)
        },
        importReply: { _ in
            .failure(.cryptoUnavailable)
        },
        send: { _ in
            .rejected(.cryptoUnavailable)
        },
        preview: { _ in
            .failure(.cryptoUnavailable)
        },
        enterCode: { _ in
            .rejected(.cryptoUnavailable)
        },
        identity: {
            throw KakusanError.cryptoUnavailable
        },
        peers: {
            []
        },
        recognize: { _, _ in
            .unknown
        },
        remember: { _, _, _ in
            throw KakusanError.cryptoUnavailable
        },
        rename: { _, _ in
            throw KakusanError.cryptoUnavailable
        },
        forget: { _ in
            throw KakusanError.cryptoUnavailable
        },
        nickname: { _ in
            nil
        },
        playGuest: { _, _, _ in
            throw KakusanError.cryptoUnavailable
        },
        stopGuest: {
        },
        loadSettings: {
            throw KakusanError.cryptoUnavailable
        },
        saveSettings: { _ in
            throw KakusanError.cryptoUnavailable
        }
    )
}

extension DependencyValues {
    /// Kakusan hosting, joining, remembered devices and preferences.
    public var kakusan: KakusanClient {
        get {
            self[KakusanClient.self]
        }
        set {
            self[KakusanClient.self] = newValue
        }
    }
}
