import Foundation

/// The datacenters a cloud launch offers to choose from, fastest first.
public struct CloudDatacenterLaunchOffer: Equatable, Sendable {
    /// How long the offer waits for a choice by default.
    public static let defaultTimeoutSeconds = 15
    /// The round trip above which a datacenter is marked as slow.
    public static let highLatencyThresholdMs = 80
    /// The name that lets the service choose.
    public static let automaticName = "Auto"
    /// The note explaining the shown round trips.
    public static let pingNote = "Ping is the adjusted value the stream core reports"

    /// One offered datacenter.
    public struct Entry: Equatable, Identifiable, Sendable {
        /// The datacenter's name.
        public let name: String
        /// The round trip, or `nil` when it did not answer.
        public let rttMs: Int?
        /// The bandwidth measured there, if known.
        public let bandwidthKbps: Int?

        /// Creates an entry, dropping a non-positive bandwidth.
        ///
        /// - Parameters:
        ///   - name: The datacenter's name.
        ///   - rttMs: The round trip.
        ///   - bandwidthKbps: The measured bandwidth.
        public init(name: String, rttMs: Int?, bandwidthKbps: Int? = nil) {
            self.name = name
            self.rttMs = rttMs
            self.bandwidthKbps = bandwidthKbps.flatMap {
                $0 > 0
                    ? $0
                    : nil
            }
        }

        /// The datacenter's name.
        public var id: String {
            name
        }

        /// Whether it answered the probe.
        public var answered: Bool {
            rttMs != nil
        }

        /// Whether it is slow or did not answer.
        public var highLatency: Bool {
            guard let rttMs else {
                return true
            }
            return rttMs > CloudDatacenterLaunchOffer.highLatencyThresholdMs
        }

        /// The round trip as shown.
        public var pingDescription: String {
            guard let rttMs else {
                return "No reply"
            }
            return "\(rttMs) ms"
        }

        /// The bandwidth as shown, if known.
        public var bandwidthDescription: String? {
            bandwidthKbps.map {
                "\($0 / 1000) Mbps"
            }
        }
    }

    /// The offered datacenters.
    public let entries: [Entry]
    /// How long the offer waits for a choice, at least one second.
    public let timeoutSeconds: Int

    /// Creates an offer.
    ///
    /// - Parameters:
    ///   - entries: The offered datacenters.
    ///   - timeoutSeconds: How long to wait.
    public init(entries: [Entry], timeoutSeconds: Int = defaultTimeoutSeconds) {
        self.entries = entries
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    /// Creates an offer from probe rows, dropping invalid and repeated names and putting answered rows first by
    /// round trip.
    ///
    /// - Parameters:
    ///   - rows: The probe rows.
    ///   - timeoutSeconds: How long to wait.
    public init(rows: [CloudDatacenterPingRow], timeoutSeconds: Int = defaultTimeoutSeconds) {
        var seen = Set<String>()
        var unique = [Entry]()
        for row in rows {
            guard CloudDatacenterSettings.validName(row.name) != nil, seen.insert(row.name).inserted else {
                continue
            }
            unique.append(Entry(name: row.name, rttMs: row.measured && row.rtt > 0
                    ? row.rtt
                    : nil))
        }
        let ordered = unique.enumerated().sorted { lhs, rhs in
            switch (lhs.element.rttMs, rhs.element.rttMs) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        self.init(entries: ordered.map(\.element), timeoutSeconds: timeoutSeconds)
    }

    /// The fastest datacenter that answered.
    public var lowest: Entry? {
        entries.first(where: \.answered)
    }

    /// Whether nothing is offered.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Whether a name is offered or is the automatic choice.
    ///
    /// - Parameter name: The datacenter.
    /// - Returns: Whether it may be chosen.
    public func offers(_ name: String) -> Bool {
        name == Self.automaticName || entries.contains { $0.name == name }
    }

    /// Whether an entry is the fastest that answered.
    ///
    /// - Parameter entry: The entry.
    /// - Returns: Whether it is the fastest.
    public func isLowest(_ entry: Entry) -> Bool {
        lowest?.name == entry.name
    }
}
