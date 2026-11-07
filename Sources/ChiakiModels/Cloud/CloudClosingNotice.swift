import Foundation

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
    public var message: LocalizedStringResource {
        let hours = minutes >= 120
            ? minutes / 60
            : nil
        switch reason {
        case .timeLimit:
            return hours.map { .cloudClosingTimeLimitHours(hours: $0) }
                ?? .cloudClosingTimeLimitMinutes(minutes: minutes)
        case .maintenance:
            return hours.map { .cloudClosingMaintenanceHours(hours: $0) }
                ?? .cloudClosingMaintenanceMinutes(minutes: minutes)
        case .unexplained:
            return hours.map { .cloudClosingUnexplainedHours(hours: $0) }
                ?? .cloudClosingUnexplainedMinutes(minutes: minutes)
        }
    }
}
