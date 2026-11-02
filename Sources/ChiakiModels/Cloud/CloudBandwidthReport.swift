/// The connection bandwidth a cloud launch measured or reused.
public struct CloudBandwidthReport: Equatable, Sendable {
    /// The bandwidth in kilobits per second.
    public var kbps: Int

    /// How old a reused measurement was, or `nil` when it was measured at launch.
    public var ageSeconds: Int?

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - kbps: The bandwidth.
    ///   - ageSeconds: The age of a reused measurement.
    public init(kbps: Int, ageSeconds: Int? = nil) {
        self.kbps = kbps
        self.ageSeconds = ageSeconds
    }

    /// The bandwidth in whole megabits per second.
    public var rate: String {
        "\(kbps / 1000) Mbps"
    }

    /// The phrase shown in launch progress.
    public var progressDescription: String {
        guard let ageSeconds else {
            return rate
        }
        return ageSeconds < 60
            ? "\(rate) saved moments ago"
            : "\(rate) saved \(ageSeconds / 60) min ago"
    }

    /// The phrase shown in stream statistics.
    public var statisticsDescription: String {
        guard let ageSeconds else {
            return "\(rate), measured at launch"
        }
        return ageSeconds < 60
            ? "\(rate), measured moments before launch"
            : "\(rate), measured \(ageSeconds / 60) min before launch"
    }
}
