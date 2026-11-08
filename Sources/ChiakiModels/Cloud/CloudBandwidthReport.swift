import Foundation

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
    public var rate: LocalizedStringResource {
        .cloudBandwidthRate(mbps: megabits)
    }

    /// The phrase shown in launch progress.
    public var progressDescription: LocalizedStringResource {
        guard let ageSeconds else {
            return rate
        }
        return ageSeconds < 60
            ? .cloudBandwidthSavedMomentsAgo(mbps: megabits)
            : .cloudBandwidthSavedMinutesAgo(mbps: megabits, minutes: ageSeconds / 60)
    }

    /// The phrase shown in stream statistics.
    public var statisticsDescription: LocalizedStringResource {
        guard let ageSeconds else {
            return .cloudBandwidthMeasuredAtLaunch(mbps: megabits)
        }
        return ageSeconds < 60
            ? .cloudBandwidthMeasuredMomentsBefore(mbps: megabits)
            : .cloudBandwidthMeasuredMinutesBefore(mbps: megabits, minutes: ageSeconds / 60)
    }

    private var megabits: Int {
        kbps / 1000
    }
}
