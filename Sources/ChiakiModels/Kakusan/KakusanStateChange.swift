/// A state change reported by the native Kakusan session.
public struct KakusanStateChange: Equatable, Sendable {
    /// The new state.
    public let state: KakusanSessionState

    /// The error, when the session failed.
    public let error: KakusanError?

    /// The reason, when it closed without an error.
    public let reason: KakusanReason?

    /// Whether the other participant caused the change.
    public let byPeer: Bool

    /// The guest's seat, once granted.
    public let seat: Int?

    /// The seat grant's generation; 0 means no grant.
    public let generation: UInt32

    /// The console seat the guest's controller uses.
    public let consoleSeat: UInt8?

    /// The seat reserved for the guest while admitting.
    public let reservedSeat: UInt8?

    /// Creates a change.
    ///
    /// - Parameters:
    ///   - state: The new state.
    ///   - error: The error.
    ///   - reason: The reason.
    ///   - byPeer: Whether the peer caused it.
    ///   - seat: The granted seat.
    ///   - generation: The grant generation.
    ///   - consoleSeat: The console seat.
    ///   - reservedSeat: The reserved seat.
    public init(
        state: KakusanSessionState,
        error: KakusanError? = nil,
        reason: KakusanReason? = nil,
        byPeer: Bool = false,
        seat: Int? = nil,
        generation: UInt32 = 0,
        consoleSeat: UInt8? = nil,
        reservedSeat: UInt8? = nil
    ) {
        self.state = state
        self.error = error
        self.reason = reason
        self.byPeer = byPeer
        self.seat = seat
        self.generation = generation
        self.consoleSeat = consoleSeat
        self.reservedSeat = reservedSeat
    }

    /// The seat grant, when the change carries a valid one.
    public var grant: KakusanSeatGrant? {
        guard let seat, (1 ... Int(UInt8.max)).contains(seat), generation != 0 else {
            return nil
        }
        return KakusanSeatGrant(seat: seat, generation: generation)
    }
}
