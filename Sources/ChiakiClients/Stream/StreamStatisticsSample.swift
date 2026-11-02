import ChiakiModels
import Foundation

/// One reading of the player's statistics.
public struct StreamStatisticsSample: Equatable, Sendable {
    /// The statistics, or `nil` while no player runs.
    public let statistics: RenderStatistics?

    /// When the reading was taken, in seconds of system uptime.
    public let uptime: Double

    /// Records a reading.
    ///
    /// - Parameters:
    ///   - statistics: The statistics, or `nil` while no player runs.
    ///   - uptime: When the reading was taken, in seconds of system uptime.
    public init(statistics: RenderStatistics?, uptime: Double) {
        self.statistics = statistics
        self.uptime = uptime
    }
}
