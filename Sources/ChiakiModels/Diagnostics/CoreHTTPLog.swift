/// The core's HTTP log as one read returned it.
public struct CoreHTTPLog: Equatable, Sendable {
    /// The log's revision when it was read.
    public var revision: UInt64

    /// The tallies.
    public var totals: CoreHTTPTotals

    /// The exchanges, newest first.
    public var exchanges: [CoreHTTPExchange]

    /// Describes a log.
    ///
    /// - Parameters:
    ///   - revision: The revision.
    ///   - totals: The tallies.
    ///   - exchanges: The exchanges.
    public init(
        revision: UInt64 = 0,
        totals: CoreHTTPTotals = CoreHTTPTotals(),
        exchanges: [CoreHTTPExchange] = []
    ) {
        self.revision = revision
        self.totals = totals
        self.exchanges = exchanges
    }
}

/// HTTP tallies overall, without credentials, per credential and per host.
public struct CoreHTTPTotals: Equatable, Sendable {
    /// Every exchange.
    public var all: CoreHTTPTally

    /// Exchanges that carried no credential.
    public var anonymous: CoreHTTPTally

    /// Exchanges per credential carried.
    public var credentials: [CoreHTTPCredential: CoreHTTPTally]

    /// Exchanges per scheme and host.
    public var bases: [String: CoreHTTPTally]

    /// Describes totals.
    ///
    /// - Parameters:
    ///   - all: Every exchange.
    ///   - anonymous: Exchanges without a credential.
    ///   - credentials: Exchanges per credential.
    ///   - bases: Exchanges per host.
    public init(
        all: CoreHTTPTally = CoreHTTPTally(),
        anonymous: CoreHTTPTally = CoreHTTPTally(),
        credentials: [CoreHTTPCredential: CoreHTTPTally] = [:],
        bases: [String: CoreHTTPTally] = [:]
    ) {
        self.all = all
        self.anonymous = anonymous
        self.credentials = credentials
        self.bases = bases
    }
}

/// Counts of HTTP exchanges.
public struct CoreHTTPTally: Equatable, Sendable {
    /// How many requests were made.
    public var requests: Int

    /// How many got an HTTP error status.
    public var httpErrors: Int

    /// How many failed before a response arrived.
    public var transportErrors: Int

    /// How many bytes were sent.
    public var bytesSent: Int

    /// How many bytes were received.
    public var bytesReceived: Int

    /// Describes a tally.
    ///
    /// - Parameters:
    ///   - requests: How many requests.
    ///   - httpErrors: How many HTTP errors.
    ///   - transportErrors: How many transport errors.
    ///   - bytesSent: How many bytes were sent.
    ///   - bytesReceived: How many bytes were received.
    public init(
        requests: Int = 0,
        httpErrors: Int = 0,
        transportErrors: Int = 0,
        bytesSent: Int = 0,
        bytesReceived: Int = 0
    ) {
        self.requests = requests
        self.httpErrors = httpErrors
        self.transportErrors = transportErrors
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
    }
}
