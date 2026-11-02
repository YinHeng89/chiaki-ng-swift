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
    public func caption(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(measuredAt)))
        let age: String
        switch seconds {
        case ..<60:
            age = "moments ago"
        case ..<3600:
            age = "\(seconds / 60) min ago"
        case ..<86400:
            age = "\(seconds / 3600) h ago"
        default:
            age = "\(seconds / 86400) days ago"
        }
        return "Measured your connection at \(kbps / 1000) Mbps \(age). "
            + "Measures again at launch when that is out of date."
    }
}
