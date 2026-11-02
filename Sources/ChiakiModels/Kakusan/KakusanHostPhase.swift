import Foundation

/// Where a host's attempt for one guest is.
public enum KakusanHostPhase: Equatable, Sendable {
    /// The invitation is being created by the operation with the given id.
    case preparing(UUID)

    /// The invitation is out; the reply is being awaited or imported.
    case invitation(KakusanInvitation, KakusanReplyImport)

    /// The guest is connecting.
    case connecting(KakusanApproval)

    /// The codes are being compared.
    case verifying(KakusanApproval, KakusanVerification)

    /// The guest is being seated.
    case admitting(KakusanAdmission)

    /// Seated, waiting for the guest to be ready.
    case readying(KakusanSeatGrant, pad: UInt8)

    /// Playing.
    case active(KakusanSeatGrant, pad: UInt8)

    /// Closing with the outcome.
    case closing(KakusanAttemptOutcome)

    /// Ended with the outcome.
    case ended(KakusanAttemptOutcome)
}

/// Where seating a verified guest is.
public enum KakusanAdmission: Equatable, Sendable {
    /// Waiting for a free seat.
    case awaitingSeat

    /// Waiting for the console to add the controller.
    case awaitingConsole

    /// A seat and console pad are reserved.
    case reserved(KakusanSeatGrant, pad: UInt8)

    /// The console added the controller at the pad.
    case consoleJoined(pad: UInt8)

    /// The pad, once the console has joined it.
    public var pad: UInt8? {
        if case .consoleJoined(let pad) = self {
            return pad
        }
        return nil
    }
}

/// Where the host's approval of a guest is.
public enum KakusanApproval: Equatable, Sendable {
    /// Not yet given.
    case pending

    /// Being sent by the operation with the given id.
    case sending(UUID)

    /// Given.
    case granted
}

/// Where importing a guest's reply is.
public enum KakusanReplyImport: Equatable, Sendable {
    /// Waiting for the host to paste it.
    case awaiting

    /// Being imported by the operation with the given id.
    case importing(UUID)

    /// Refused; the host may paste again.
    case rejected(KakusanError)
}

/// A seat granted to a guest, with the generation that tells a later grant of the same seat apart.
public struct KakusanSeatGrant: Equatable, Sendable {
    /// The seat, from 1.
    public let seat: Int

    /// The grant's generation.
    public let generation: UInt32

    /// Creates a grant.
    ///
    /// - Parameters:
    ///   - seat: The seat.
    ///   - generation: The generation.
    public init(seat: Int, generation: UInt32) {
        self.seat = seat
        self.generation = generation
    }
}

/// An invitation block and when it expires.
public struct KakusanInvitation: Equatable, Sendable {
    /// The block to send to the guest.
    public let block: KakusanBlock

    /// When it expires.
    public let expiresAt: Date

    /// Creates an invitation.
    ///
    /// - Parameters:
    ///   - block: The block.
    ///   - expiresAt: The expiry.
    public init(block: KakusanBlock, expiresAt: Date) {
        self.block = block
        self.expiresAt = expiresAt
    }
}
