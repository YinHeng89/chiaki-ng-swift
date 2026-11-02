import Foundation

/// The datacenter a cloud stream used and how it was chosen, for display.
public struct CloudDatacenterSelection: Equatable, Sendable {
    /// The datacenter's name.
    public var name: String

    /// The round trip to show, if known.
    public var rttMs: Int?

    /// Whether the service chose it.
    public var automatic: Bool

    /// When the shown round trip was measured, for a stored choice.
    public var measuredAt: Date?

    /// Whether the user chose it from the launch offer.
    public var atLaunch: Bool

    /// Creates a selection.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - rttMs: The round trip.
    ///   - automatic: Whether the service chose it.
    ///   - measuredAt: When the round trip was measured.
    ///   - atLaunch: Whether it was chosen at launch.
    public init(name: String, rttMs: Int?, automatic: Bool, measuredAt: Date? = nil, atLaunch: Bool = false) {
        self.name = name
        self.rttMs = rttMs
        self.automatic = automatic
        self.measuredAt = measuredAt
        self.atLaunch = atLaunch
    }

    /// The selection the core reported for a stream.
    ///
    /// - Parameters:
    ///   - name: The datacenter's name.
    ///   - rttMs: The round trip the core reported, or 0.
    ///   - forced: Whether the datacenter was forced rather than chosen by the service.
    ///   - settings: The stored settings, for a stored choice's last measurement.
    ///   - service: The service.
    ///   - atLaunch: Whether it was chosen from the launch offer.
    /// - Returns: The selection.
    public static func reported(
        name: String,
        rttMs: Int,
        forced: Bool,
        settings: CloudDatacenterSettings,
        service: CloudDatacenterService,
        atLaunch: Bool = false
    ) -> Self {
        guard forced else {
            return Self(name: name, rttMs: rttMs > 0
                ? rttMs
                : nil, automatic: true)
        }
        if atLaunch {
            return Self(name: name, rttMs: rttMs > 0
                ? rttMs
                : nil, automatic: false, atLaunch: true)
        }
        let stored = settings.measurement(named: name, for: service)
        return Self(name: name, rttMs: stored?.rttMs, automatic: false, measuredAt: stored?.measuredAt)
    }

    /// The round trip as shown, if known.
    public var pingDescription: String? {
        guard let rttMs else {
            return nil
        }
        return automatic || atLaunch
            ? "\(rttMs) ms"
            : "last measured \(rttMs) ms"
    }

    /// The line shown while connecting.
    public var connectingDescription: String {
        guard let rttMs else {
            return "Connecting to \(name)"
        }
        return "Connecting to \(name) (\(rttMs) ms)"
    }

    /// How it was chosen.
    public var modeDescription: String {
        if atLaunch {
            return "Chosen at launch"
        }
        return automatic
            ? "Automatic"
            : "Chosen"
    }

    /// The line shown in stream statistics.
    public var statisticsDescription: String {
        guard let pingDescription else {
            return "\(name), \(modeDescription.lowercased())"
        }
        return "\(name) at \(pingDescription), \(modeDescription.lowercased())"
    }
}
