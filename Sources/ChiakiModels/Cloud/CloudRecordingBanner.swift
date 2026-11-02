/// The PS5 cloud console's banner while it records a clip.
public struct CloudRecordingBanner: Equatable, Sendable {
    /// How long the clip has recorded, as the console writes it, such as `00:10`.
    public let elapsed: String

    /// Describes the banner.
    ///
    /// - Parameter elapsed: How long the clip has recorded.
    public init(elapsed: String) {
        self.elapsed = elapsed
    }
}
