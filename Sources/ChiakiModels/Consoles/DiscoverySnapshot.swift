/// What a running discovery has seen so far.
public struct DiscoverySnapshot: Equatable, Sendable {
    /// The consoles found, ordered by hardware id.
    public var consoles: [DiscoveredConsole]

    /// How many addresses the sweep visits.
    public var sweepTargets: Int

    /// How many addresses the sweep has visited.
    public var sweepVisited: Int

    /// Whether a network was available.
    public var networkAvailable: Bool

    /// The ranges searched by broadcast.
    public var broadcastRanges: [String]

    /// The ranges searched address by address.
    public var unicastRanges: [String]

    /// Describes a snapshot.
    ///
    /// - Parameters:
    ///   - consoles: The consoles found.
    ///   - sweepTargets: The addresses the sweep visits.
    ///   - sweepVisited: The addresses visited.
    ///   - networkAvailable: Whether a network was available.
    ///   - broadcastRanges: The broadcast ranges.
    ///   - unicastRanges: The unicast ranges.
    public init(
        consoles: [DiscoveredConsole] = [],
        sweepTargets: Int = 0,
        sweepVisited: Int = 0,
        networkAvailable: Bool = false,
        broadcastRanges: [String] = [],
        unicastRanges: [String] = []
    ) {
        self.consoles = consoles
        self.sweepTargets = sweepTargets
        self.sweepVisited = sweepVisited
        self.networkAvailable = networkAvailable
        self.broadcastRanges = broadcastRanges
        self.unicastRanges = unicastRanges
    }
}

/// A console discovery found on the network.
public struct DiscoveredConsole: Equatable, Identifiable, Sendable {
    /// The console generation as discovery labels it.
    public enum Kind: String, Sendable {
        /// A PlayStation 4.
        case ps4 = "PS4"

        /// A PlayStation 5.
        case ps5 = "PS5"
    }

    /// The hardware id in uppercase hexadecimal.
    public let id: String

    /// The console's name.
    public let name: String

    /// The address it answered from.
    public let address: String

    /// Its generation.
    public let kind: Kind

    /// Whether it is in rest mode.
    public let standby: Bool

    /// Describes a console.
    ///
    /// - Parameters:
    ///   - id: The hardware id in uppercase hexadecimal.
    ///   - name: The name.
    ///   - address: The address.
    ///   - kind: The generation.
    ///   - standby: Whether it is in rest mode.
    public init(id: String, name: String, address: String, kind: Kind, standby: Bool) {
        self.id = id
        self.name = name
        self.address = address
        self.kind = kind
        self.standby = standby
    }
}

/// What the shared local-network scan reports to each subscriber.
public enum ConsoleScanEvent: Equatable, Sendable {
    /// The consoles currently answering, and how the scan is configured.
    case snapshot(DiscoverySnapshot)

    /// The scan stopped and will not report again until it is subscribed to afresh.
    case failed
}

/// A reason to keep scanning the local network for consoles.
///
/// The root's one discovery holds a set of leases and scans while any is held, so the library, the add-console
/// screen and an automatic connection share one scan and none of them stops it under another.
public enum DiscoveryLease: Hashable, Sendable, CaseIterable {
    /// The library shows which consoles are awake.
    case library

    /// The add-console screen lists consoles to pair.
    case addConsole

    /// An automatic connection looks for its console.
    case autoConnect
}
