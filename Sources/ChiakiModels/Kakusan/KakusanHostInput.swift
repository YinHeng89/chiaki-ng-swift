import Foundation

/// Something that happened to a host's attempt, grouped by step.
public enum KakusanHostInput: Equatable, Sendable {
    /// Invitation step inputs.
    public enum Invitation: Equatable, Sendable {
        /// The operation created the guest's id.
        case invited(UUID, KakusanGuestID)

        /// The operation failed.
        case failed(UUID, KakusanError)

        /// The invitation block is ready.
        case ready(KakusanInvitation)

        /// The invitation expired.
        case expired
    }

    /// Reply step inputs.
    public enum Reply: Equatable, Sendable {
        /// The host submitted a reply, with the import operation's id.
        case submit(UUID)

        /// A reply was imported, by the given operation or by the session itself.
        case imported(UUID?)

        /// The pasted reply belonged to another attempt.
        case redirected(UUID)

        /// The import operation was refused.
        case rejected(UUID, KakusanError)

        /// The guest's identity was bound.
        case bound(KakusanIdentity)
    }

    /// Approval step inputs.
    public enum Approval: Equatable, Sendable {
        /// The host approved, with the operation's id.
        case request(UUID)

        /// The approval operation finished, with its error if any.
        case result(UUID, KakusanError?)
    }

    /// Verification step inputs.
    public enum Code: Equatable, Sendable {
        /// The host's code is ready.
        case ready(KakusanCode)

        /// The host submitted the guest's code, with the operation's id.
        case submit(UUID)

        /// The submission finished, with its error if any.
        case result(UUID, KakusanError?)
    }

    /// Seating step inputs.
    public enum Seat: Equatable, Sendable {
        /// The guest asked for a seat.
        case joinRequested

        /// The console added the guest's controller at a pad.
        case consoleJoined(pad: UInt8)

        /// The console could not add the controller.
        case consoleJoinFailed

        /// The console removed the guest's controller from a pad.
        case consoleLeft(pad: UInt8)
    }

    /// An invitation step input.
    case invitation(Invitation)

    /// A reply step input.
    case reply(Reply)

    /// An approval step input.
    case approval(Approval)

    /// A verification step input.
    case code(Code)

    /// The native session changed state.
    case state(KakusanStateChange)

    /// A seating step input.
    case seat(Seat)

    /// The host cancelled the attempt.
    case cancel

    /// Hosting ended.
    case hostingEnded
}
