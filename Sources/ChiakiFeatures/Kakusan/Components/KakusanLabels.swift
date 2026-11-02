import ChiakiModels

extension KakusanHostNotice {
    /// The notice's heading.
    var title: String {
        switch self {
        case .invitationEnded(let outcome):
            outcome == .failed(.expired)
                ? "Invitation expired"
                : "Invitation closed"
        case let .ended(name, outcome):
            Self.endedTitle(name ?? "The remote player", outcome)
        case .noFreeSeat:
            "No free seat"
        case .commandFailed:
            "Remote players hit a problem"
        }
    }

    /// The notice's detail, if it needs one.
    var detail: String? {
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

    private static func endedTitle(_ player: String, _ outcome: KakusanAttemptOutcome) -> String {
        switch outcome {
        case .cancelled, .left, .closed(.user, true):
            "\(player) left"
        case .closed(.user, false):
            "\(player) was removed"
        case .failed, .closed:
            "\(player) disconnected"
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
        name ?? "Remote player"
    }

    /// The guest's progress, and how it is coloured.
    var status: (text: String, tone: CouchTone) {
        switch attempt.phase {
        case .preparing:
            ("Preparing an invitation", .waiting)
        case .invitation(_, .importing):
            ("Checking the reply", .waiting)
        case .invitation:
            ("Waiting for a reply", .waiting)
        case .connecting:
            ("Connecting", .waiting)
        case .verifying:
            ("Checking codes", .waiting)
        case .admitting:
            ("Joining the console", .waiting)
        case .readying:
            ("Getting ready", .waiting)
        case .active:
            ("Playing", .ready)
        case .closing:
            ("Leaving", .idle)
        case .ended(let outcome):
            (outcome.label, .failed)
        }
    }
}
