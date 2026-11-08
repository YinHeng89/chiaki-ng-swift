import ChiakiModels
import Foundation

/// The words the cloud library's loading view shows for the core's fetch: one line for the current step and,
/// under it, the current activity and its page count.
///
/// Only a running step has words; an idle, ready, unanswered or cancelled fetch shows none.
public struct CloudLibraryFetchProgress: Equatable, Sendable {
    /// The running step the line describes, which identifies the line as it changes.
    public let stage: CloudLibraryFetchState.Step
    /// The line for the current step.
    public let step: LocalizedStringResource
    /// The current activity, if the step has named one.
    public let detail: LocalizedStringResource?
    /// The page count of the current activity, if it has read a page.
    public let pages: LocalizedStringResource?

    /// The words for a state of the core's fetch.
    ///
    /// - Parameter state: The latest state the core reported.
    /// - Returns: The words, or `nil` for a state that shows no fetch line.
    public init?(_ state: CloudLibraryFetchState) {
        guard let step = Self.line(of: state.step) else {
            return nil
        }
        stage = state.step
        self.step = step
        detail = state.activity.map(Self.detail(of:))
        pages = Self.pages(read: state.pagesRead, expected: state.pagesExpected)
    }

    /// The line for a step.
    ///
    /// - Parameter step: The step.
    /// - Returns: The line, or `nil` for a step that is not running.
    public static func line(of step: CloudLibraryFetchState.Step) -> LocalizedStringResource? {
        switch step {
        case .checkingSignIn:
            .libraryFetchCheckingSignIn
        case .cloudList:
            .libraryFetchCloudList
        case .ownedLibrary:
            .libraryFetchOwnedLibrary
        case .premiumCategory:
            .libraryFetchPremiumCategory
        case .forSaleCategory:
            .libraryFetchForSaleCategory
        case .streamingAccess:
            .libraryFetchStreamingAccess
        case .matching:
            .libraryFetchMatching
        case .trustedTime:
            .libraryFetchTrustedTime
        case .exclusions:
            .libraryFetchExclusions
        case .idle, .ready, .unanswered, .cancelled:
            nil
        }
    }

    /// The detail for an activity.
    ///
    /// - Parameter activity: The activity.
    /// - Returns: The detail; for a clock sync, the time server being asked once the core has named it.
    public static func detail(of activity: CloudLibraryFetchState.Activity) -> LocalizedStringResource {
        switch activity {
        case .reusingHeldAnswer:
            .libraryFetchActivityReusingHeldAnswer
        case .walkingPublicStore:
            .libraryFetchActivityPublicStore
        case .walkingOldServiceShelves:
            .libraryFetchActivityOldServiceShelves
        case .walkingPublicStoreFallback:
            .libraryFetchActivityPublicStoreFallback
        case .checkingStreamingCopies:
            .libraryFetchActivityStreamingCopies
        case .readingPS5StoreLists:
            .libraryFetchActivityStoreListsPs5
        case .readingEntitlements:
            .libraryFetchActivityEntitlements
        case .readingStreamedPS4Concepts:
            .libraryFetchActivityGamesPs4
        case .scanningPS5Library:
            .libraryFetchActivityGamesPs5
        case .readingCategoryPages:
            .libraryFetchActivityCategoryPages
        case .readingSubscriptions:
            .libraryFetchActivitySubscriptions
        case .matchingGames:
            .libraryFetchActivityMatchingGames
        case let .syncingClock(host):
            host.map { .verbatim($0) } ?? .libraryFetchActivityTrustedTime
        case .readingExclusions:
            .libraryFetchActivityExclusions
        }
    }

    /// The page count line.
    ///
    /// - Parameters:
    ///   - read: Pages read so far.
    ///   - expected: Pages expected in all, when known.
    /// - Returns: "Page 3 of 7" when the total is known, "Page 3" when it is not, and `nil` before any page.
    public static func pages(read: Int, expected: Int?) -> LocalizedStringResource? {
        guard read > 0 else {
            return nil
        }
        guard let expected else {
            return .libraryFetchPage(read: read)
        }
        return .libraryFetchPageOf(read: read, expected: expected)
    }
}
