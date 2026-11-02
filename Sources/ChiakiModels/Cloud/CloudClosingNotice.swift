/// The cloud service's warning that it will close the game soon.
public struct CloudClosingNotice: Equatable, Sendable {
    /// Why the service closes the game.
    public enum Reason: Equatable, Sendable {
        /// The streaming time limit runs out.
        case timeLimit

        /// The streaming server goes down for maintenance.
        case maintenance

        /// The service gave no reason.
        case unexplained
    }

    /// How long the warning stays.
    public static let shownFor = Duration.seconds(12)

    /// The minutes left before the game closes, never negative.
    public let minutes: Int

    /// Why the game closes.
    public let reason: Reason

    /// Describes a warning.
    ///
    /// - Parameters:
    ///   - minutes: The minutes left; a negative count reads as zero.
    ///   - reason: Why the game closes.
    public init(minutes: Int, reason: Reason) {
        self.minutes = max(0, minutes)
        self.reason = reason
    }

    /// The warning shown over the game.
    public var message: String {
        switch reason {
        case .timeLimit:
            "The game closes in \(remaining) because of the streaming time limit. Save your progress."
        case .maintenance:
            "The streaming server goes down for maintenance in \(remaining) and the game will close. "
                + "Save your progress."
        case .unexplained:
            "The streaming service closes the game in \(remaining). Save your progress."
        }
    }

    private var remaining: String {
        if minutes >= 120 {
            return "\(minutes / 60) hours"
        }
        return minutes == 1
            ? "1 minute"
            : "\(minutes) minutes"
    }
}
