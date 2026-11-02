import Foundation

/// Something the native session reports to a Kakusan host.
public enum KakusanHostEvent: Equatable, Sendable {
    /// An invitation for a guest is ready, with its expiry.
    case invitationReady(KakusanGuestID, KakusanBlock, expiresAt: Date)

    /// A guest's reply was bound to its key and fingerprint.
    case replyBound(KakusanGuestID, KakusanPublicKey, KakusanFingerprint)

    /// The host's code for a guest is ready to read out.
    case codeReady(KakusanGuestID, KakusanCode)

    /// A guest's session changed state.
    case stateChanged(KakusanGuestID, KakusanStateChange)

    /// A guest's controller took a console seat.
    case consoleSeated(KakusanGuestID, pad: UInt8)

    /// A guest's controller left a console seat.
    case consoleUnseated(KakusanGuestID, pad: UInt8)

    /// Seat use changed.
    case seatsChanged(KakusanSeatSnapshot)

    /// Hosting became unavailable.
    case unavailable(KakusanError)
}
