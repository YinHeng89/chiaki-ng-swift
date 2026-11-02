/// How the host's seats are used.
public struct KakusanSeatSnapshot: Equatable, Sendable {
    /// The total number of seats.
    public let capacity: Int

    /// Seats used by local players.
    public let local: Int

    /// Seats used by remote guests.
    public let remote: Int

    /// Seats reserved for guests being admitted.
    public let reserved: Int

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - capacity: The total seats.
    ///   - local: The local players.
    ///   - remote: The remote guests.
    ///   - reserved: The reserved seats.
    public init(capacity: Int, local: Int, remote: Int, reserved: Int) {
        self.capacity = capacity
        self.local = local
        self.remote = remote
        self.reserved = reserved
    }

    /// The seats still free.
    public var free: Int {
        max(0, capacity - local - remote - reserved)
    }
}
