/// A four-digit login PIN or controller passcode, validated once and never printed.
public struct StreamAccessCode: Hashable, Sendable, CustomDebugStringConvertible {
    /// The four digits.
    public let digits: String

    /// Validates a typed code.
    ///
    /// - Parameter value: The typed text.
    /// - Returns: `nil` unless the text is exactly four ASCII digits.
    public init?(_ value: String) {
        guard value.utf8.count == 4, value.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
            return nil
        }
        digits = value
    }

    /// A redacted description, so a code never reaches a log.
    public var debugDescription: String {
        "[REDACTED]"
    }
}
