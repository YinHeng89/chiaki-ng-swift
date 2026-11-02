/// Whether an account can use cloud streaming, as the catalog last checked.
public struct CloudAccess: Equatable, Sendable {
    /// Whether cloud streaming is available.
    public enum Availability: Equatable, Sendable, CaseIterable {
        /// Cloud streaming is available.
        case available

        /// The sign-in expired.
        case signInExpired

        /// PSN rejected access.
        case rejected

        /// The account's region is not supported.
        case regionUnsupported

        /// Access could not be checked.
        case unavailable
    }

    /// Whether cloud streaming is available.
    public let availability: Availability

    /// How many titles the listing holds, when one was read.
    public let titleCount: Int?

    /// Whether the listing was complete.
    public let complete: Bool

    /// Whether the listing came from the account service.
    public let fromAccountService: Bool

    /// Describes access.
    ///
    /// - Parameters:
    ///   - availability: Whether it is available.
    ///   - titleCount: How many titles the listing holds.
    ///   - complete: Whether the listing was complete.
    ///   - fromAccountService: Whether it came from the account service.
    public init(availability: Availability, titleCount: Int?, complete: Bool, fromAccountService: Bool) {
        self.availability = availability
        self.titleCount = titleCount
        self.complete = complete
        self.fromAccountService = fromAccountService
    }
}
