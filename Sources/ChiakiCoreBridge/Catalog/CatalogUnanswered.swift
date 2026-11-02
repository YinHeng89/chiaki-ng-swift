import ChiakiBridge
import ChiakiModels

/// Why the catalog did not answer a request.
public struct CatalogUnanswered: Error, Equatable, Sendable {
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

    /// The unanswered request the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The failure.
    static func of(_ facts: chiaki_bridge.CatalogUnanswered) -> Self {
        Self(
            reason: reason(of: facts.reason),
            httpStatus: Int(facts.http_status),
            needsSignIn: facts.needs_sign_in
        )
    }

    /// The unanswered request a bridge refusal stands for.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The failure.
    static func of(_ refusal: chiaki_bridge.CatalogRefusal) -> Self {
        switch refusal {
        case .core_closed:
            Self(reason: .coreClosed)
        case .unknown_user:
            Self(reason: .unknownUser)
        case .invalid_product:
            Self(reason: .invalidProduct)
        case .invalid_concept:
            Self(reason: .invalidConcept)
        case .invalid_image:
            Self(reason: .invalidImage)
        }
    }

    /// The model reason of the core's.
    ///
    /// - Parameter reason: The core's reason.
    /// - Returns: The model reason.
    static func reason(of reason: chiaki_bridge.CatalogReason) -> Reason {
        switch reason {
        case .cancelled:
            .cancelled
        case .user:
            .user
        case .unavailable:
            .unavailable
        case .rejected:
            .rejected
        case .region_unsupported:
            .regionUnsupported
        case .malformed:
            .malformed
        case .not_listed:
            .notListed
        case .storage:
            .storage
        case .ownership_unknown:
            .ownershipUnknown
        case .restriction_list_unavailable:
            .restrictionListUnavailable
        }
    }
}

extension CatalogFailure {
    /// The failure the bridge reported for an unanswered catalog request.
    ///
    /// - Parameter unanswered: What the bridge reported.
    public init(_ unanswered: CatalogUnanswered) {
        self.init(
            reason: Self.reason(of: unanswered.reason),
            httpStatus: unanswered.httpStatus,
            needsSignIn: unanswered.needsSignIn
        )
    }

    private static func reason(of reason: CatalogUnanswered.Reason) -> Reason {
        switch reason {
        case .cancelled:
            .cancelled
        case .user:
            .user
        case .unavailable:
            .unavailable
        case .rejected:
            .rejected
        case .regionUnsupported:
            .regionUnsupported
        case .malformed:
            .malformed
        case .notListed:
            .notListed
        case .storage:
            .storage
        case .ownershipUnknown:
            .ownershipUnknown
        case .restrictionListUnavailable:
            .restrictionListUnavailable
        case .unknownUser:
            .unknownUser
        case .coreClosed:
            .coreClosed
        case .invalidProduct:
            .invalidProduct
        case .invalidImage:
            .invalidImage
        case .unknownCache:
            .unknownCache
        case .invalidConcept:
            .invalidConcept
        }
    }
}
