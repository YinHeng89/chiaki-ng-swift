import ChiakiModels
import Foundation

extension KakusanHostNotice {
    /// The notice's heading.
    var title: LocalizedStringResource {
        switch self {
        case .invitationEnded(let outcome):
            outcome == .failed(.expired)
                ? .kakusanNoticeInvitationExpired
                : .kakusanNoticeInvitationClosed
        case let .ended(name, outcome):
            Self.endedTitle(name ?? String(localized: .kakusanNoticeRemotePlayer), outcome)
        case .noFreeSeat:
            .kakusanNoticeNoFreeSeat
        case .commandFailed:
            .kakusanNoticeCommandFailed
        }
    }

    /// The notice's detail, if it needs one.
    var detail: LocalizedStringResource? {
        switch self {
        case .invitationEnded(let outcome):
            outcome == .failed(.expired)
                ? nil
                : outcome.label
        case let .ended(_, outcome):
            Self.quiet(outcome)
                ? nil
                : outcome.label
        case .noFreeSeat:
            nil
        case .commandFailed(let error):
            error.label
        }
    }

    /// How the notice is coloured.
    var tone: CouchTone {
        switch self {
        case .invitationEnded:
            .idle
        case let .ended(_, outcome):
            Self.quiet(outcome)
                ? .idle
                : .waiting
        case .noFreeSeat, .commandFailed:
            .waiting
        }
    }

    private static func endedTitle(
        _ player: String,
        _ outcome: KakusanAttemptOutcome
    ) -> LocalizedStringResource {
        switch outcome {
        case .cancelled, .left, .closed(.user, true):
            .kakusanNoticeLeft(player: player)
        case .closed(.user, false):
            .kakusanNoticeRemoved(player: player)
        case .failed, .closed:
            .kakusanNoticeDisconnected(player: player)
        }
    }

    private static func quiet(_ outcome: KakusanAttemptOutcome) -> Bool {
        switch outcome {
        case .cancelled, .left, .closed(.user, _):
            true
        case .failed, .closed:
            false
        }
    }
}

extension KakusanHostFeature.Guest {
    /// The name shown for the guest.
    var displayName: String {
        name ?? String(localized: .kakusanGuestRemotePlayer)
    }

    /// The guest's progress, and how it is coloured.
    var status: (text: LocalizedStringResource, tone: CouchTone) {
        switch attempt.phase {
        case .preparing:
            (.kakusanStatusPreparing, .waiting)
        case .invitation(_, .importing):
            (.kakusanStatusCheckingReply, .waiting)
        case .invitation:
            (.kakusanStatusWaitingForReply, .waiting)
        case .connecting:
            (.kakusanStatusConnecting, .waiting)
        case .verifying:
            (.kakusanStatusCheckingCodes, .waiting)
        case .admitting:
            (.kakusanStatusJoiningConsole, .waiting)
        case .readying:
            (.kakusanStatusGettingReady, .waiting)
        case .active:
            (.kakusanStatusPlaying, .ready)
        case .closing:
            (.kakusanStatusLeaving, .idle)
        case .ended(let outcome):
            (outcome.label, .failed)
        }
    }
}
