import Foundation

/// Something the players are told about the seats, shown briefly over the stream.
public enum CouchNotice: Equatable, Sendable {
    /// A player joined on a pad, with their light colour if known.
    case joined(pad: UInt8, player: CouchPlayer, color: UInt32?)
    /// A player could not join on a pad.
    case joinFailed(pad: UInt8, failure: CouchFailure)
    /// The console dropped the player on a pad.
    case released(pad: UInt8)
    /// A seated player's controller disconnected.
    case disconnected(pad: UInt8)
    /// A seated player was removed.
    case left(pad: UInt8)
    /// A player switched to another controller.
    case switched(pad: UInt8, device: ControllerDevice)
    /// News about remote play guests.
    case remote(KakusanHostNotice)
}

/// A notice shown over the stream, with an identifier so it can be dismissed on its own.
public struct CouchNoticeItem: Equatable, Sendable, Identifiable {
    /// Identifies the notice for dismissal.
    public let id: UUID
    /// What the notice says.
    public let notice: CouchNotice

    /// Creates a notice item.
    ///
    /// - Parameters:
    ///   - id: Identifies the notice for dismissal.
    ///   - notice: What the notice says.
    public init(id: UUID, notice: CouchNotice) {
        self.id = id
        self.notice = notice
    }
}

/// Why a couch guest's controller could not join the stream.
public enum CouchFailure: Equatable, Sendable {
    /// The join request was never sent, with the core's cause when known.
    case notSent(StreamOutcome.Cause?)

    /// The console refused with the given status.
    case refused(Int)

    /// The console did not answer in time.
    case timedOut

    /// Every passcode attempt was used.
    case passcodeAttempts

    /// The guest's account is not on the console.
    case accountUnresolvable
}
