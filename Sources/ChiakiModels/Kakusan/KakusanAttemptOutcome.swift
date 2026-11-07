import Foundation

/// How a Kakusan attempt ended.
public enum KakusanAttemptOutcome: Equatable, Sendable {
    /// The user cancelled it.
    case cancelled

    /// The user left.
    case left

    /// It failed.
    case failed(KakusanError)

    /// It closed for a reason, possibly caused by the peer.
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

    /// The message shown for the outcome.
    public var label: LocalizedStringResource {
        switch self {
        case .cancelled:
            .kakusanAttemptCancelled
        case .left:
            .kakusanReasonLeftGame
        case .failed(let error):
            error.label
        case let .closed(reason, byPeer):
            reason.label(byPeer: byPeer)
        }
    }

    /// The heading of the host's card for an ended attempt.
    public var title: LocalizedStringResource {
        switch self {
        case .failed(.noPath):
            .kakusanAttemptNoPathTitle
        case .failed(.pairingFailed):
            .kakusanAttemptUnverifiedTitle
        case .failed(.expired):
            .kakusanAttemptExpiredTitle
        case .cancelled, .left, .failed, .closed:
            .kakusanAttemptEndedTitle
        }
    }

    /// The SF Symbol shown beside ``title``.
    public var symbolName: String {
        switch self {
        case .failed(.noPath):
            "point.3.filled.connected.trianglepath.dotted"
        case .failed(.pairingFailed):
            "exclamationmark.shield"
        case .failed(.expired):
            "clock.badge.xmark"
        case .cancelled, .left, .failed, .closed:
            "person.badge.minus"
        }
    }
}
