/// Where the core's full fetch of one account's cloud library stands, mirroring the core's `FetchState` field by
/// field.
///
/// The core owns the fetch and its state machine; the app only keeps the latest snapshot the core reported for
/// the fetch it shows, and never derives a state of its own.
public struct CloudLibraryFetchState: Equatable, Sendable {
    /// One step of a full catalog fetch, in the order the core runs them.
    public enum Step: Equatable, Sendable, CaseIterable {
        /// No fetch has run for the account since it was signed in or started over.
        case idle
        /// The account's sign-in is being checked.
        case checkingSignIn
        /// The list of titles PlayStation streams in the account's region is being read.
        case cloudList
        /// The games the account owns are being read.
        case ownedLibrary
        /// The PS5 titles the account's plan includes are being read.
        case premiumCategory
        /// The PS5 titles the store sells for streaming are being read.
        case forSaleCategory
        /// Whether the account may stream PS5 titles from the cloud is being read.
        case streamingAccess
        /// The answers are being matched into the account's games.
        case matching
        /// Trusted time is being synced, because a shown game awaits its release.
        case trustedTime
        /// The list of titles excluded from PS5 cloud streaming is being read.
        case exclusions
        /// The fetch ended with the account's games.
        case ready
        /// The fetch ended without games; ``CloudLibraryFetchState/failure`` says why.
        case unanswered
        /// The fetch was cancelled.
        case cancelled
    }

    /// What a step is doing at the moment.
    public enum Activity: Equatable, Sendable, CaseIterable {
        /// An answer held from an earlier fetch is being used.
        case reusingHeldAnswer
        /// The region's public store is being walked without signing in.
        case walkingPublicStore
        /// The account's PS Now shelves are being walked.
        case walkingOldServiceShelves
        /// The shelves could not be walked, so the public store is walked instead.
        case walkingPublicStoreFallback
        /// Each listed PS4 title is checked for a streaming copy a plan covers.
        case checkingStreamingCopies
        /// The PS5 lists of the store app are being read.
        case readingPS5StoreLists
        /// The account's entitlements are being read, page by page.
        case readingEntitlements
        /// The concepts of the account's streamed PS4 copies are being read.
        case readingStreamedPS4Concepts
        /// The account's PS5 library is being read, page by page.
        case scanningPS5Library
        /// A store category is being read, page by page.
        case readingCategoryPages
        /// The account's subscriptions are being read.
        case readingSubscriptions
        /// The account's games are being built from the answers.
        case matchingGames
        /// The clock is being synced with a trusted server.
        ///
        /// - Parameter host: The host name of the time server being asked, such as `time.cloudflare.com`, or
        ///   `nil` before the core has named one.
        case syncingClock(host: String?)
        /// The exclusion list is being read.
        case readingExclusions

        /// Every activity, with ``syncingClock(host:)`` before it names a server.
        public static let allCases: [Self] = [
            .reusingHeldAnswer,
            .walkingPublicStore,
            .walkingOldServiceShelves,
            .walkingPublicStoreFallback,
            .checkingStreamingCopies,
            .readingPS5StoreLists,
            .readingEntitlements,
            .readingStreamedPS4Concepts,
            .scanningPS5Library,
            .readingCategoryPages,
            .readingSubscriptions,
            .matchingGames,
            .syncingClock(host: nil),
            .readingExclusions
        ]
    }

    /// How a step that has ended was answered.
    public enum Outcome: Equatable, Sendable, CaseIterable {
        /// The fetch did not need the step.
        case skipped
        /// Answered from what was held, without asking PlayStation.
        case held
        /// Answered afresh.
        case fetched
        /// Asked and not fully answered; the fetch carried on without the missing part.
        case degraded
    }

    /// A step the fetch has passed, and how.
    public struct PassedStep: Equatable, Sendable {
        /// The step.
        public let step: Step
        /// How it ended.
        public let outcome: Outcome

        /// Describes a passed step.
        ///
        /// - Parameters:
        ///   - step: The step.
        ///   - outcome: How it ended.
        public init(step: Step, outcome: Outcome) {
            self.step = step
            self.outcome = outcome
        }
    }

    /// The fetch this snapshot belongs to, counted from 1 for each account; 0 before any.
    public let attempt: UInt64
    /// The step reached.
    public let step: Step
    /// What the step is doing, or `nil` while it waits on another fetch's answer and once the fetch has ended.
    public let activity: Activity?
    /// Pages read so far by the current activity; 0 for an activity that does not page.
    public let pagesRead: Int
    /// Pages the current activity expects in all, or `nil` while no source has stated a total.
    public let pagesExpected: Int?
    /// The steps already passed, in order.
    public let passed: [PassedStep]
    /// Why the fetch ended without games; only for ``Step/unanswered``.
    public let failure: CatalogFailure?
    /// Whether the fetch is still running.
    public let isRunning: Bool

    /// Describes a snapshot of the core's fetch.
    ///
    /// - Parameters:
    ///   - attempt: The fetch the snapshot belongs to.
    ///   - step: The step reached.
    ///   - activity: What the step is doing, if it has said.
    ///   - pagesRead: Pages read so far by the current activity.
    ///   - pagesExpected: Pages the current activity expects, when known.
    ///   - passed: The steps already passed, in order.
    ///   - failure: Why the fetch ended without games.
    ///   - isRunning: Whether the fetch is still running.
    public init(
        attempt: UInt64,
        step: Step,
        activity: Activity? = nil,
        pagesRead: Int = 0,
        pagesExpected: Int? = nil,
        passed: [PassedStep] = [],
        failure: CatalogFailure? = nil,
        isRunning: Bool
    ) {
        self.attempt = attempt
        self.step = step
        self.activity = activity
        self.pagesRead = pagesRead
        self.pagesExpected = pagesExpected
        self.passed = passed
        self.failure = failure
        self.isRunning = isRunning
    }
}
