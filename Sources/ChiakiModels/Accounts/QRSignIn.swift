import Foundation

/// A code a QR sign-in shows for another device to scan and approve.
///
/// Nothing here is secret: the address is meant to be shown. PSN also issues six digits with every code, but the
/// approval page the address opens never shows them, so the app keeps them without drawing them.
public struct QRSignInCode: Hashable, Sendable {
    /// Which code of the sign-in this is, counted from 1 and raised for every replacement code.
    public let attempt: Int

    /// The address the QR code encodes.
    public let approvalURL: String

    /// The six digits PSN issued with the code, leading zeroes kept, which the approval page does not show.
    public let userCode: String

    /// When the code stops being accepted, when PSN said.
    public let expiresAt: Date?

    /// Creates a code.
    ///
    /// - Parameters:
    ///   - attempt: Which code of the sign-in this is, from 1.
    ///   - approvalURL: The address the QR code encodes.
    ///   - userCode: The six digits PSN issued with the code.
    ///   - expiresAt: When the code stops being accepted, when known.
    public init(attempt: Int, approvalURL: String, userCode: String, expiresAt: Date?) {
        self.attempt = attempt
        self.approvalURL = approvalURL
        self.userCode = userCode
        self.expiresAt = expiresAt
    }
}

/// How far a QR sign-in has got before it ends with an account or a failure.
public enum QRSignInProgress: Hashable, Sendable {
    /// A code is being obtained, at the start or after the shown code expired.
    case preparing

    /// A code is shown and PSN is asked whether it has been approved.
    case awaitingApproval(QRSignInCode)

    /// The code was approved and the account is being signed in.
    case signingIn
}
