/// A progress report from a starting or reconnecting stream.
///
/// The facts the session reacts to are typed fields; the core's full report travels as an opaque
/// ``StreamProgressDetail`` for the views that render it.
public struct StreamProgress: Equatable, Sendable {
    /// The account's place in the cloud server queue, when it is queued.
    public let queuePosition: Int?

    /// The bandwidth the cloud launch measured, when it measured one.
    public let bandwidth: CloudBandwidthReport?

    /// Whether the report belongs to a reconnection rather than the start.
    public let reconnecting: Bool

    private let detail: (any StreamProgressDetail)?

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - queuePosition: The cloud queue position.
    ///   - bandwidth: The measured bandwidth.
    ///   - reconnecting: Whether it belongs to a reconnection.
    ///   - detail: The core's full report.
    public init(
        queuePosition: Int? = nil,
        bandwidth: CloudBandwidthReport? = nil,
        reconnecting: Bool = false,
        detail: (any StreamProgressDetail)? = nil
    ) {
        self.queuePosition = queuePosition
        self.bandwidth = bandwidth
        self.reconnecting = reconnecting
        self.detail = detail
    }

    /// The core's full report, when it has the given type.
    ///
    /// - Parameter type: The expected report type.
    /// - Returns: The report, or `nil` when there is none of that type.
    public func detail<Detail: StreamProgressDetail>(as type: Detail.Type) -> Detail? {
        detail as? Detail
    }

    /// Whether two reports carry the same facts and the same full report.
    ///
    /// - Parameters:
    ///   - lhs: One report.
    ///   - rhs: The other report.
    /// - Returns: `true` when they are equal.
    public static func == (lhs: StreamProgress, rhs: StreamProgress) -> Bool {
        guard lhs.queuePosition == rhs.queuePosition, lhs.bandwidth == rhs.bandwidth,
              lhs.reconnecting == rhs.reconnecting else {
            return false
        }
        switch (lhs.detail, rhs.detail) {
        case (nil, nil):
            return true
        case (let left?, let right?):
            return left.isEqual(to: right)
        default:
            return false
        }
    }
}

/// The core's full progress report behind a ``StreamProgress``, which only the views that render it read.
public protocol StreamProgressDetail: Sendable {
    /// Whether this report equals another one.
    ///
    /// - Parameter other: Another report.
    /// - Returns: `true` when both are the same report.
    func isEqual(to other: any StreamProgressDetail) -> Bool
}

extension StreamProgressDetail where Self: Equatable {
    /// Compares two reports of the same type with `==`.
    ///
    /// - Parameter other: Another report.
    /// - Returns: `true` when `other` has this type and is equal.
    public func isEqual(to other: any StreamProgressDetail) -> Bool {
        (other as? Self) == self
    }
}
