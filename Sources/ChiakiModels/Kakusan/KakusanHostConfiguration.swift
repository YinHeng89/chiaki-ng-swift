/// What a Kakusan host arms the native session with.
public struct KakusanHostConfiguration: Equatable, Sendable {
    /// The total seats.
    public let capacity: Int

    /// The seats taken by local players.
    public let localSeats: Int

    /// The media tuning.
    public let tuning: KakusanMediaTuning

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - capacity: The total seats.
    ///   - localSeats: The local seats.
    ///   - tuning: The media tuning.
    public init(
        capacity: Int,
        localSeats: Int,
        tuning: KakusanMediaTuning = KakusanMediaTuning()
    ) {
        self.capacity = capacity
        self.localSeats = localSeats
        self.tuning = tuning
    }
}
