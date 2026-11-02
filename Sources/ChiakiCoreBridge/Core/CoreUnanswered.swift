import ChiakiBridge

/// Why the core could not answer a request that needs PSN.
public struct CoreUnanswered: Error, Hashable, Sendable {
    /// The reasons a request goes unanswered.
    public enum Reason: Hashable, Sendable, CaseIterable {
        /// The user has no PSN sign-in, so nothing was sent.
        case signedOut

        /// PSN refused the sign-in; the user must sign in again.
        case signInExpired

        /// The app token is missing, expired or refused.
        case storeAccessLapsed

        /// No usable Remote Play token is held and none could be obtained.
        case remotePlayAccessMissing

        /// The request was cancelled.
        case cancelled

        /// PSN is rate limiting the account or the client.
        case rateLimited

        /// PSN could not be reached or answered with an unexpected status.
        case unavailable

        /// PSN refused the request.
        case rejected

        /// PSN's reply could not be read.
        case malformed

        /// The older PlayStation Now service refused the request.
        case oldServiceRefused

        /// The account is not one the core holds.
        case unknownUser

        /// The core is not open.
        case coreClosed
    }

    /// Why the request went unanswered.
    public let reason: Reason

    /// The HTTP status of the reply behind the failure, or 0 when there was none.
    public let httpStatus: Int

    /// Describes an unanswered request.
    ///
    /// - Parameters:
    ///   - reason: Why it went unanswered.
    ///   - httpStatus: The HTTP status, or 0.
    public init(reason: Reason, httpStatus: Int = 0) {
        self.reason = reason
        self.httpStatus = httpStatus
    }

    /// Whether the user must sign in again before the request can succeed.
    public var needsSignIn: Bool {
        switch reason {
        case .signedOut, .signInExpired, .storeAccessLapsed, .remotePlayAccessMissing:
            true
        case .cancelled, .rateLimited, .unavailable, .rejected, .malformed, .oldServiceRefused, .unknownUser,
             .coreClosed:
            false
        }
    }

    /// The model reason of a core reason.
    ///
    /// - Parameter reason: The core's reason.
    /// - Returns: The model reason.
    static func reason(of reason: libchiaking.users.Unanswered.Reason) -> Reason {
        switch reason {
        case .signed_out:
            .signedOut
        case .sign_in_expired:
            .signInExpired
        case .store_access_lapsed:
            .storeAccessLapsed
        case .remote_play_access_missing:
            .remotePlayAccessMissing
        case .cancelled:
            .cancelled
        case .rate_limited:
            .rateLimited
        case .unavailable:
            .unavailable
        case .rejected:
            .rejected
        case .malformed:
            .malformed
        case .old_service_refused:
            .oldServiceRefused
        }
    }
}
