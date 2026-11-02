import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reaches this installation's Kakusan identity, the devices it remembers and the invitations it reads,
/// outside of any shared stream.
public struct KakusanDevicesBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    #if CHIAKI_KAKUSAN
        /// Replaces the STUN servers Kakusan uses to find this device's public address.
        ///
        /// - Parameter servers: The servers, or none for the core's own list.
        /// - Returns: Success, or why the core refused the list.
        public func useStunServers(_ servers: [String]) -> Result<Void, KakusanError> {
            var texts = chiaki_bridge.Texts()
            for server in servers {
                texts.push_back(std.string(server))
            }
            let outcome = chiaki_bridge.KakusanDevices.use_stun_servers(texts)
            switch outcome.kind() {
            case .used:
                return .success(())
            case .unavailable:
                return outcome.why_unavailable() == .invalid_stun_servers
                    ? .failure(.internal)
                    : .failure(.cryptoUnavailable)
            case .refused:
                return .failure(.cryptoUnavailable)
            }
        }

        /// Reads what an invitation reveals before joining.
        ///
        /// - Parameter block: The invitation.
        /// - Returns: The preview, or why the invitation cannot be joined.
        public func preview(_ block: KakusanBlock) -> Result<KakusanInvitationPreview, KakusanError> {
            let outcome = chiaki_bridge.KakusanDevices.preview_invitation(std.string(block.text))
            switch outcome.kind() {
            case .read:
                guard let preview = Self.preview(of: outcome.invitation()) else {
                    return .failure(.invalidBlock)
                }
                return .success(preview)
            case .declined:
                return .failure(Self.error(outcome.decline()))
            case .unavailable:
                return .failure(.cryptoUnavailable)
            case .refused:
                return outcome.refusal() == .invalid_text
                    ? .failure(.invalidBlock)
                    : .failure(.cryptoUnavailable)
            }
        }

        /// This installation's Kakusan identity, derived and saved on first use.
        ///
        /// - Returns: The identity.
        /// - Throws: `KakusanError.cryptoUnavailable` when the core cannot derive it.
        public func thisDevice() throws(KakusanError) -> KakusanIdentity {
            let outcome = chiaki_bridge.KakusanDevices.this_device()
            guard outcome.kind() == .identified else {
                throw .cryptoUnavailable
            }
            let device = outcome.device()
            guard let publicKey = KakusanPublicKey(Data(device.identity)),
                  let fingerprint = KakusanFingerprint(Data(device.fingerprint)) else {
                throw .cryptoUnavailable
            }
            return KakusanIdentity(publicKey: publicKey, fingerprint: fingerprint)
        }

        /// Every device this installation remembers.
        ///
        /// - Returns: The devices, skipping any whose key or fingerprint is malformed.
        /// - Throws: `KakusanError.internal` when the core cannot list them.
        public func peers() throws(KakusanError) -> [KakusanPeer] {
            let outcome = chiaki_bridge.KakusanDevices.remembered()
            guard outcome.kind() == .listed else {
                throw .internal
            }
            return outcome.devices().compactMap(Self.peer(of:))
        }

        /// Checks a device against the remembered ones.
        ///
        /// - Parameters:
        ///   - key: The device's public key.
        ///   - nickname: The name the user expects it to have, if any.
        /// - Returns: How the device was recognised.
        public func recognize(_ key: KakusanPublicKey, expecting nickname: String?) -> KakusanRecognition {
            let identity = chiaki_bridge.Bytes(key.bytes)
            let facts = if let nickname {
                chiaki_bridge.KakusanDevices.recognise(identity, std.string(nickname))
            } else {
                chiaki_bridge.KakusanDevices.recognise(identity)
            }
            return Self.recognition(of: facts)
        }

        /// Renames a remembered device.
        ///
        /// - Parameters:
        ///   - key: The device's public key.
        ///   - nickname: The new name.
        /// - Returns: The renamed device, or the device already holding the name.
        /// - Throws: `KakusanError.sourceEnded` when the device is not remembered, otherwise
        ///   `KakusanError.internal`.
        public func rename(_ key: KakusanPublicKey, to nickname: String) throws(KakusanError)
            -> KakusanRememberResult {
            try Self.rememberResult(
                of: chiaki_bridge.KakusanDevices.rename(
                    chiaki_bridge.Bytes(key.bytes),
                    std.string(nickname)
                )
            )
        }

        /// Forgets a remembered device.
        ///
        /// - Parameter key: The device's public key.
        /// - Returns: Whether the core forgot it.
        public func forget(_ key: KakusanPublicKey) -> Bool {
            chiaki_bridge.KakusanDevices.forget(chiaki_bridge.Bytes(key.bytes))
        }

        /// Normalises a typed nickname.
        ///
        /// - Parameter typed: What the user typed.
        /// - Returns: The name as it would be saved, or `nil` when it cannot be a nickname.
        public func normalisedNickname(_ typed: String) -> String? {
            chiaki_bridge.KakusanDevices.normalised_nickname(std.string(typed)).value.map(String.init)
        }
    #endif

    /// Maps the core's answer to remembering or renaming a device.
    ///
    /// - Parameter outcome: The core's answer.
    /// - Returns: The saved device, or the device that already holds the nickname.
    /// - Throws: `KakusanError.sourceEnded` when the session or device is gone, otherwise
    ///   `KakusanError.internal`.
    static func rememberResult(of outcome: chiaki_bridge.RememberOutcome) throws(KakusanError)
        -> KakusanRememberResult {
        switch outcome.kind() {
        case .remembered:
            guard let peer = peer(of: outcome.device()) else {
                throw .internal
            }
            return .saved(peer)
        case .declined:
            return try declinedResult(of: outcome.decline())
        case .unavailable:
            throw .internal
        case .refused:
            throw outcome.refusal() == .invalid_identity
                ? KakusanError.sourceEnded
                : KakusanError.internal
        }
    }

    /// Maps the core's reason for declining to remember or rename a device.
    ///
    /// - Parameter decline: Why the core declined, with the device holding the nickname when it is taken.
    /// - Returns: The device that already holds the nickname.
    /// - Throws: `KakusanError.sourceEnded` when the device is gone, otherwise `KakusanError.internal`.
    static func declinedResult(of decline: chiaki_bridge.RememberDeclineFacts) throws(KakusanError)
        -> KakusanRememberResult {
        switch decline.kind {
        case .nickname_taken:
            guard let peer = decline.holder.value.flatMap(peer(of:)) else {
                throw .internal
            }
            return .nicknameTaken(peer)
        case .unknown_device, .not_verified:
            throw .sourceEnded
        case .invalid_nickname, .store_unavailable:
            throw .internal
        }
    }

    /// The model peer for a device the core remembers, or `nil` when its key or fingerprint is malformed.
    ///
    /// - Parameter facts: The device the core reported.
    /// - Returns: The peer.
    static func peer(of facts: chiaki_bridge.DeviceFacts) -> KakusanPeer? {
        guard let key = KakusanPublicKey(Data(facts.identity)),
              let fingerprint = KakusanFingerprint(Data(facts.fingerprint)) else {
            return nil
        }
        return KakusanPeer(
            publicKey: key,
            fingerprint: fingerprint,
            nickname: String(facts.nickname),
            firstVerifiedAt: Timestamp.date(milliseconds: facts.first_verified_ms),
            lastSeenAt: Timestamp.date(milliseconds: facts.last_seen_ms)
        )
    }

    /// The model error a core refusal stands for.
    ///
    /// - Parameter refused: The core's refusal.
    /// - Returns: The error.
    static func error(_ refused: libchiaking.kakusan.Refusal.Kind) -> KakusanError {
        switch refused {
        case .invalid_text, .invalid_argument:
            .invalidBlock
        case .expired:
            .expired
        case .unsupported_version:
            .version
        case .identity_changed:
            .identityChanged
        case .tampered:
            .transcript
        case .verification_failed:
            .pairingFailed
        case .unreachable:
            .noPath
        case .no_free_seat:
            .noCapacity
        case .console_refused_seat, .busy:
            .sourceJoinFailed
        case .malformed:
            .codec
        case .timed_out:
            .timeout
        case .protocol:
            .protocol
        case .stream_not_shareable, .cannot_be_shared:
            .sourceFormat
        case .connection_too_slow:
            .congestion
        case .session_ended, .not_sharing, .not_visiting:
            .sourceEnded
        case .internal:
            .internal
        }
    }

    private static func recognition(of facts: chiaki_bridge.RecognitionFacts) -> KakusanRecognition {
        guard let peer = facts.device.value.flatMap(peer(of:)) else {
            return .unknown
        }
        switch facts.kind {
        case .unknown:
            return .unknown
        case .recognised:
            return .recognised(peer)
        case .changed_key:
            return .changedKey(peer)
        }
    }

    /// A preview from what the core read, or `nil` when any value is outside the shared session's limits.
    ///
    /// - Parameters:
    ///   - hostHint: The host's identity hint, as raw bytes.
    ///   - claimedHostName: The name this installation remembers the host by, if any.
    ///   - capacity: The seats the host offers.
    ///   - expiresAt: When the invitation expires, in seconds since 1970.
    /// - Returns: The preview.
    static func preview(
        hostHint: Data,
        claimedHostName: String?,
        capacity: Int,
        expiresAt: UInt64
    ) -> KakusanInvitationPreview? {
        guard let hint = KakusanIdentityHint(hostHint),
              (1 ... KakusanHostAttempt.capacity).contains(capacity),
              expiresAt > 0 else {
            return nil
        }
        return KakusanInvitationPreview(
            hostHint: hint,
            claimedHostName: claimedHostName,
            capacity: capacity,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt))
        )
    }

    private static func preview(of invitation: chiaki_bridge
        .InvitationFacts) -> KakusanInvitationPreview? {
        preview(
            hostHint: Data(invitation.host_hint),
            claimedHostName: invitation.recognition.device.value.map { String($0.nickname) },
            capacity: Int(invitation.capacity),
            expiresAt: invitation.expires_at
        )
    }
}
