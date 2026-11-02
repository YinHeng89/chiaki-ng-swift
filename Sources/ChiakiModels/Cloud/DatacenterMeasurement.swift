import Foundation

/// One cloud datacenter's last measured latency and probe, as the core saves it.
public struct DatacenterMeasurement: Hashable, Sendable {
    /// The longest name accepted, in UTF-8 bytes.
    public static let maximumNameBytes = 256

    /// The most measurements kept per cloud service.
    public static let maximumPerService = 64

    /// The name of the automatic choice, which is never a datacenter.
    public static let automaticName = "Auto"

    /// The datacenter's name.
    public let name: String

    /// The measured round trip in milliseconds.
    public let roundTripMs: Int

    /// The individual round trip samples in milliseconds.
    public let samplesMs: [Int]

    /// The inbound MTU the probe found.
    public let mtuIn: Int

    /// The outbound MTU the probe found.
    public let mtuOut: Int

    /// The port the probe used.
    public let port: Int

    /// The public address the datacenter saw.
    public let publicAddress: String

    /// The largest bandwidth the datacenter offered.
    public let maxBandwidth: Int

    /// When the round trip was measured.
    public let measuredAt: Date

    /// The measured bandwidth, if one was measured.
    public let bandwidth: DatacenterBandwidth?

    /// Describes a measurement.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - roundTripMs: The round trip in milliseconds.
    ///   - samplesMs: The individual samples.
    ///   - mtuIn: The inbound MTU.
    ///   - mtuOut: The outbound MTU.
    ///   - port: The port.
    ///   - publicAddress: The public address.
    ///   - maxBandwidth: The largest bandwidth offered.
    ///   - measuredAt: When it was measured.
    ///   - bandwidth: The measured bandwidth, if any.
    public init(
        name: String,
        roundTripMs: Int,
        samplesMs: [Int] = [],
        mtuIn: Int = 0,
        mtuOut: Int = 0,
        port: Int = 0,
        publicAddress: String = "",
        maxBandwidth: Int = 0,
        measuredAt: Date,
        bandwidth: DatacenterBandwidth? = nil
    ) {
        self.name = name
        self.roundTripMs = roundTripMs
        self.samplesMs = samplesMs
        self.mtuIn = mtuIn
        self.mtuOut = mtuOut
        self.port = port
        self.publicAddress = publicAddress
        self.maxBandwidth = maxBandwidth
        self.measuredAt = measuredAt
        self.bandwidth = bandwidth
    }

    /// Whether a name may be stored: not empty, not the automatic choice, at most
    /// ``maximumNameBytes`` bytes and free of control characters.
    ///
    /// - Parameter name: The candidate name.
    /// - Returns: `true` when the name is valid.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != automaticName && name.utf8.count <= maximumNameBytes
            && !name.unicodeScalars.contains {
                $0.value < 0x20 || $0.value == 0x7F
            }
    }

    /// The measurements a service keeps: valid names and positive round trips only, one per name, fastest
    /// first, at most ``maximumPerService``.
    ///
    /// - Parameter measurements: The candidates.
    /// - Returns: The measurements to keep, in the order they are kept.
    public static func kept(_ measurements: [DatacenterMeasurement]) -> [DatacenterMeasurement] {
        var seen = Set<String>()
        let unique = measurements.filter {
            isValidName($0.name) && $0.roundTripMs > 0 && seen.insert($0.name).inserted
        }
        let sorted = unique.sorted { lhs, rhs in
            lhs.roundTripMs == rhs.roundTripMs
                ? lhs.name < rhs.name
                : lhs.roundTripMs < rhs.roundTripMs
        }
        return Array(sorted.prefix(maximumPerService))
    }
}

/// A bandwidth measured against one datacenter.
public struct DatacenterBandwidth: Hashable, Sendable {
    /// The bandwidth in kilobits per second.
    public let kbps: Int

    /// When it was measured.
    public let measuredAt: Date

    /// The round trip during the measurement, in milliseconds.
    public let roundTripMs: Int

    /// Describes a bandwidth measurement.
    ///
    /// - Parameters:
    ///   - kbps: The bandwidth in kilobits per second.
    ///   - measuredAt: When it was measured.
    ///   - roundTripMs: The round trip during the measurement.
    public init(kbps: Int, measuredAt: Date, roundTripMs: Int) {
        self.kbps = kbps
        self.measuredAt = measuredAt
        self.roundTripMs = roundTripMs
    }
}
