import Foundation

/// The most recent stored bandwidth measurement for a service.
public struct CloudSavedBandwidth: Equatable, Sendable {
    /// The bandwidth in kilobits per second.
    public var kbps: Int

    /// When it was measured.
    public var measuredAt: Date

    /// Creates a saved measurement.
    ///
    /// - Parameters:
    ///   - kbps: The bandwidth.
    ///   - measuredAt: When it was measured.
    public init(kbps: Int, measuredAt: Date) {
        self.kbps = kbps
        self.measuredAt = measuredAt
    }

    /// The settings caption describing the measurement and its age.
    ///
    /// - Parameter now: The current time.
    /// - Returns: The caption.
    public func caption(now: Date) -> LocalizedStringResource {
        let seconds = max(0, Int(now.timeIntervalSince(measuredAt)))
        let mbps = kbps / 1000
        switch seconds {
        case ..<60:
            return .cloudSavedBandwidthMomentsAgo(mbps: mbps)
        case ..<3600:
            return .cloudSavedBandwidthMinutesAgo(mbps: mbps, minutes: seconds / 60)
        case ..<86400:
            return .cloudSavedBandwidthHoursAgo(mbps: mbps, hours: seconds / 3600)
        default:
            return .cloudSavedBandwidthDaysAgo(mbps: mbps, days: seconds / 86400)
        }
    }
}
