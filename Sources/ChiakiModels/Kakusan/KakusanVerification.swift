import Foundation

/// The verification step: this side's code and the entry of the other side's.
public struct KakusanVerification: Equatable, Sendable {
    /// The code this side shows, once known.
    public var ownCode: KakusanCode?

    /// The entry of the other side's code.
    public var entry: KakusanCodeEntry

    /// Creates a verification step.
    ///
    /// - Parameters:
    ///   - ownCode: This side's code.
    ///   - entry: The entry state.
    public init(ownCode: KakusanCode? = nil, entry: KakusanCodeEntry = .awaiting) {
        self.ownCode = ownCode
        self.entry = entry
    }

    /// Records this side's code the first time it arrives.
    ///
    /// - Parameter code: The code the session produced.
    /// - Returns: `accepted` for the first code, `ignored` for a repeat of the same code and `rejected` for a
    ///   different one.
    mutating func record(_ code: KakusanCode) -> KakusanTransition {
        guard let ownCode else {
            self.ownCode = code
            return .accepted
        }
        return ownCode == code
            ? .ignored
            : .rejected
    }

    /// Starts submitting the entered code under an operation, but only while the entry is still awaiting
    /// input.
    ///
    /// - Parameter operation: The operation that tracks the submission.
    /// - Returns: `accepted` when the entry moved to submitting, otherwise `rejected`.
    mutating func submit(_ operation: UUID) -> KakusanTransition {
        guard entry == .awaiting else {
            return .rejected
        }
        entry = .submitting(operation)
        return .accepted
    }
}

/// Where entering the other participant's verification code is.
public enum KakusanCodeEntry: Equatable, Sendable {
    /// Waiting for the user to type it.
    case awaiting

    /// Submitted by the operation with the given id, awaiting the answer.
    case submitting(UUID)

    /// Submitted and answered.
    case submitted
}
