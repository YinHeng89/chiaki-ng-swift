import Foundation

/// What the catalog decided about launching a cloud title.
public enum CloudLaunchDecision: Equatable, Sendable {
    /// The title may be launched, with the launch the catalog prepared when it prepared one.
    case cleared(CloudLaunchClearanceToken?)

    /// The title may not be launched.
    case refused(CloudClearanceRefusal)
}

/// A step reported while a cloud title is cleared for launch.
public enum CloudLaunchClearanceEvent: Equatable, Sendable {
    /// A launch check started or changed state.
    case check(CloudLaunchCheck)

    /// Clearance ended with a launch decision, or the catalog failed to answer.
    case finished(Result<CloudLaunchDecision, CatalogFailure>)
}

/// A step of the checks made before a cloud title is launched.
public enum CloudLaunchCheck: CaseIterable, Sendable {
    /// Loading the account's library.
    case loadingLibrary

    /// Checking the membership.
    case membership

    /// Checking that cloud streaming is available.
    case cloudStreaming

    /// Checking ownership.
    case ownership

    /// Checking the entitlement.
    case entitlement

    /// Checking the cloud game.
    case cloudGame

    /// Checking exclusions.
    case exclusions

    /// Checking the release time.
    case release
}

/// Why the catalog refused to launch a cloud title, with what the refusal names.
public struct CloudClearanceRefusal: Equatable, Sendable {
    /// Why the title may not be launched.
    public let refusal: CloudLaunchRefusal

    /// The store's notice, or an empty string.
    public let notice: String

    /// The time the refusal names, such as a release time.
    public let time: Date?

    /// Whether the user must sign in again.
    public let needsSignIn: Bool

    /// The title's display price, or an empty string.
    public let price: String

    /// Describes a refusal.
    ///
    /// - Parameters:
    ///   - refusal: Why the title may not be launched.
    ///   - notice: The store's notice.
    ///   - time: The time the refusal names.
    ///   - needsSignIn: Whether the user must sign in again.
    ///   - price: The display price.
    public init(
        refusal: CloudLaunchRefusal,
        notice: String = "",
        time: Date? = nil,
        needsSignIn: Bool = false,
        price: String = ""
    ) {
        self.refusal = refusal
        self.notice = notice
        self.time = time
        self.needsSignIn = needsSignIn
        self.price = price
    }
}
