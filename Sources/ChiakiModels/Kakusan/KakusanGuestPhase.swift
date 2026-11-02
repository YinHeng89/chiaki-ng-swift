import Foundation

/// Where a guest's join is.
public enum KakusanGuestPhase: Equatable, Sendable {
    /// Not joining.
    case idle

    /// Waiting for an invitation to be pasted, with the last error if any.
    case entering(KakusanError?)

    /// Previewing an invitation by the operation with the given id.
    case previewing(UUID)

    /// The invitation was previewed.
    case previewed(KakusanInvitationSummary)

    /// The user accepted what joining discloses.
    case disclosureAccepted(KakusanInvitationSummary)

    /// The session with the given id is preparing the reply.
    case preparingReply(UUID, KakusanInvitationSummary)

    /// The reply is ready; waiting for the host to import it.
    case waitingForHost(UUID, reply: KakusanBlock, KakusanInvitationSummary)

    /// Connecting to the host.
    case connecting(UUID)

    /// Comparing codes.
    case verifying(UUID, KakusanVerification)

    /// The host is admitting the guest.
    case admitting(UUID)

    /// Seated, getting ready.
    case readying(UUID, seat: Int?)

    /// Streaming.
    case streaming(UUID, KakusanGuestStream)

    /// Leaving the session.
    case leaving(UUID)

    /// Ended with the outcome.
    case ended(KakusanGuestOutcome)

    /// The session id, for the phases that have a running session.
    public var session: UUID? {
        switch self {
        case .preparingReply(let id, _), .waitingForHost(let id, _, _), .connecting(let id),
             .verifying(let id, _), .admitting(let id), .readying(let id, _), .streaming(let id, _),
             .leaving(let id):
            id
        case .idle, .entering, .previewing, .previewed, .disclosureAccepted, .ended:
            nil
        }
    }
}

/// A guest's running stream: its seat and video.
public struct KakusanGuestStream: Equatable, Sendable {
    /// The seat, once granted.
    public var seat: Int?

    /// The video.
    public var video: KakusanGuestVideo

    /// Creates a stream.
    ///
    /// - Parameters:
    ///   - seat: The seat.
    ///   - video: The video.
    public init(seat: Int?, video: KakusanGuestVideo) {
        self.seat = seat
        self.video = video
    }
}

/// Where the guest's video is.
public enum KakusanGuestVideo: Equatable, Sendable {
    /// Waiting for the host's stream.
    case awaitingStream

    /// The stream is ready at the frame rate; waiting for the first frame.
    case awaitingFrame(fps: Int)

    /// Frames are shown, at the frame rate when known.
    case playing(fps: Int?)
}

/// How a guest's session ended.
public enum KakusanGuestOutcome: Equatable, Sendable {
    /// It failed.
    case failed(KakusanError)

    /// It closed for a reason, possibly caused by the host.
    case closed(KakusanReason, byPeer: Bool)

    /// The outcome a final state change describes.
    ///
    /// - Parameter change: The change.
    public init(_ change: KakusanStateChange) {
        if let error = change.error {
            self = .failed(error)
        } else {
            self = .closed(change.reason ?? .user, byPeer: change.byPeer)
        }
    }

    /// The message shown to the guest.
    public var label: String {
        switch self {
        case .failed(let error):
            error.label
        case .closed(.user, true):
            "The host removed you"
        case let .closed(reason, byPeer):
            reason.label(byPeer: byPeer)
        }
    }

    /// The heading of the guest's card for an ended session.
    public var title: String {
        switch self {
        case .failed(.noPath):
            "A direct path wasn’t available"
        case .failed(.pairingFailed):
            "This invitation is closed"
        case .failed(.expired):
            "Invitation expired"
        case .closed(.source, _), .failed(.sourceEnded):
            "The game ended"
        case .failed, .closed:
            "Connection ended"
        }
    }

    /// The SF Symbol shown beside ``title``.
    public var symbolName: String {
        switch self {
        case .failed(.noPath):
            "point.3.filled.connected.trianglepath.dotted"
        case .failed(.pairingFailed):
            "lock"
        case .failed(.expired):
            "clock.badge.xmark"
        case .failed, .closed:
            "person.badge.minus"
        }
    }
}
