import ChiakiModels
import Foundation

/// The datacenter store as the C++ datacenter store adapter reaches it through ``CoreStoreGateway``.
///
/// Every method takes and returns only what the generated C++ header can represent. Failures come back as
/// `false` or `nil`; the cause is reported by the store itself.
public final class CoreDatacenterGateway {
    private let datacenters: any DatacenterStoring

    /// Creates the gateway over the datacenter store.
    ///
    /// - Parameter datacenters: Where datacenter measurements are persisted.
    init(datacenters: any DatacenterStoring) {
        self.datacenters = datacenters
    }

    /// Loads a service's datacenter measurements.
    ///
    /// - Parameter service: The cloud service.
    /// - Returns: The ledger, or `nil` when the store could not be read.
    public func loadDatacenters(_ service: CoreCloudService) -> CoreDatacenterLedger? {
        do {
            return try CoreDatacenterLedger(datacenters.measurements(for: service.service))
        } catch {
            return nil
        }
    }

    /// Starts an empty batch of measurements for a C++ adapter to fill with `CoreDatacenterLedger/add`.
    ///
    /// - Returns: The empty batch.
    public func newDatacenterBatch() -> CoreDatacenterLedger {
        CoreDatacenterLedger([])
    }

    /// Replaces a service's measurements with a batch.
    ///
    /// - Parameters:
    ///   - batch: The batch.
    ///   - service: The cloud service.
    /// - Returns: `true` when the measurements were saved.
    public func saveDatacenters(_ batch: CoreDatacenterLedger, for service: CoreCloudService) -> Bool {
        do {
            try datacenters.save(batch.assembled, for: service.service)
            return true
        } catch {
            return false
        }
    }
}

/// A service's datacenter measurements, loaded for a C++ store adapter or assembled by one before a save.
public final class CoreDatacenterLedger {
    /// The loaded measurements, fastest first.
    public let measurements: [CoreDatacenterRecord]

    private var drafts: [CoreDatacenterDraft] = []

    /// Mirrors a load from the datacenter store.
    ///
    /// - Parameter measurements: The loaded measurements.
    init(_ measurements: [DatacenterMeasurement]) {
        self.measurements = measurements.map(CoreDatacenterRecord.init)
    }

    /// The measurements the store adapter added for saving, in the order it added them.
    var assembled: [DatacenterMeasurement] {
        drafts.map(\.measurement)
    }

    /// Adds a measurement to save, for the store adapter to fill in.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - roundTripMs: The round trip in milliseconds.
    ///   - measuredAt: When it was measured, in milliseconds since 1970.
    /// - Returns: The measurement's draft.
    public func add(name: String, roundTripMs: Int32, measuredAt: Int64) -> CoreDatacenterDraft {
        let draft = CoreDatacenterDraft(name: name, roundTripMs: roundTripMs, measuredAt: measuredAt)
        drafts.append(draft)
        return draft
    }
}

/// One datacenter measurement a C++ store adapter assembles in a ``CoreDatacenterLedger`` before a save.
///
/// Times are whole milliseconds since 1970.
public final class CoreDatacenterDraft {
    private let name: String
    private let roundTripMs: Int
    private let measuredAt: Date
    private var samplesMs: [Int] = []
    private var mtuIn = 0
    private var mtuOut = 0
    private var port = 0
    private var publicAddress = ""
    private var maxBandwidth = 0
    private var bandwidth: DatacenterBandwidth?

    /// Starts a measurement.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - roundTripMs: The round trip in milliseconds.
    ///   - measuredAt: When it was measured, in milliseconds since 1970.
    init(name: String, roundTripMs: Int32, measuredAt: Int64) {
        self.name = name
        self.roundTripMs = Int(roundTripMs)
        self.measuredAt = Timestamp.date(milliseconds: measuredAt)
    }

    /// Copies the individual round trip samples.
    ///
    /// - Parameters:
    ///   - samples: The samples in milliseconds, or `nil` when there are none.
    ///   - count: How many samples.
    public func setSamples(_ samples: UnsafePointer<Int32>?, count: Int) {
        samplesMs = samples.map {
            UnsafeBufferPointer(start: $0, count: count).map(Int.init)
        } ?? []
    }

    /// Sets the route the probe found to the datacenter.
    ///
    /// - Parameters:
    ///   - mtuIn: The inbound MTU.
    ///   - mtuOut: The outbound MTU.
    ///   - port: The port.
    ///   - publicAddress: The public address.
    ///   - maxBandwidth: The largest bandwidth offered.
    public func setRoute(
        mtuIn: Int32,
        mtuOut: Int32,
        port: Int32,
        publicAddress: String,
        maxBandwidth: Int32
    ) {
        self.mtuIn = Int(mtuIn)
        self.mtuOut = Int(mtuOut)
        self.port = Int(port)
        self.publicAddress = publicAddress
        self.maxBandwidth = Int(maxBandwidth)
    }

    /// Sets the measured bandwidth.
    ///
    /// - Parameters:
    ///   - kbps: The measured bandwidth, or zero when none was measured.
    ///   - measuredAt: When the bandwidth was measured, in milliseconds since 1970.
    ///   - roundTripMs: The round trip during the bandwidth measurement.
    public func setBandwidth(kbps: Int32, measuredAt: Int64, roundTripMs: Int32) {
        bandwidth = kbps > 0
            ? DatacenterBandwidth(
                kbps: Int(kbps),
                measuredAt: Timestamp.date(milliseconds: measuredAt),
                roundTripMs: Int(roundTripMs)
            )
            : nil
    }

    /// The assembled measurement.
    var measurement: DatacenterMeasurement {
        DatacenterMeasurement(
            name: name,
            roundTripMs: roundTripMs,
            samplesMs: samplesMs,
            mtuIn: mtuIn,
            mtuOut: mtuOut,
            port: port,
            publicAddress: publicAddress,
            maxBandwidth: maxBandwidth,
            measuredAt: measuredAt,
            bandwidth: bandwidth
        )
    }
}

/// A saved datacenter measurement as the C++ store adapters read it. Times are milliseconds since 1970.
public struct CoreDatacenterRecord {
    /// The datacenter's name.
    public let name: String

    /// The round trip in milliseconds.
    public let roundTripMs: Int32

    /// The individual round trip samples in milliseconds.
    public let samplesMs: [Int32]

    /// The inbound MTU.
    public let mtuIn: Int32

    /// The outbound MTU.
    public let mtuOut: Int32

    /// The port.
    public let port: Int32

    /// The public address.
    public let publicAddress: String

    /// The largest bandwidth offered.
    public let maxBandwidth: Int32

    /// When the round trip was measured.
    public let measuredAt: Int64

    /// The measured bandwidth in kilobits per second, or zero when none was measured.
    public let bandwidthKbps: Int32

    /// When the bandwidth was measured, or zero.
    public let bandwidthMeasuredAt: Int64

    /// The round trip during the bandwidth measurement, or zero.
    public let bandwidthRoundTripMs: Int32

    /// Mirrors a measurement.
    ///
    /// - Parameter measurement: The measurement.
    init(_ measurement: DatacenterMeasurement) {
        name = measurement.name
        roundTripMs = Int32(clamping: measurement.roundTripMs)
        samplesMs = measurement.samplesMs.map {
            Int32(clamping: $0)
        }
        mtuIn = Int32(clamping: measurement.mtuIn)
        mtuOut = Int32(clamping: measurement.mtuOut)
        port = Int32(clamping: measurement.port)
        publicAddress = measurement.publicAddress
        maxBandwidth = Int32(clamping: measurement.maxBandwidth)
        measuredAt = Timestamp.milliseconds(of: measurement.measuredAt)
        bandwidthKbps = Int32(clamping: measurement.bandwidth?.kbps ?? 0)
        bandwidthMeasuredAt = measurement.bandwidth.map {
            Timestamp.milliseconds(of: $0.measuredAt)
        } ?? 0
        bandwidthRoundTripMs = Int32(clamping: measurement.bandwidth?.roundTripMs ?? 0)
    }
}

/// A cloud streaming service as the C++ store adapters see it.
public enum CoreCloudService {
    /// The older PS Now service.
    case psNow

    /// The PS5 cloud service.
    case psCloud

    /// The model service.
    var service: CloudService {
        switch self {
        case .psNow:
            .psNow
        case .psCloud:
            .psCloud
        }
    }
}
