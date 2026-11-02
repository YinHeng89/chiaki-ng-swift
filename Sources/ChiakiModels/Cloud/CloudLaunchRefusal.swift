/// Why a cloud title may not be launched.
public enum CloudLaunchRefusal: String, Codable, Equatable, Sendable, CaseIterable {
    /// The title is not in the cloud catalog.
    case notListed

    /// The title is listed but hidden from the account.
    case hidden

    /// The title must be bought before it streams.
    case buyToStream

    /// The title must be added to the library before it streams.
    case addToLibrary

    /// The title needs PlayStation Plus Premium.
    case needsPremium

    /// PlayStation refused to stream the title.
    case refusedByStreamService

    /// The title cannot be streamed.
    case notStreamable

    /// The title is a pre-order without a release date.
    case unannounced

    /// The title is not released yet.
    case notReleased

    /// The release time could not be checked against PlayStation's clock.
    case noTrustedClock

    /// The ownership check could not be completed.
    case checkUnavailable

    /// PlayStation has no record of the account's copy.
    case invalidTitle

    /// The title was taken down from cloud streaming.
    case titleTakenDown

    /// Cloud streaming is not available for the account's copy.
    case streamingUnavailable

    /// The account's copy is no longer active and must be bought again.
    case purchaseNeeded

    /// PlayStation reports the copy in a state that cannot be streamed.
    case unexpectedEntitlementState

    /// The title is a bundle; one of its games must be chosen.
    case chooseAGame
}
