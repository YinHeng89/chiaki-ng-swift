import ChiakiModels

/// The words the cloud library's loading view shows for the core's fetch: one line for the current step and,
/// under it, the current activity and its page count.
///
/// Only a running step has words; an idle, ready, unanswered or cancelled fetch shows none.
public struct CloudLibraryFetchProgress: Equatable, Sendable {
    /// The line for the current step.
    public let step: String
    /// The current activity, if the step has named one.
    public let detail: String?
    /// The page count of the current activity, if it has read a page.
    public let pages: String?

    /// The words for a state of the core's fetch.
    ///
    /// - Parameter state: The latest state the core reported.
    /// - Returns: The words, or `nil` for a state that shows no fetch line.
    public init?(_ state: CloudLibraryFetchState) {
        guard let step = Self.line(of: state.step) else {
            return nil
        }
        self.step = step
        detail = state.activity.map(Self.detail(of:))
        pages = Self.pages(read: state.pagesRead, expected: state.pagesExpected)
    }

    /// The line for a step.
    ///
    /// - Parameter step: The step.
    /// - Returns: The line, or `nil` for a step that is not running.
    public static func line(of step: CloudLibraryFetchState.Step) -> String? {
        switch step {
        case .checkingSignIn:
            "Checking your sign-in"
        case .cloudList:
            "Reading the cloud catalog"
        case .ownedLibrary:
            "Reading your games"
        case .premiumCategory:
            "Reading the Game Catalog"
        case .forSaleCategory:
            "Reading cloud games for sale"
        case .streamingAccess:
            "Checking cloud streaming access"
        case .matching:
            "Putting your library together"
        case .trustedTime:
            "Checking the time"
        case .exclusions:
            "Checking which games are unavailable"
        case .idle, .ready, .unanswered, .cancelled:
            nil
        }
    }

    /// The detail for an activity.
    ///
    /// - Parameter activity: The activity.
    /// - Returns: The detail; for a clock sync, the time server being asked once the core has named it.
    public static func detail(of activity: CloudLibraryFetchState.Activity) -> String {
        switch activity {
        case .reusingHeldAnswer:
            "Using what was saved earlier"
        case .walkingPublicStore:
            "PlayStation Store"
        case .walkingOldServiceShelves:
            "PS Now shelves"
        case .walkingPublicStoreFallback:
            "PlayStation Store, as a fallback"
        case .checkingStreamingCopies:
            "Checking which copies stream"
        case .readingPS5StoreLists:
            "PS5 store lists"
        case .readingEntitlements:
            "Your entitlements"
        case .readingStreamedPS4Concepts:
            "Your PS4 games"
        case .scanningPS5Library:
            "Your PS5 games"
        case .readingCategoryPages:
            "Store pages"
        case .readingSubscriptions:
            "Your subscriptions"
        case .matchingGames:
            "Matching titles"
        case let .syncingClock(host):
            host ?? "Trusted time"
        case .readingExclusions:
            "Exclusion list"
        }
    }

    /// The page count line.
    ///
    /// - Parameters:
    ///   - read: Pages read so far.
    ///   - expected: Pages expected in all, when known.
    /// - Returns: "Page 3 of 7" when the total is known, "Page 3" when it is not, and `nil` before any page.
    public static func pages(read: Int, expected: Int?) -> String? {
        guard read > 0 else {
            return nil
        }
        guard let expected else {
            return "Page \(read)"
        }
        return "Page \(read) of \(expected)"
    }
}
