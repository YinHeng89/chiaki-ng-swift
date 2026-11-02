import Foundation

/// A guest's journey through joining: entering an invitation, previewing it, accepting the disclosure, replying,
/// verifying and playing.
///
/// Session inputs carry the session id that started them; inputs for another session are
/// ``KakusanTransition/ignored``.
public struct KakusanGuestJoin: Equatable, Sendable {
    /// The current phase.
    public internal(set) var phase: KakusanGuestPhase = .idle

    /// Creates an idle join.
    public init() {
    }

    /// The running session's id, if any.
    public var session: UUID? {
        phase.session
    }

    /// The invitation being considered or answered.
    public var summary: KakusanInvitationSummary? {
        switch phase {
        case .previewed(let summary), .disclosureAccepted(let summary), .preparingReply(_, let summary),
             .waitingForHost(_, _, let summary):
            summary
        default:
            nil
        }
    }

    /// Whether the join screen is shown.
    public var presented: Bool {
        phase != .idle
    }

    /// Applies an input.
    ///
    /// - Parameter input: What happened.
    /// - Returns: Whether the input changed the join.
    public mutating func apply(_ input: KakusanGuestInput) -> KakusanTransition {
        switch input {
        case .open:
            guard phase == .idle else {
                return .ignored
            }
            phase = .entering(nil)
            return .accepted
        case .preview(let event):
            return applyPreview(event)
        case .setDisclosure(let accepted):
            return disclose(accepted)
        case .start(let session):
            guard case .disclosureAccepted(let summary) = phase else {
                return .rejected
            }
            phase = .preparingReply(session, summary)
            return .accepted
        case let .session(id, event):
            guard let current = session, current == id else {
                return .ignored
            }
            var running = KakusanGuestSession(phase: phase)
            let transition = running.apply(id, event)
            phase = running.phase
            return transition
        case .leave:
            return leave()
        case .back:
            return back()
        }
    }

    private mutating func applyPreview(_ event: KakusanGuestInput.Preview) -> KakusanTransition {
        switch event {
        case .request(let operation):
            switch phase {
            case .entering, .previewed, .disclosureAccepted:
                phase = .previewing(operation)
                return .accepted
            default:
                return .rejected
            }
        case let .succeeded(operation, summary):
            guard phase == .previewing(operation) else {
                return .ignored
            }
            phase = .previewed(summary)
            return .accepted
        case let .failed(operation, error):
            guard phase == .previewing(operation) else {
                return .ignored
            }
            phase = .entering(error)
            return .accepted
        }
    }

    private mutating func disclose(_ accepted: Bool) -> KakusanTransition {
        switch phase {
        case .previewed(let summary):
            guard accepted else {
                return .ignored
            }
            phase = .disclosureAccepted(summary)
            return .accepted
        case .disclosureAccepted(let summary):
            guard !accepted else {
                return .ignored
            }
            phase = .previewed(summary)
            return .accepted
        default:
            return .rejected
        }
    }

    private mutating func leave() -> KakusanTransition {
        switch phase {
        case .idle, .leaving:
            return .ignored
        case .entering, .previewing, .previewed, .disclosureAccepted, .ended:
            phase = .idle
            return .accepted
        default:
            guard let session else {
                return .rejected
            }
            phase = .leaving(session)
            return .accepted
        }
    }

    private mutating func back() -> KakusanTransition {
        switch phase {
        case .previewed, .disclosureAccepted, .ended:
            phase = .entering(nil)
            return .accepted
        default:
            return .rejected
        }
    }
}

/// A guest join's progress while its session runs: the reply, the verification codes, the session states the
/// host reports, the stream and how the session ends.
///
/// It moves only the join's phase, so ``KakusanGuestJoin`` hands it the phase for each session event and
/// takes it back.
private struct KakusanGuestSession: Equatable, Sendable {
    /// The join's phase.
    var phase: KakusanGuestPhase

    /// Applies an event from the running guest session, routing it to the reply, code, state, stream or
    /// termination handlers.
    ///
    /// While leaving, only the session's stop is accepted and returns the join to idle; everything else is
    /// ignored.
    ///
    /// - Parameters:
    ///   - id: The session the event came from, already matched against the current session.
    ///   - event: The session event.
    /// - Returns: Whether the event moved, was ignored by, or was refused by the join.
    mutating func apply(_ id: UUID, _ event: KakusanGuestInput.Session) -> KakusanTransition {
        if case .leaving = phase {
            guard event == .stopped else {
                return .ignored
            }
            phase = .idle
            return .accepted
        }
        switch event {
        case .replyReady(let reply):
            return replyReady(id, reply)
        case .codeReady(let code):
            return codeReady(id, code)
        case .submitCode(let operation):
            return submitCode(id, operation)
        case let .codeResult(operation, error):
            return codeResult(id, operation, error)
        case .state(let change):
            return applyState(id, change)
        case .streamReady, .firstFrame, .streamStopped:
            return applyStream(id, event)
        case .failed, .ended, .expired, .stopped:
            return applyTermination(event)
        }
    }

    private mutating func replyReady(_ id: UUID, _ reply: KakusanBlock) -> KakusanTransition {
        switch phase {
        case .preparingReply(_, let summary):
            phase = .waitingForHost(id, reply: reply, summary)
            return .accepted
        case .waitingForHost(_, let current, _):
            return current == reply
                ? .ignored
                : .rejected
        default:
            return .ignored
        }
    }

    private mutating func codeReady(_ id: UUID, _ code: KakusanCode) -> KakusanTransition {
        switch phase {
        case .waitingForHost, .connecting:
            phase = .verifying(id, KakusanVerification(ownCode: code))
            return .accepted
        case .verifying(_, var verification):
            let transition = verification.record(code)
            phase = .verifying(id, verification)
            return transition
        case .preparingReply:
            return .rejected
        default:
            return .ignored
        }
    }

    private mutating func submitCode(_ id: UUID, _ operation: UUID) -> KakusanTransition {
        guard case .verifying(_, var verification) = phase else {
            return .rejected
        }
        let transition = verification.submit(operation)
        phase = .verifying(id, verification)
        return transition
    }

    private mutating func codeResult(_ id: UUID, _ operation: UUID,
                                     _ error: KakusanError?) -> KakusanTransition {
        guard case .verifying(_, var verification) = phase,
              verification.entry == .submitting(operation) else {
            return .ignored
        }
        if let error {
            phase = .ended(.failed(error))
            return .accepted
        }
        verification.entry = .submitted
        phase = .verifying(id, verification)
        return .accepted
    }

    private mutating func applyState(_ id: UUID, _ change: KakusanStateChange) -> KakusanTransition {
        switch change.state {
        case .waiting:
            return waiting()
        case .connecting:
            return connect(id)
        case .verifying:
            return verify(id)
        case .admitting:
            return admit(id)
        case .readyWait:
            return ready(id, seat: change.seat)
        case .active:
            return activate(id, seat: change.seat)
        case .closing, .closed:
            phase = .ended(KakusanGuestOutcome(change))
            return .accepted
        }
    }

    private func waiting() -> KakusanTransition {
        switch phase {
        case .preparingReply, .waitingForHost:
            .ignored
        default:
            .rejected
        }
    }

    private mutating func connect(_ id: UUID) -> KakusanTransition {
        switch phase {
        case .preparingReply, .waitingForHost:
            phase = .connecting(id)
            return .accepted
        case .connecting:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func verify(_ id: UUID) -> KakusanTransition {
        switch phase {
        case .preparingReply, .waitingForHost, .connecting:
            phase = .verifying(id, KakusanVerification())
            return .accepted
        case .verifying:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func admit(_ id: UUID) -> KakusanTransition {
        switch phase {
        case .waitingForHost, .connecting, .verifying:
            phase = .admitting(id)
            return .accepted
        case .admitting:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func ready(_ id: UUID, seat: Int?) -> KakusanTransition {
        switch phase {
        case .admitting:
            phase = .readying(id, seat: seat)
            return .accepted
        case .readying:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func activate(_ id: UUID, seat: Int?) -> KakusanTransition {
        switch phase {
        case .admitting:
            phase = .streaming(id, KakusanGuestStream(seat: seat, video: .awaitingStream))
            return .accepted
        case .readying(_, let known):
            phase = .streaming(id, KakusanGuestStream(seat: seat ?? known, video: .awaitingStream))
            return .accepted
        case .streaming:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func applyStream(_ id: UUID,
                                      _ event: KakusanGuestInput.Session) -> KakusanTransition {
        switch (phase, event) {
        case let (.admitting, .streamReady(fps)):
            phase = .streaming(id, KakusanGuestStream(seat: nil, video: .awaitingFrame(fps: fps)))
        case let (.readying(_, seat), .streamReady(fps)):
            phase = .streaming(id, KakusanGuestStream(seat: seat, video: .awaitingFrame(fps: fps)))
        case let (.streaming(_, stream), .streamReady(fps)) where stream.video == .awaitingStream:
            phase = .streaming(id, KakusanGuestStream(seat: stream.seat, video: .awaitingFrame(fps: fps)))
        case let (.streaming(_, stream), .firstFrame):
            return play(id, stream)
        case (.streaming, .streamStopped):
            phase = .ended(.closed(.source, byPeer: true))
        case (.streaming, _):
            return .ignored
        case (_, .streamStopped):
            return .ignored
        default:
            return .rejected
        }
        return .accepted
    }

    private mutating func play(_ id: UUID, _ stream: KakusanGuestStream) -> KakusanTransition {
        switch stream.video {
        case .awaitingStream:
            phase = .streaming(id, KakusanGuestStream(seat: stream.seat, video: .playing(fps: nil)))
            return .accepted
        case .awaitingFrame(let fps):
            phase = .streaming(id, KakusanGuestStream(seat: stream.seat, video: .playing(fps: fps)))
            return .accepted
        case .playing:
            return .ignored
        }
    }

    private mutating func applyTermination(_ event: KakusanGuestInput.Session) -> KakusanTransition {
        switch event {
        case .failed(let error):
            phase = .ended(.failed(error))
            return .accepted
        case .ended:
            if case .streaming = phase {
                phase = .ended(.closed(.source, byPeer: true))
            } else {
                phase = .ended(.failed(.internal))
            }
            return .accepted
        case .expired:
            switch phase {
            case .preparingReply, .waitingForHost:
                phase = .ended(.failed(.expired))
                return .accepted
            default:
                return .ignored
            }
        default:
            return .ignored
        }
    }
}
