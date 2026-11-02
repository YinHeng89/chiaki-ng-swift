import ChiakiModels
import Foundation

/// Kakusan values for tests: ids, keys, blocks, codes and host attempts driven to a stage.
public enum KakusanFixture {
    /// A fixed operation id for the invitation of a built attempt.
    public static let operation = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    /// A fixed operation id for the reply of a built attempt.
    public static let replyOperation = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    /// A seat grant used by seated state changes.
    public static let grant = KakusanSeatGrant(seat: 3, generation: 7)

    /// A fixed current time.
    public static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A well-formed invitation block.
    public static let invitation = KakusanBlock(
        pasted: "RCP1:eyJib2R5Ijp7ImNhcGFjaXR5Ijo0LCJjcmVhdGVkX2F0IjoxNzAwMDAwMDAwLCJkcmFmdCI6NH0"
            + "sInNpZyI6IkFBQUEifQ"
    )!

    /// A well-formed reply block.
    public static let reply = KakusanBlock(
        pasted: "RCP1:eyJib2R5Ijp7ImtpbmQiOiJyZXBseSIsInJlcXVlc3RlZF9zZWF0cyI6MX0sInNpZyI6IkJCQkIifQ"
    )!

    /// A guest id filled with one byte.
    ///
    /// - Parameter value: The byte.
    /// - Returns: The id.
    public static func guest(_ value: UInt8) -> KakusanGuestID {
        KakusanGuestID(Data(repeating: value, count: KakusanGuestID.length))!
    }

    /// A public key filled with one byte.
    ///
    /// - Parameter value: The byte.
    /// - Returns: The key.
    public static func key(_ value: UInt8) -> KakusanPublicKey {
        KakusanPublicKey(Data(repeating: value, count: KakusanPublicKey.length))!
    }

    /// An identity hint filled with one byte.
    ///
    /// - Parameter value: The byte.
    /// - Returns: The hint.
    public static func hint(_ value: UInt8) -> KakusanIdentityHint {
        KakusanIdentityHint(Data(repeating: value, count: KakusanIdentityHint.length))!
    }

    /// A fingerprint derived from one byte.
    ///
    /// - Parameter value: The byte.
    /// - Returns: The fingerprint.
    public static func fingerprint(_ value: UInt8) -> KakusanFingerprint {
        KakusanFingerprint(Data((0 ..< 32).map { UInt8(truncatingIfNeeded: Int($0) * 7 + Int(value)) }))!
    }

    /// A bound peer derived from one byte.
    ///
    /// - Parameter value: The byte.
    /// - Returns: The peer.
    public static func peer(_ value: UInt8) -> KakusanIdentity {
        KakusanIdentity(publicKey: key(value), fingerprint: fingerprint(value))
    }

    /// A remembered device derived from one byte.
    ///
    /// - Parameters:
    ///   - value: The byte.
    ///   - name: The device's nickname.
    /// - Returns: The device.
    public static func remembered(_ value: UInt8, _ name: String) -> KakusanPeer {
        KakusanPeer(
            publicKey: key(value),
            fingerprint: fingerprint(value),
            nickname: name,
            firstVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
    }

    /// Normalises a nickname the way the core does for the names tests use: trimmed, and `nil` when empty.
    ///
    /// - Parameter typed: What the user typed.
    /// - Returns: The name, or `nil` when nothing is left.
    @Sendable public static func nickname(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// A verification code.
    ///
    /// - Parameter digits: The code's digits.
    /// - Returns: The code.
    public static func code(_ digits: String) -> KakusanCode {
        KakusanCode(digits)!
    }

    /// A preview of a four-seat invitation.
    ///
    /// - Parameter seconds: How long after ``now`` the invitation expires.
    /// - Returns: The preview.
    public static func preview(expiresIn seconds: TimeInterval = 600) -> KakusanInvitationPreview {
        KakusanInvitationPreview(
            hostHint: hint(1),
            claimedHostName: nil,
            capacity: 4,
            expiresAt: now.addingTimeInterval(seconds)
        )
    }

    /// A state change for a seated guest.
    ///
    /// - Parameters:
    ///   - state: The session state.
    ///   - pad: The console pad the guest holds.
    /// - Returns: The change.
    public static func seated(_ state: KakusanSessionState, pad: UInt8? = 2) -> KakusanStateChange {
        KakusanStateChange(state: state, seat: grant.seat, generation: grant.generation, consoleSeat: pad)
    }

    /// A state change for a guest with a reserved pad.
    ///
    /// - Parameter pad: The reserved pad.
    /// - Returns: The change.
    public static func reserved(pad: UInt8 = 2) -> KakusanStateChange {
        KakusanStateChange(
            state: .admitting,
            seat: grant.seat,
            generation: grant.generation,
            reservedSeat: pad
        )
    }

    /// A host attempt driven to a stage.
    ///
    /// - Parameters:
    ///   - id: The attempt's id.
    ///   - value: The byte the guest's id is filled with; the peer uses the next byte.
    ///   - stage: How far to drive it.
    /// - Returns: The attempt.
    public static func attempt(_ id: UUID, guest value: UInt8 = 1,
                               through stage: KakusanHostStage) -> KakusanHostAttempt {
        var attempt = KakusanHostAttempt(id: id, operation: operation)
        guard stage != .preparing else {
            return attempt
        }
        _ = attempt.apply(.invitation(.invited(operation, guest(value))))
        _ = attempt.apply(.invitation(.ready(KakusanInvitation(
            block: invitation,
            expiresAt: now.addingTimeInterval(600)
        ))))
        _ = attempt.apply(.reply(.submit(replyOperation)))
        switch stage {
        case .preparing, .invitation:
            _ = attempt.apply(.reply(.redirected(replyOperation)))
            return attempt
        case .rejectedReply:
            _ = attempt.apply(.reply(.rejected(replyOperation, .invalidBlock)))
            return attempt
        default:
            break
        }
        _ = attempt.apply(.reply(.imported(replyOperation)))
        _ = attempt.apply(.reply(.bound(peer(value + 1))))
        if stage == .endedNoPath {
            _ = attempt.apply(.state(KakusanStateChange(state: .closed, error: .noPath)))
            return attempt
        }
        guard stage != .connecting else {
            return attempt
        }
        _ = attempt.apply(.code(.ready(code("4821"))))
        guard stage != .verifying else {
            return attempt
        }
        _ = attempt.apply(.state(KakusanStateChange(state: .admitting)))
        guard stage != .admitting else {
            return attempt
        }
        _ = attempt.apply(.seat(.joinRequested))
        guard stage != .seating else {
            return attempt
        }
        _ = attempt.apply(.seat(.consoleJoined(pad: 2)))
        _ = attempt.apply(.state(seated(.active)))
        return attempt
    }
}

/// How far ``KakusanFixture/attempt(_:guest:through:)`` drives a host attempt.
public enum KakusanHostStage: CaseIterable, Sendable {
    /// Preparing the invitation.
    case preparing
    /// Waiting for a reply.
    case invitation
    /// A reply was refused.
    case rejectedReply
    /// Connecting to the guest.
    case connecting
    /// Checking codes.
    case verifying
    /// Admitting the guest.
    case admitting
    /// Waiting for a console seat.
    case seating
    /// Playing.
    case active
    /// Ended without a direct path.
    case endedNoPath
}
