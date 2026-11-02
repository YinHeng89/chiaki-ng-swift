import Foundation

/// One event a shared stream reported, as model values, mapped to host and guest events.
///
/// ``hostEvent`` and ``guestEvent`` drop anything malformed or outside the shared session's limits, so a feature
/// only ever sees valid model values.
public struct KakusanStreamEvent: Equatable, Sendable {
    /// What a shared stream can report.
    public enum Kind: Equatable, Sendable {
        /// The host made an invitation for a guest.
        case invitationReady
        /// The host accepted a guest's reply and learned the guest's device.
        case replyBound
        /// The guest made a reply to an invitation.
        case replyReady
        /// A verification code is ready to read out.
        case codeReady
        /// A guest's visit moved to another stage.
        case stateChanged
        /// The host started sharing the stream.
        case streamShared
        /// The host stopped sharing the stream.
        case sharingEnded
        /// The console seated a guest.
        case playerSeated
        /// The console released a guest's seat.
        case playerUnseated
        /// The host's seats changed.
        case seatsChanged
        /// The guest's stream stopped.
        case streamStopped
        /// The guest's stream is ready.
        case streamReady
        /// The guest learned the host's device.
        case hostIdentified
        /// Kakusan cannot be used.
        case unavailable
        /// The host could not share the stream.
        case sharingFailed
    }

    /// What happened.
    public var kind: Kind
    /// The guest the event is about, as raw bytes.
    public var guestID: Data?
    /// The invitation or reply text the event carries.
    public var text: String?
    /// The verification code the event carries.
    public var code: String?
    /// When an invitation expires, in seconds since 1970.
    public var expiresAt: UInt64 = 0
    /// A peer's public key, as raw bytes.
    public var identity: Data?
    /// A peer's fingerprint, as raw bytes.
    public var fingerprint: Data?
    /// The stage the visit reached.
    public var state: KakusanSessionState?
    /// The failure the event reports.
    public var error: KakusanError?
    /// Why the visit ended.
    public var reason: KakusanReason?
    /// Whether the peer caused the change.
    public var byPeer = false
    /// The shared session seat the change concerns.
    public var seat: Int?
    /// The seat grant's generation.
    public var generation: UInt32 = 0
    /// The console pad the guest holds.
    public var pad: Int?
    /// The console pad reserved for the guest.
    public var reservedPad: Int?
    /// The total seats.
    public var capacity = 0
    /// The local seats.
    public var localSeats = 0
    /// The remote seats.
    public var remoteSeats = 0
    /// The reserved seats.
    public var reservedSeats = 0
    /// The guest stream's frame rate.
    public var videoFPS = 0

    /// Creates an empty event of a kind.
    ///
    /// - Parameter kind: What happened.
    public init(kind: Kind) {
        self.kind = kind
    }
}

extension KakusanStreamEvent {
    /// The event as a host sees it, or `nil` when it is not a valid host event.
    public var hostEvent: KakusanHostEvent? {
        switch kind {
        case .invitationReady:
            invitationReady
        case .replyBound:
            replyBound
        case .codeReady:
            guest.flatMap { guest in
                kakusanCode.map { .codeReady(guest, $0) }
            }
        case .stateChanged:
            guest.flatMap { guest in
                stateChange.map { .stateChanged(guest, $0) }
            }
        case .playerSeated:
            guest.flatMap { guest in
                seatedPad.map { .consoleSeated(guest, pad: $0) }
            }
        case .playerUnseated:
            guest.flatMap { guest in
                seatedPad.map { .consoleUnseated(guest, pad: $0) }
            }
        case .seatsChanged:
            seats.map { .seatsChanged($0) }
        case .unavailable, .sharingFailed:
            .unavailable(error ?? .internal)
        case .replyReady, .hostIdentified, .streamReady, .streamStopped, .streamShared, .sharingEnded:
            nil
        }
    }

    /// The event as a guest sees it, or `nil` when it is not a valid guest event.
    public var guestEvent: KakusanGuestEvent? {
        switch kind {
        case .replyReady:
            block.map { .replyReady($0) }
        case .hostIdentified:
            boundPeer.map { .hostIdentified($0) }
        case .codeReady:
            kakusanCode.map { .codeReady($0) }
        case .stateChanged:
            stateChange.map { .stateChanged($0) }
        case .streamReady:
            videoFPS > 0
                ? .streamReady(fps: videoFPS)
                : nil
        case .streamStopped:
            .streamStopped
        case .invitationReady, .replyBound, .streamShared, .sharingEnded, .playerSeated, .playerUnseated,
             .seatsChanged, .unavailable, .sharingFailed:
            nil
        }
    }

    private var guest: KakusanGuestID? {
        guestID.flatMap(KakusanGuestID.init)
    }

    private var block: KakusanBlock? {
        text.flatMap { KakusanBlock(pasted: $0) }
    }

    private var kakusanCode: KakusanCode? {
        code.flatMap(KakusanCode.init)
    }

    private var invitationReady: KakusanHostEvent? {
        guard let guest, let block, expiresAt > 0 else {
            return nil
        }
        return .invitationReady(guest, block, expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt)))
    }

    private var replyBound: KakusanHostEvent? {
        guard let guest, let peer = boundPeer else {
            return nil
        }
        return .replyBound(guest, peer.publicKey, peer.fingerprint)
    }

    private var boundPeer: KakusanIdentity? {
        guard let key = identity.flatMap(KakusanPublicKey.init),
              let print = fingerprint.flatMap(KakusanFingerprint.init) else {
            return nil
        }
        return KakusanIdentity(publicKey: key, fingerprint: print)
    }

    private var seatedPad: UInt8? {
        Self.remotePad(pad)
    }

    private static func remotePad(_ pad: Int?) -> UInt8? {
        guard let pad, (1 ..< KakusanHostAttempt.capacity).contains(pad) else {
            return nil
        }
        return UInt8(pad)
    }

    private var stateSeat: Int? {
        guard let seat, seat > 0 else {
            return nil
        }
        return seat
    }

    private var seats: KakusanSeatSnapshot? {
        let limit = KakusanHostAttempt.capacity
        guard (1 ... limit).contains(capacity),
              [localSeats, remoteSeats, reservedSeats].allSatisfy({ (0 ... limit).contains($0) }) else {
            return nil
        }
        return KakusanSeatSnapshot(
            capacity: capacity,
            local: localSeats,
            remote: remoteSeats,
            reserved: reservedSeats
        )
    }

    private var stateChange: KakusanStateChange? {
        guard let state else {
            return nil
        }
        return KakusanStateChange(
            state: state,
            error: error,
            reason: reason,
            byPeer: byPeer,
            seat: stateSeat,
            generation: generation,
            consoleSeat: seatedPad,
            reservedSeat: Self.remotePad(reservedPad)
        )
    }
}
