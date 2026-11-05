/// How a native stream ended, with the cloud launch refusal when PlayStation refused the title.
public struct StreamEndReport: Equatable, Sendable {
    /// How the stream ended.
    public var outcome: StreamOutcome

    /// Why PlayStation refused the cloud launch, or `nil` when it did not.
    public var launchRefused: CloudLaunchRefused?

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - outcome: How the stream ended.
    ///   - launchRefused: Why PlayStation refused the cloud launch.
    public init(outcome: StreamOutcome, launchRefused: CloudLaunchRefused? = nil) {
        self.outcome = outcome
        self.launchRefused = launchRefused
    }
}

/// Why PlayStation refused to launch a cloud title once the stream had asked for it.
public enum CloudLaunchRefused: Equatable, Sendable {
    /// The catalog's launch checks refused the title.
    case notCleared(CloudClearanceRefusal)

    /// The account's privacy settings block streaming.
    case privacySettings

    /// The title must be bought first, at the display price when PlayStation named one.
    case licenceNotFree(price: String)

    /// The account's membership does not cover cloud streaming.
    case membershipRejected

    /// The title left the PlayStation Plus streaming catalog.
    case outsideStreamingPlan

    /// The title's edition is sold in a different PlayStation Store region than the account's, so it cannot be licensed to the account.
    case storeRegion

    /// This build of the app leaves out PS Cloud launches.
    case notBuilt

    /// PlayStation could not find the title for streaming.
    case titleNotFound

    /// PlayStation refused to stream the title.
    case refusedByStreamService

    /// No streaming datacenter answered.
    case noReachableDatacenter

    /// The chosen datacenter is unavailable; the name is empty when PlayStation did not say which.
    case datacenterUnavailable(String)

    /// No streaming server was free.
    case noServer

    /// The account's sign-in expired.
    case signInExpired

    /// Cloud streaming is unavailable for another reason.
    case unavailable
}
