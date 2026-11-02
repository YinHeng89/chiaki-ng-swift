/// The eight-digit PIN a console shows while it waits to be paired.
///
/// The digits are held in ``SecretBytes`` from the moment they are validated, so the PIN cannot be copied and
/// is wiped when it is destroyed. Only ASCII digits are accepted; full-width or other Unicode digits are
/// refused because the console compares bytes.
public struct PairingPIN: ~Copyable, Sendable {
    /// The number of digits in a PIN.
    public static let length = 8

    private let digits: SecretBytes

    /// Validates typed text and takes its digits.
    ///
    /// The text itself is an immutable `String` and cannot be wiped; callers clear the field that held it.
    ///
    /// - Parameter text: The typed PIN.
    /// - Returns: `nil` unless the text is exactly ``length`` ASCII digits.
    public init?(_ text: String) {
        var bytes = Array(text.utf8)
        guard Self.isValid(bytes) else {
            bytes.withUnsafeMutableBytes {
                SecretBytes.wipe($0)
            }
            return nil
        }
        digits = SecretBytes(wiping: &bytes)
    }

    /// Reports whether typed text would make a valid PIN, without keeping it.
    ///
    /// - Parameter text: The typed PIN.
    /// - Returns: `true` when the text is exactly ``length`` ASCII digits.
    public static func accepts(_ text: String) -> Bool {
        isValid(Array(text.utf8))
    }

    /// Lends the digits to a closure as a NUL-terminated C string.
    ///
    /// - Parameter body: Reads the digits. The pointer is valid only for the duration of `body`.
    /// - Returns: What `body` returns.
    /// - Throws: The error `body` throws.
    public func withUnsafeCString<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafePointer<CChar>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try digits.withUnsafeCString(body)
    }

    private static func isValid(_ bytes: [UInt8]) -> Bool {
        bytes.count == length && bytes.allSatisfy {
            (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0)
        }
    }
}
