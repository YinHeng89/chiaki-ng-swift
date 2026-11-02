import Foundation

/// One guest's journey through hosting: invitation, reply, approval, verification, admission and play.
///
/// Every input that answers an operation carries that operation's id; an answer for an operation that is no
/// longer current is ``KakusanTransition/ignored``. An ended attempt ignores everything.
public struct KakusanHostAttempt: Equatable, Sendable, Identifiable {
    /// The attempt's id.
    public let id: UUID
    /// The guest's id, once the invitation is created.
    public internal(set) var guest: KakusanGuestID?
    /// The current phase.
    public internal(set) var phase: KakusanHostPhase
    /// The guest's bound identity, once known.
    public internal(set) var peer: KakusanIdentity?
    /// The furthest milestone reached.
    public internal(set) var milestone = KakusanHostMilestone.inviting

    /// Starts an attempt preparing its invitation.
    ///
    /// - Parameters:
    ///   - id: The attempt's id.
    ///   - operation: The id of the invitation operation.
    public init(id: UUID, operation: UUID) {
        self.id = id
        phase = .preparing(operation)
    }

    /// How the attempt ended, once it has.
    public var outcome: KakusanAttemptOutcome? {
        if case .ended(let outcome) = phase {
            return outcome
        }
        return nil
    }

    /// The approval state, while connecting or verifying.
    public var approval: KakusanApproval? {
        switch phase {
        case .connecting(let approval), .verifying(let approval, _):
            approval
        case .preparing, .invitation, .admitting, .readying, .active, .closing, .ended:
            nil
        }
    }

    /// The seat grant, once reserved.
    public var seat: KakusanSeatGrant? {
        KakusanHostSeating(phase: phase, milestone: milestone).seat
    }

    /// The console pad reserved while admitting.
    public var reservedPad: UInt8? {
        KakusanHostSeating(phase: phase, milestone: milestone).reservedPad
    }

    /// The console pad the guest plays on, once joined.
    public var pad: UInt8? {
        KakusanHostSeating(phase: phase, milestone: milestone).pad
    }

    /// Whether a seat has been asked for.
    public var seatRequested: Bool {
        KakusanHostSeating(phase: phase, milestone: milestone).seatRequested
    }

    private mutating func progress(
        _ step: (inout KakusanHostProgress) -> KakusanTransition
    ) -> KakusanTransition {
        var progress = KakusanHostProgress(phase: phase, milestone: milestone)
        let transition = step(&progress)
        phase = progress.phase
        milestone = progress.milestone
        return transition
    }

    /// Applies an input.
    ///
    /// - Parameter input: What happened.
    /// - Returns: Whether the input changed the attempt.
    public mutating func apply(_ input: KakusanHostInput) -> KakusanTransition {
        if case .ended = phase {
            return .ignored
        }
        switch input {
        case .invitation(let event):
            return applyInvitation(event)
        case .reply(let event):
            return applyReply(event)
        case .approval(let event):
            return applyApproval(event)
        case .code(let event):
            return progress {
                $0.apply(event)
            }
        case .state(let change):
            return progress {
                $0.apply(change)
            }
        case .seat(let event):
            var seating = KakusanHostSeating(phase: phase, milestone: milestone)
            let transition = seating.apply(event)
            phase = seating.phase
            milestone = seating.milestone
            return transition
        case .cancel:
            phase = .ended(.cancelled)
            return .accepted
        case .hostingEnded:
            phase = .ended(.closed(.source, byPeer: false))
            return .accepted
        }
    }

    private mutating func applyInvitation(_ event: KakusanHostInput.Invitation) -> KakusanTransition {
        switch event {
        case let .invited(operation, guest):
            return bind(operation, guest)
        case let .failed(operation, error):
            guard phase == .preparing(operation) else {
                return .ignored
            }
            phase = .ended(.failed(error))
            return .accepted
        case .ready(let invitation):
            return present(invitation)
        case .expired:
            guard case .invitation = phase else {
                return .ignored
            }
            phase = .ended(.failed(.expired))
            return .accepted
        }
    }

    private mutating func bind(_ operation: UUID, _ guest: KakusanGuestID) -> KakusanTransition {
        guard phase == .preparing(operation) else {
            return .ignored
        }
        guard self.guest == nil else {
            return self.guest == guest
                ? .ignored
                : .rejected
        }
        self.guest = guest
        return .accepted
    }

    private mutating func present(_ invitation: KakusanInvitation) -> KakusanTransition {
        switch phase {
        case .preparing:
            guard guest != nil else {
                return .rejected
            }
            phase = .invitation(invitation, .awaiting)
            return .accepted
        case .invitation, .connecting, .verifying, .admitting, .readying, .active, .closing, .ended:
            return .ignored
        }
    }

    private mutating func applyReply(_ event: KakusanHostInput.Reply) -> KakusanTransition {
        switch event {
        case .submit(let operation):
            guard case .invitation(let invitation, let progress) = phase,
                  progress == .awaiting || isRejected(progress) else {
                return .rejected
            }
            phase = .invitation(invitation, .importing(operation))
            return .accepted
        case .imported(let operation):
            return imported(operation)
        case .redirected(let operation):
            guard case .invitation(let invitation, .importing(operation)) = phase else {
                return .ignored
            }
            phase = .invitation(invitation, .awaiting)
            return .accepted
        case let .rejected(operation, error):
            guard case .invitation(let invitation, .importing(operation)) = phase else {
                return .ignored
            }
            phase = .invitation(invitation, .rejected(error))
            return .accepted
        case .bound(let peer):
            return bound(peer)
        }
    }

    private func isRejected(_ progress: KakusanReplyImport) -> Bool {
        if case .rejected = progress {
            return true
        }
        return false
    }

    private mutating func imported(_ operation: UUID?) -> KakusanTransition {
        guard case .invitation(_, let progress) = phase else {
            return .ignored
        }
        if let operation {
            guard progress == .importing(operation) else {
                return .ignored
            }
        } else if case .importing = progress {
            return .ignored
        }
        phase = .connecting(.pending)
        milestone = max(milestone, .bound)
        return .accepted
    }

    private mutating func bound(_ peer: KakusanIdentity) -> KakusanTransition {
        if let current = self.peer {
            return current == peer
                ? .ignored
                : .rejected
        }
        switch phase {
        case .preparing:
            return .rejected
        case .invitation, .connecting, .verifying, .admitting, .readying, .active, .closing, .ended:
            self.peer = peer
            milestone = max(milestone, .bound)
            return .accepted
        }
    }

    private mutating func applyApproval(_ event: KakusanHostInput.Approval) -> KakusanTransition {
        switch event {
        case .request(let operation):
            return updateApproval(from: .pending, to: .sending(operation))
                ? .accepted
                : .rejected
        case .result(let operation, nil):
            return updateApproval(from: .sending(operation), to: .granted)
                ? .accepted
                : .ignored
        case let .result(operation, error?):
            guard approval == .sending(operation) else {
                return .ignored
            }
            phase = .ended(.failed(error))
            return .accepted
        }
    }

    private mutating func updateApproval(from current: KakusanApproval,
                                         to next: KakusanApproval) -> Bool {
        switch phase {
        case .connecting(current):
            phase = .connecting(next)
            return true
        case .verifying(current, let verification):
            phase = .verifying(next, verification)
            return true
        default:
            return false
        }
    }
}

extension KakusanHostAttempt {
    /// The most seats a shared session offers, local and remote together.
    public static let capacity = 4
}

/// A hosting attempt's progress once the guest answered: the verification codes and the session states the
/// host reports.
///
/// It moves only the attempt's phase and furthest milestone, so ``KakusanHostAttempt`` hands it those two
/// values for each code or state input and takes them back.
private struct KakusanHostProgress: Equatable, Sendable {
    /// The attempt's phase.
    var phase: KakusanHostPhase

    /// The furthest milestone the attempt reached.
    var milestone: KakusanHostMilestone

    /// Applies a verification code event: the own code being ready, or the guest's code being submitted and
    /// answered.
    ///
    /// - Parameter event: The code event.
    /// - Returns: Whether the event moved, was ignored by, or was refused by the attempt.
    mutating func apply(_ event: KakusanHostInput.Code) -> KakusanTransition {
        switch event {
        case .ready(let code):
            return record(code)
        case .submit(let operation):
            guard case .verifying(let approval, var verification) = phase else {
                return .rejected
            }
            let transition = verification.submit(operation)
            phase = .verifying(approval, verification)
            return transition
        case let .result(operation, error):
            guard case .verifying(let approval, var verification) = phase,
                  verification.entry == .submitting(operation) else {
                return .ignored
            }
            if let error {
                phase = .ended(.failed(error))
                return .accepted
            }
            verification.entry = .submitted
            phase = .verifying(approval, verification)
            return .accepted
        }
    }

    private mutating func record(_ code: KakusanCode) -> KakusanTransition {
        switch phase {
        case .connecting(let approval):
            phase = .verifying(approval, KakusanVerification(ownCode: code))
            return .accepted
        case .verifying(let approval, var verification):
            let transition = verification.record(code)
            phase = .verifying(approval, verification)
            return transition
        case .invitation:
            phase = .verifying(.pending, KakusanVerification(ownCode: code))
            milestone = max(milestone, .bound)
            return .accepted
        case .preparing:
            return .rejected
        case .admitting, .readying, .active, .closing, .ended:
            return .ignored
        }
    }

    /// Applies a state change reported by the host session.
    ///
    /// While closing, only the final closed state is accepted and ends the attempt; otherwise the change
    /// moves the
    /// attempt to the matching phase or is refused when it does not follow from the current one.
    ///
    /// - Parameter change: The reported state change.
    /// - Returns: Whether the change moved, was ignored by, or was refused by the attempt.
    mutating func apply(_ change: KakusanStateChange) -> KakusanTransition {
        if case .closing(let outcome) = phase {
            guard change.state == .closed else {
                return .ignored
            }
            phase = .ended(change.error == nil && change.reason == nil
                ? outcome
                : KakusanAttemptOutcome(change))
            return .accepted
        }
        switch change.state {
        case .waiting:
            return waiting()
        case .connecting:
            return connect()
        case .verifying:
            return verify()
        case .admitting:
            return admit(change)
        case .readyWait:
            return ready(change)
        case .active:
            return activate(change)
        case .closing:
            phase = .closing(KakusanAttemptOutcome(change))
            return .accepted
        case .closed:
            phase = .ended(KakusanAttemptOutcome(change))
            return .accepted
        }
    }

    private func waiting() -> KakusanTransition {
        switch phase {
        case .preparing, .invitation:
            .ignored
        default:
            .rejected
        }
    }

    private mutating func connect() -> KakusanTransition {
        switch phase {
        case .invitation:
            phase = .connecting(.pending)
            milestone = max(milestone, .bound)
            return .accepted
        case .connecting:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func verify() -> KakusanTransition {
        switch phase {
        case .invitation:
            phase = .verifying(.pending, KakusanVerification())
            milestone = max(milestone, .bound)
            return .accepted
        case .connecting(let approval):
            phase = .verifying(approval, KakusanVerification())
            return .accepted
        case .verifying:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func admit(_ change: KakusanStateChange) -> KakusanTransition {
        switch phase {
        case .invitation, .connecting, .verifying:
            phase = .admitting(.awaitingSeat)
            milestone = max(milestone, .verified)
            return .accepted
        case .admitting(.consoleJoined):
            return .ignored
        case .admitting(let admission):
            guard let grant = change.grant, let pad = change.reservedSeat,
                  admission != .reserved(grant, pad: pad) else {
                return .ignored
            }
            phase = .admitting(.reserved(grant, pad: pad))
            return .accepted
        default:
            return .rejected
        }
    }

    private mutating func ready(_ change: KakusanStateChange) -> KakusanTransition {
        switch phase {
        case .admitting(.awaitingSeat):
            return .rejected
        case .admitting(let admission):
            guard let grant = change.grant, let pad = change.consoleSeat ?? admission.pad else {
                return .rejected
            }
            phase = .readying(grant, pad: pad)
            return .accepted
        case .readying(let grant, let pad):
            return reseat(change, from: grant, pad) { .readying($0, pad: $1) }
        default:
            return .rejected
        }
    }

    private mutating func activate(_ change: KakusanStateChange) -> KakusanTransition {
        switch phase {
        case .admitting(.awaitingSeat):
            return .rejected
        case .admitting(let admission):
            guard let grant = change.grant, let pad = change.consoleSeat ?? admission.pad else {
                return .rejected
            }
            phase = .active(grant, pad: pad)
            milestone = .seated
            return .accepted
        case .readying(let grant, let pad):
            phase = .active(change.grant ?? grant, pad: change.consoleSeat ?? pad)
            milestone = .seated
            return .accepted
        case .active(let grant, let pad):
            return reseat(change, from: grant, pad) { .active($0, pad: $1) }
        default:
            return .rejected
        }
    }

    private mutating func reseat(
        _ change: KakusanStateChange,
        from grant: KakusanSeatGrant,
        _ pad: UInt8,
        to next: (KakusanSeatGrant, UInt8) -> KakusanHostPhase
    ) -> KakusanTransition {
        let reported = next(change.grant ?? grant, change.consoleSeat ?? pad)
        guard reported != phase else {
            return .ignored
        }
        phase = reported
        return .accepted
    }
}

/// A hosting attempt's seat on the console: the guest asking to join, and the console granting, refusing or
/// dropping its controller slot.
///
/// It moves only the attempt's phase and furthest milestone, so ``KakusanHostAttempt`` hands it those two
/// values for each seat event and takes them back.
private struct KakusanHostSeating: Equatable, Sendable {
    /// The attempt's phase.
    var phase: KakusanHostPhase

    /// The furthest milestone the attempt reached.
    var milestone: KakusanHostMilestone

    /// The seat grant, once reserved.
    var seat: KakusanSeatGrant? {
        switch phase {
        case .admitting(.reserved(let grant, _)), .readying(let grant, _), .active(let grant, _):
            grant
        case .preparing, .invitation, .connecting, .verifying, .admitting, .closing, .ended:
            nil
        }
    }

    /// The console pad reserved while admitting.
    var reservedPad: UInt8? {
        if case .admitting(.reserved(_, let pad)) = phase {
            return pad
        }
        return nil
    }

    /// The console pad the guest plays on, once joined.
    var pad: UInt8? {
        switch phase {
        case .admitting(let admission):
            admission.pad
        case .readying(_, let pad), .active(_, let pad):
            pad
        case .preparing, .invitation, .connecting, .verifying, .closing, .ended:
            nil
        }
    }

    /// Whether a seat has been asked for.
    var seatRequested: Bool {
        switch phase {
        case .admitting(.awaitingConsole), .admitting(.reserved), .admitting(.consoleJoined), .readying,
             .active:
            true
        case .preparing, .invitation, .connecting, .verifying, .admitting, .closing, .ended:
            false
        }
    }

    /// Applies a seat event: the guest asking to join, or the console granting, refusing or dropping its
    /// controller slot.
    ///
    /// - Parameter event: The seat event.
    /// - Returns: Whether the event moved, was ignored by, or was refused by the attempt.
    mutating func apply(_ event: KakusanHostInput.Seat) -> KakusanTransition {
        switch event {
        case .joinRequested:
            return requestJoin()
        case .consoleJoined(let pad):
            return joinConsole(pad)
        case .consoleJoinFailed:
            return failJoin()
        case .consoleLeft(let pad):
            return leaveConsole(pad)
        }
    }

    private mutating func requestJoin() -> KakusanTransition {
        switch phase {
        case .connecting, .verifying, .admitting(.awaitingSeat):
            phase = .admitting(.awaitingConsole)
            milestone = max(milestone, .verified)
            return .accepted
        case .admitting(.awaitingConsole), .admitting(.reserved), .closing:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func joinConsole(_ pad: UInt8) -> KakusanTransition {
        switch phase {
        case .admitting(.consoleJoined(pad)):
            return .ignored
        case .admitting(.awaitingConsole), .admitting(.reserved), .admitting(.consoleJoined):
            phase = .admitting(.consoleJoined(pad: pad))
            return .accepted
        case .readying(let grant, let current):
            guard current != pad else {
                return .ignored
            }
            phase = .readying(grant, pad: pad)
            return .accepted
        case .active(let grant, let current):
            guard current != pad else {
                return .ignored
            }
            phase = .active(grant, pad: pad)
            return .accepted
        case .admitting, .closing:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func failJoin() -> KakusanTransition {
        switch phase {
        case .admitting(.awaitingConsole):
            phase = .admitting(.awaitingSeat)
            return .accepted
        case .admitting, .readying, .active, .closing:
            return .ignored
        default:
            return .rejected
        }
    }

    private mutating func leaveConsole(_ pad: UInt8) -> KakusanTransition {
        switch phase {
        case .admitting, .readying, .active:
            guard self.pad == pad else {
                return .ignored
            }
            phase = .closing(.closed(.source, byPeer: false))
            return .accepted
        case .closing:
            return .ignored
        default:
            return .rejected
        }
    }
}

/// How far a host's attempt got, in order.
public enum KakusanHostMilestone: Int, Equatable, Sendable, Comparable {
    /// The invitation was being made.
    case inviting

    /// The guest's identity was bound.
    case bound

    /// The codes matched.
    case verified

    /// The guest was seated.
    case seated

    /// Orders milestones by progress.
    ///
    /// - Parameters:
    ///   - lhs: One milestone.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` comes first.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
