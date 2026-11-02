import Foundation

/// The stored datacenter choices and probe measurements for each cloud service.
public struct CloudDatacenterSettings: Codable, Equatable, Sendable {
    /// The longest datacenter name kept, in UTF-8 bytes.
    public static let maximumNameBytes = 256
    /// The most measurements kept per service.
    public static let maximumMeasurements = 64

    /// The datacenter chosen for PS Now, or `nil` for automatic.
    public var psNowChoice: String?
    /// The datacenter chosen for PS Cloud, or `nil` for automatic.
    public var psCloudChoice: String?
    /// The PS Now measurements, fastest first.
    public var psNowMeasurements: [CloudDatacenterMeasurement] = []
    /// The PS Cloud measurements, fastest first.
    public var psCloudMeasurements: [CloudDatacenterMeasurement] = []
    /// Whether launch offers a datacenter choice.
    public var selectsAtLaunch = true
    /// The datacenter the last stream connected to.
    public var lastConnection: CloudDatacenterConnection?

    /// The JSON keys the settings are stored under.
    enum CodingKeys: String, CodingKey {
        /// The PS Now choice.
        case psNowChoice
        /// The PS Cloud choice.
        case psCloudChoice
        /// The PS Now measurements.
        case psNowMeasurements
        /// The PS Cloud measurements.
        case psCloudMeasurements
        /// Whether launch offers a datacenter choice.
        case selectsAtLaunch
        /// The datacenter the last stream connected to.
        case lastConnection
    }

    /// Creates empty settings that select at launch.
    public init() {
    }

    /// Decodes settings, defaulting missing fields and dropping an unreadable last connection.
    ///
    /// - Parameter decoder: The decoder holding the settings.
    /// - Throws: `DecodingError` when a present field has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        psNowChoice = try values.decodeIfPresent(String.self, forKey: .psNowChoice)
        psCloudChoice = try values.decodeIfPresent(String.self, forKey: .psCloudChoice)
        psNowMeasurements = try values.decodeIfPresent(
            [CloudDatacenterMeasurement].self, forKey: .psNowMeasurements
        ) ?? []
        psCloudMeasurements = try values.decodeIfPresent(
            [CloudDatacenterMeasurement].self, forKey: .psCloudMeasurements
        ) ?? []
        selectsAtLaunch = try values.decodeIfPresent(Bool.self, forKey: .selectsAtLaunch) ?? true
        lastConnection = try? values.decodeIfPresent(CloudDatacenterConnection.self, forKey: .lastConnection)
    }

    /// The datacenter chosen for a service.
    ///
    /// - Parameter service: The service.
    /// - Returns: The chosen name, or `nil` for automatic.
    public func choice(for service: CloudDatacenterService) -> String? {
        switch service {
        case .psNow:
            psNowChoice
        case .psCloud:
            psCloudChoice
        }
    }

    /// Chooses a datacenter for a service, dropping an invalid name.
    ///
    /// - Parameters:
    ///   - name: The datacenter, or `nil` for automatic.
    ///   - service: The service.
    public mutating func setChoice(_ name: String?, for service: CloudDatacenterService) {
        let value = name.flatMap { Self.validName($0) }
        switch service {
        case .psNow:
            psNowChoice = value
        case .psCloud:
            psCloudChoice = value
        }
    }

    /// The measurements for a service.
    ///
    /// - Parameter service: The service.
    /// - Returns: The measurements, fastest first.
    public func measurements(for service: CloudDatacenterService) -> [CloudDatacenterMeasurement] {
        switch service {
        case .psNow:
            psNowMeasurements
        case .psCloud:
            psCloudMeasurements
        }
    }

    /// Replaces a service's measurements, sorting by round trip and keeping at most ``maximumMeasurements``.
    ///
    /// - Parameters:
    ///   - value: The measurements.
    ///   - service: The service.
    public mutating func setMeasurements(
        _ value: [CloudDatacenterMeasurement],
        for service: CloudDatacenterService
    ) {
        let sorted = value.sorted { lhs, rhs in
            lhs.rttMs == rhs.rttMs
                ? lhs.name < rhs.name
                : lhs.rttMs < rhs.rttMs
        }
        let bounded = Array(sorted.prefix(Self.maximumMeasurements))
        switch service {
        case .psNow:
            psNowMeasurements = bounded
        case .psCloud:
            psCloudMeasurements = bounded
        }
    }

    /// The measurement of one datacenter.
    ///
    /// - Parameters:
    ///   - name: The datacenter.
    ///   - service: The service.
    /// - Returns: The measurement, or `nil`.
    public func measurement(named name: String,
                            for service: CloudDatacenterService) -> CloudDatacenterMeasurement? {
        measurements(for: service).first { $0.name == name }
    }

    /// Whether any service has a measurement.
    public var hasMeasurements: Bool {
        !psNowMeasurements.isEmpty || !psCloudMeasurements.isEmpty
    }

    /// Records a probe's answered rows, unless the datacenter was forced.
    ///
    /// Unchanged rows keep their original measurement time.
    ///
    /// - Parameters:
    ///   - rows: The probe rows.
    ///   - service: The service.
    ///   - forced: Whether the probe ran against a forced datacenter.
    ///   - now: The time to stamp new measurements with.
    /// - Returns: The updated settings.
    public func recording(
        _ rows: [CloudDatacenterPingRow],
        for service: CloudDatacenterService,
        forced: Bool,
        at now: Date
    ) -> Self {
        guard !forced else {
            return self
        }
        var byName = Dictionary(
            measurements(for: service).map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in rows where row.measured && row.rtt > 0 {
            guard let name = Self.validName(row.name) else {
                continue
            }
            if let existing = byName[name], existing.sameProbe(as: row) {
                continue
            }
            byName[name] = CloudDatacenterMeasurement(
                name: name,
                rttMs: row.rtt,
                rttsMs: row.rtts,
                mtuIn: row.mtuIn,
                mtuOut: row.mtuOut,
                port: row.port,
                publicIP: row.publicIP,
                maxBandwidth: row.maxBandwidth,
                measuredAt: now
            )
        }
        var value = self
        value.setMeasurements(Array(byName.values), for: service)
        return value
    }

    /// Drops every choice and measurement, keeping the launch preference and last connection.
    ///
    /// - Returns: The cleared settings.
    public func forgettingMeasurements() -> Self {
        var value = Self()
        value.selectsAtLaunch = selectsAtLaunch
        value.lastConnection = lastConnection
        return value
    }

    /// Sets whether launch offers a datacenter choice.
    ///
    /// - Parameter enabled: Whether to offer it.
    /// - Returns: The updated settings.
    public func selectingAtLaunch(_ enabled: Bool) -> Self {
        var value = self
        value.selectsAtLaunch = enabled
        return value
    }

    /// Leaves the datacenter to the automatic choice: no saved choice for any service and no choice
    /// offered at launch, keeping the measurements and the last connection.
    ///
    /// - Returns: The settings a launch uses when players cannot pick a datacenter.
    public func choosingAutomatically() -> Self {
        var value = selectingAtLaunch(false)
        for service in CloudDatacenterService.allCases {
            value.setChoice(nil, for: service)
        }
        return value
    }

    /// Drops invalid names from choices, measurements and the last connection.
    ///
    /// - Returns: The valid settings.
    public func validated() throws -> Self {
        var value = self
        value.psNowChoice = psNowChoice.flatMap { Self.validName($0) }
        value.psCloudChoice = psCloudChoice.flatMap { Self.validName($0) }
        value.setMeasurements(psNowMeasurements.filter { Self.validName($0.name) != nil }, for: .psNow)
        value.setMeasurements(psCloudMeasurements.filter { Self.validName($0.name) != nil }, for: .psCloud)
        if let connection = lastConnection, Self.validName(connection.name) == nil {
            value.lastConnection = nil
        }
        return value
    }

    /// Records the datacenter a stream connected to, unless the name is invalid or automatic.
    ///
    /// - Parameters:
    ///   - name: The datacenter.
    ///   - rttMs: The round trip the core reported, or 0.
    ///   - service: The service.
    ///   - now: When it connected.
    /// - Returns: The updated settings.
    public func connecting(
        to name: String,
        rttMs: Int,
        service: CloudDatacenterService,
        at now: Date
    ) -> Self {
        guard let valid = Self.validName(name) else {
            return self
        }
        var value = self
        value.lastConnection = CloudDatacenterConnection(
            name: valid,
            rttMs: rttMs > 0
                ? rttMs
                : nil,
            service: service,
            connectedAt: now
        )
        return value
    }

    /// The most recent bandwidth measured for a service.
    ///
    /// - Parameter service: The service.
    /// - Returns: The newest measurement with a bandwidth, or `nil`.
    public func latestBandwidth(for service: CloudDatacenterService) -> CloudSavedBandwidth? {
        measurements(for: service)
            .compactMap { measurement -> CloudSavedBandwidth? in
                guard let kbps = measurement.bandwidthKbps, kbps > 0,
                      let measuredAt = measurement.bandwidthMeasuredAt else {
                    return nil
                }
                return CloudSavedBandwidth(kbps: kbps, measuredAt: measuredAt)
            }
            .max { $0.measuredAt < $1.measuredAt }
    }

    /// Accepts a datacenter name only when it is safe to store and show.
    ///
    /// Rejects empty names, the `Auto` placeholder, names longer than ``maximumNameBytes`` and names with
    /// control characters.
    ///
    /// - Parameter name: The candidate name.
    /// - Returns: The name unchanged, or `nil` when it is rejected.
    static func validName(_ name: String) -> String? {
        guard !name.isEmpty, name != "Auto", name.utf8.count <= maximumNameBytes,
              !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return nil
        }
        return name
    }
}

extension CloudDatacenterSettings: PersistedSettingValue {
    /// The key the cloud datacenter settings are stored under.
    public static var settingKey: SettingKey<CloudDatacenterSettings> {
        SettingKeys.cloudDatacenters
    }
}

/// The datacenter the last cloud stream connected to.
public struct CloudDatacenterConnection: Codable, Equatable, Sendable {
    /// The datacenter's name.
    public var name: String

    /// The round trip the core reported, when it reported one.
    public var rttMs: Int?

    /// The service the stream used.
    public var service: CloudDatacenterService

    /// When the stream connected.
    public var connectedAt: Date

    /// Creates a connection record.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - rttMs: The round trip.
    ///   - service: The service.
    ///   - connectedAt: When it connected.
    public init(name: String, rttMs: Int?, service: CloudDatacenterService, connectedAt: Date) {
        self.name = name
        self.rttMs = rttMs
        self.service = service
        self.connectedAt = connectedAt
    }
}
