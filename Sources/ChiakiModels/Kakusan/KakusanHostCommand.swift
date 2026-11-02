import Foundation

/// A command a Kakusan host sends to the native session.
public enum KakusanHostCommand: Equatable, Sendable {
    /// Enter the code a guest reads out.
    case enterCode(KakusanGuestID, KakusanCode)

    /// Seat a guest, preferably at a console seat, with its controller type and account.
    case giveSeat(KakusanGuestID, preferred: UInt8?, controllerType: UInt8, accountID: Data?)

    /// Remove a guest.
    case remove(KakusanGuestID)

    /// Change the number of local players.
    case setLocalSeats(Int)

    /// Change the total seats.
    case setCapacity(Int)

    /// Change the media tuning.
    case setTuning(KakusanMediaTuning)
}
