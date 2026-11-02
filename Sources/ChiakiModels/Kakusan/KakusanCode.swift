/// The four-digit code a host reads out to a guest; it never appears in descriptions or mirrors.
public struct KakusanCode: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// The number of digits.
    public static let length = 4

    /// The digits.
    public let digits: String

    /// Validates a code.
    ///
    /// - Parameter value: Exactly four ASCII digits.
    public init?(_ value: String) {
        guard value.utf8.count == Self.length,
              value.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
            return nil
        }
        digits = value
    }

    /// Keeps the first four ASCII digits of typed text.
    ///
    /// - Parameter value: The typed text.
    /// - Returns: At most four digits.
    public static func digitsOnly(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            (48 ... 57).contains($0.value)
        }
        return String(String.UnicodeScalarView(scalars.prefix(length)))
    }

    /// Always `[REDACTED]`.
    public var description: String {
        "[REDACTED]"
    }

    /// Always `[REDACTED]`.
    public var debugDescription: String {
        "[REDACTED]"
    }

    /// A mirror with no children, so reflection reveals nothing.
    public var customMirror: Mirror {
        Mirror(self, children: [])
    }
}
