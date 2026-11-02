import Foundation

/// A stored datacenter probe result, with the bandwidth measured there when known.
public struct CloudDatacenterMeasurement: Codable, Equatable, Sendable {
    /// The datacenter's name.
    public var name: String

    /// The round trip in milliseconds.
    public var rttMs: Int

    /// The individual round trips of the probe.
    public var rttsMs: [Int]

    /// The inbound MTU.
    public var mtuIn: Int

    /// The outbound MTU.
    public var mtuOut: Int

    /// The probe port.
    public var port: Int

    /// The public address the datacenter saw.
    public var publicIP: String

    /// The datacenter's advertised maximum bandwidth.
    public var maxBandwidth: Int

    /// When the probe ran.
    public var measuredAt: Date

    /// The bandwidth measured there, in kilobits per second.
    public var bandwidthKbps: Int?

    /// When the bandwidth was measured.
    public var bandwidthMeasuredAt: Date?

    /// The round trip during the bandwidth measurement.
    public var bandwidthRttMs: Int?

    /// Creates a measurement.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - rttMs: The round trip.
    ///   - rttsMs: The individual round trips.
    ///   - mtuIn: The inbound MTU.
    ///   - mtuOut: The outbound MTU.
    ///   - port: The probe port.
    ///   - publicIP: The public address.
    ///   - maxBandwidth: The advertised maximum bandwidth.
    ///   - measuredAt: When the probe ran.
    ///   - bandwidthKbps: The measured bandwidth.
    ///   - bandwidthMeasuredAt: When the bandwidth was measured.
    ///   - bandwidthRttMs: The round trip during the bandwidth measurement.
    public init(
        name: String,
        rttMs: Int,
        rttsMs: [Int] = [],
        mtuIn: Int = 0,
        mtuOut: Int = 0,
        port: Int = 0,
        publicIP: String = "",
        maxBandwidth: Int = 0,
        measuredAt: Date,
        bandwidthKbps: Int? = nil,
        bandwidthMeasuredAt: Date? = nil,
        bandwidthRttMs: Int? = nil
    ) {
        self.name = name
        self.rttMs = rttMs
        self.rttsMs = rttsMs
        self.mtuIn = mtuIn
        self.mtuOut = mtuOut
        self.port = port
        self.publicIP = publicIP
        self.maxBandwidth = maxBandwidth
        self.measuredAt = measuredAt
        self.bandwidthKbps = bandwidthKbps
        self.bandwidthMeasuredAt = bandwidthMeasuredAt
        self.bandwidthRttMs = bandwidthRttMs
    }

    /// Reports whether a probe row carries the same probe results as this measurement, ignoring timestamps
    /// and bandwidth tests.
    ///
    /// - Parameter row: The probe row to compare against.
    /// - Returns: `true` when the name, round trips, MTUs, port, public address and advertised bandwidth all
    ///   match.
    func sameProbe(as row: CloudDatacenterPingRow) -> Bool {
        name == row.name && rttMs == row.rtt && rttsMs == row.rtts && mtuIn == row.mtuIn
            && mtuOut == row.mtuOut && port == row.port && publicIP == row.publicIP
            && maxBandwidth == row.maxBandwidth
    }
}

/// One datacenter row of a cloud probe, in the service's JSON shape.
///
/// Decoding defaults every missing field, so a partial row still decodes.
public struct CloudDatacenterPingRow: Codable, Equatable, Sendable {
    /// The datacenter's name.
    public var name: String

    /// The round trip in milliseconds.
    public var rtt: Int

    /// The individual round trips.
    public var rtts: [Int]

    /// The inbound MTU.
    public var mtuIn: Int

    /// The outbound MTU.
    public var mtuOut: Int

    /// The probe port.
    public var port: Int

    /// The public address the datacenter saw.
    public var publicIP: String

    /// The advertised maximum bandwidth.
    public var maxBandwidth: Int

    /// Whether the datacenter answered the probe.
    public var measured: Bool

    /// Maps each property to the key the cloud service uses in its JSON.
    enum CodingKeys: String, CodingKey {
        /// The datacenter name, sent as `dataCenter`.
        case name = "dataCenter"
        /// The averaged round trip.
        case rtt
        /// The individual round trips.
        case rtts
        /// The inbound MTU, sent as `mtu_in`.
        case mtuIn = "mtu_in"
        /// The outbound MTU, sent as `mtu_out`.
        case mtuOut = "mtu_out"
        /// The probe port.
        case port
        /// The public address, sent as `publicIp`.
        case publicIP = "publicIp"
        /// The advertised maximum bandwidth.
        case maxBandwidth
        /// Whether the datacenter answered.
        case measured
    }

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - rtt: The round trip.
    ///   - rtts: The individual round trips.
    ///   - mtuIn: The inbound MTU.
    ///   - mtuOut: The outbound MTU.
    ///   - port: The probe port.
    ///   - publicIP: The public address.
    ///   - maxBandwidth: The advertised maximum bandwidth.
    ///   - measured: Whether it answered.
    public init(
        name: String,
        rtt: Int,
        rtts: [Int],
        mtuIn: Int,
        mtuOut: Int,
        port: Int,
        publicIP: String,
        maxBandwidth: Int,
        measured: Bool
    ) {
        self.name = name
        self.rtt = rtt
        self.rtts = rtts
        self.mtuIn = mtuIn
        self.mtuOut = mtuOut
        self.port = port
        self.publicIP = publicIP
        self.maxBandwidth = maxBandwidth
        self.measured = measured
    }

    /// Recreates the row a stored measurement came from.
    ///
    /// - Parameter measurement: The stored measurement.
    public init(_ measurement: CloudDatacenterMeasurement) {
        self.init(
            name: measurement.name,
            rtt: measurement.rttMs,
            rtts: measurement.rttsMs,
            mtuIn: measurement.mtuIn,
            mtuOut: measurement.mtuOut,
            port: measurement.port,
            publicIP: measurement.publicIP,
            maxBandwidth: measurement.maxBandwidth,
            measured: true
        )
    }

    /// Decodes a row, defaulting missing fields.
    ///
    /// - Parameter decoder: The decoder holding the row.
    /// - Throws: `DecodingError` when a present field has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        rtt = try values.decodeIfPresent(Int.self, forKey: .rtt) ?? 0
        rtts = try values.decodeIfPresent([Int].self, forKey: .rtts) ?? []
        mtuIn = try values.decodeIfPresent(Int.self, forKey: .mtuIn) ?? 0
        mtuOut = try values.decodeIfPresent(Int.self, forKey: .mtuOut) ?? 0
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? 0
        publicIP = try values.decodeIfPresent(String.self, forKey: .publicIP) ?? ""
        maxBandwidth = try values.decodeIfPresent(Int.self, forKey: .maxBandwidth) ?? 0
        measured = try values.decodeIfPresent(Bool.self, forKey: .measured) ?? false
    }
}
