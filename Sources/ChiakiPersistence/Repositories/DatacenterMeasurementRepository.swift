import ChiakiModels
import Foundation
import GRDB

/// The cloud datacenter measurements in the `datacenter_measurements` table, and their only writer.
///
/// The core and the app both save through here. Every save replaces a service's rows in one transaction, after
/// dropping invalid names and keeping the fastest `ChiakiModels/DatacenterMeasurement/maximumPerService`, so
/// two writers can no longer overwrite each other's read-modify-write of one shared settings document. The
/// user's datacenter choices stay in the settings table.
public final class DatacenterMeasurementRepository: DatacenterStoring {
    private let database: AppDatabase
    private let report: @Sendable (PersistenceError) -> Void

    /// Creates the repository over the app database.
    ///
    /// - Parameters:
    ///   - database: The open database.
    ///   - report: Receives every storage failure before it is turned into a
    ///     `ChiakiModels/DatacenterStoreFailure`. Ignored by default.
    public init(database: AppDatabase, report: @escaping @Sendable (PersistenceError) -> Void = { _ in }) {
        self.database = database
        self.report = report
    }

    /// Loads a service's measurements.
    ///
    /// - Parameter service: The cloud service.
    /// - Returns: The measurements, fastest first.
    /// - Throws: `ChiakiModels/DatacenterStoreFailure/unavailable` when the table cannot be read.
    public func measurements(for service: CloudService) throws(DatacenterStoreFailure)
        -> [DatacenterMeasurement] {
        try reporting { () throws(PersistenceError) in
            try database.read { database in
                try DatacenterMeasurementRow.fetchAll(
                    database, sql: DatacenterMeasurementRow.selectForService, arguments: [service.rawValue]
                )
            }
        }
        .compactMap(\.measurement)
    }

    /// Replaces a service's measurements with the ones it keeps.
    ///
    /// - Parameters:
    ///   - measurements: The new measurements.
    ///   - service: The cloud service.
    /// - Throws: `ChiakiModels/DatacenterStoreFailure/unavailable` when the write failed.
    public func save(
        _ measurements: [DatacenterMeasurement],
        for service: CloudService
    ) throws(DatacenterStoreFailure) {
        let kept = DatacenterMeasurement.kept(measurements)
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(
                    sql: DatacenterMeasurementRow.deleteForService,
                    arguments: [service.rawValue]
                )
                for measurement in kept {
                    try database.execute(
                        sql: DatacenterMeasurementRow.insert,
                        arguments: DatacenterMeasurementRow.insertArguments(measurement, service: service)
                    )
                }
            }
        }
    }

    /// Forgets every measurement of every service.
    ///
    /// - Throws: `ChiakiModels/DatacenterStoreFailure/unavailable` when the delete failed.
    public func forgetAll() throws(DatacenterStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(sql: DatacenterMeasurementRow.deleteAll)
            }
        }
    }

    private func reporting<Result>(_ body: () throws(PersistenceError)
        -> Result) throws(DatacenterStoreFailure)
        -> Result {
        do {
            return try body()
        } catch {
            report(error)
            throw .unavailable
        }
    }
}

/// One row of the `datacenter_measurements` table, decoded by column name.
private struct DatacenterMeasurementRow: FetchableRecord, Sendable {
    /// Selects a service's measurements, fastest first.
    static let selectForService = """
    SELECT name, round_trip_ms, samples_ms, mtu_in, mtu_out, port, public_address, max_bandwidth, measured_at,
           bandwidth_kbps, bandwidth_measured_at, bandwidth_round_trip_ms
    FROM datacenter_measurements WHERE service = ? ORDER BY round_trip_ms, name
    """

    /// Deletes a service's measurements.
    static let deleteForService = "DELETE FROM datacenter_measurements WHERE service = ?"

    /// Deletes every measurement.
    static let deleteAll = "DELETE FROM datacenter_measurements"

    /// Inserts one measurement.
    static let insert = """
    INSERT INTO datacenter_measurements(service, name, round_trip_ms, samples_ms, mtu_in, mtu_out, port,
        public_address, max_bandwidth, measured_at, bandwidth_kbps, bandwidth_measured_at, bandwidth_round_trip_ms)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    /// The measurement the row holds, or `nil` when a column breaks its schema.
    let measurement: DatacenterMeasurement?

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectForService``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        let samples = try row.decode(String.self, forColumn: "samples_ms")
        let bandwidth: DatacenterBandwidth? = if let kbps = try row.decode(
            Int64?.self,
            forColumn: "bandwidth_kbps"
        ),
            let measured = try row.decode(
                Int64?.self,
                forColumn: "bandwidth_measured_at"
            ),
            let roundTrip = try row.decode(
                Int64?.self,
                forColumn: "bandwidth_round_trip_ms"
            ) {
            DatacenterBandwidth(
                kbps: Int(kbps),
                measuredAt: Timestamp.date(milliseconds: measured),
                roundTripMs: Int(roundTrip)
            )
        } else {
            nil
        }
        guard let decoded = try? JSONDecoder().decode([Int].self, from: Data(samples.utf8)) else {
            measurement = nil
            return
        }
        measurement = try DatacenterMeasurement(
            name: row.decode(String.self, forColumn: "name"),
            roundTripMs: Int(row.decode(Int64.self, forColumn: "round_trip_ms")),
            samplesMs: decoded,
            mtuIn: Int(row.decode(Int64.self, forColumn: "mtu_in")),
            mtuOut: Int(row.decode(Int64.self, forColumn: "mtu_out")),
            port: Int(row.decode(Int64.self, forColumn: "port")),
            publicAddress: row.decode(String.self, forColumn: "public_address"),
            maxBandwidth: Int(row.decode(Int64.self, forColumn: "max_bandwidth")),
            measuredAt: Timestamp.date(milliseconds: row.decode(Int64.self, forColumn: "measured_at")),
            bandwidth: bandwidth
        )
    }

    /// The arguments of ``insert`` for one measurement.
    ///
    /// - Parameters:
    ///   - measurement: The measurement.
    ///   - service: The cloud service.
    /// - Returns: The statement arguments.
    /// - Throws: An encoding error for the samples, which cannot happen for integers.
    static func insertArguments(_ measurement: DatacenterMeasurement, service: CloudService) throws
        -> StatementArguments {
        let samples = try String(bytes: JSONEncoder().encode(measurement.samplesMs), encoding: .utf8) ?? ""
        return [
            service.rawValue, measurement.name, Int64(measurement.roundTripMs), samples,
            Int64(measurement.mtuIn),
            Int64(measurement.mtuOut), Int64(measurement.port), measurement.publicAddress,
            Int64(measurement.maxBandwidth), Timestamp.milliseconds(of: measurement.measuredAt),
            measurement.bandwidth.map {
                Int64($0.kbps)
            },
            measurement.bandwidth.map {
                Timestamp.milliseconds(of: $0.measuredAt)
            },
            measurement.bandwidth.map {
                Int64($0.roundTripMs)
            }
        ]
    }
}
