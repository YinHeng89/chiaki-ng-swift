/// Why the catalog did not answer a request.
public struct CatalogFailure: Error, Equatable, Sendable {
    /// What stopped the request.
    public enum Reason: Equatable, Sendable, CaseIterable {
        /// The request was cancelled.
        case cancelled

        /// The user's sign-in could not be used.
        case user

        /// PSN or the store did not answer.
        case unavailable

        /// PSN or the store rejected the request.
        case rejected

        /// The account's region is not supported.
        case regionUnsupported

        /// The answer could not be read.
        case malformed

        /// The title is not listed.
        case notListed

        /// The catalog's records could not be read or written.
        case storage

        /// The account's ownership is not known.
        case ownershipUnknown

        /// The list of restricted titles could not be read.
        case restrictionListUnavailable

        /// The core does not know the user.
        case unknownUser

        /// The core is not open.
        case coreClosed

        /// The product id is not valid.
        case invalidProduct

        /// The image address is not one the catalog fetches.
        case invalidImage

        /// The cache is not one the core keeps.
        case unknownCache

        /// The concept id is not valid.
        case invalidConcept
    }

    /// What stopped the request.
    public let reason: Reason

    /// The HTTP status PSN answered with, or zero.
    public let httpStatus: Int

    /// Whether the user must sign in again.
    public let needsSignIn: Bool

    /// Describes an unanswered request.
    ///
    /// - Parameters:
    ///   - reason: What stopped it.
    ///   - httpStatus: The HTTP status.
    ///   - needsSignIn: Whether the user must sign in again.
    public init(reason: Reason, httpStatus: Int = 0, needsSignIn: Bool = false) {
        self.reason = reason
        self.httpStatus = httpStatus
        self.needsSignIn = needsSignIn
    }

    /// The cloud library failure this stands for.
    public var libraryFailure: CloudLibraryFailure {
        needsSignIn
            ? .signInRequired
            : .network
    }
}
