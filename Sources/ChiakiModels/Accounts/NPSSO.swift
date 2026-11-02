/// The NPSSO session token PSN issues when a user signs in on the web.
///
/// The token is held in ``SecretBytes`` from the moment it is validated until the core signs in with it, so it
/// cannot be copied and is wiped when it is destroyed. Only printable ASCII that is legal in a cookie value is
/// accepted: no spaces, quotes, commas, semicolons or backslashes.
public struct NPSSO: ~Copyable, Sendable {
    private let token: SecretBytes

    /// Validates text and takes its bytes, ignoring surrounding whitespace.
    ///
    /// The text itself is an immutable `String` and cannot be wiped; callers drop it as soon as this returns.
    ///
    /// - Parameter text: The token as PSN returned it or as it was pasted.
    /// - Returns: `nil` when nothing but whitespace remains or a character is not allowed in a cookie value.
    public init?(_ text: String) {
        var bytes = Self.trimmed(Array(text.utf8))
        guard Self.isValid(bytes) else {
            bytes.withUnsafeMutableBytes {
                SecretBytes.wipe($0)
            }
            return nil
        }
        token = SecretBytes(wiping: &bytes)
    }

    /// Reports whether text would make a valid token, without keeping it.
    ///
    /// - Parameter text: The token text.
    /// - Returns: `true` when ``init(_:)`` would accept the text.
    public static func accepts(_ text: String) -> Bool {
        isValid(trimmed(Array(text.utf8)))
    }

    /// The number of bytes in the token.
    public var count: Int {
        token.count
    }

    /// Lends the token to a closure.
    ///
    /// - Parameter body: Reads the token. The pointer is valid only for the duration of `body`.
    /// - Returns: What `body` returns.
    /// - Throws: The error `body` throws.
    public func withUnsafeBytes<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafeRawBufferPointer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try token.withUnsafeBytes(body)
    }

    /// Lends the token to a closure as a NUL-terminated C string.
    ///
    /// - Parameter body: Reads the token. The pointer is valid only for the duration of `body`.
    /// - Returns: What `body` returns.
    /// - Throws: The error `body` throws.
    public func withUnsafeCString<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafePointer<CChar>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try token.withUnsafeCString(body)
    }

    /// Compares two tokens in time that depends only on their lengths.
    ///
    /// - Parameter other: The token to compare with.
    /// - Returns: `true` when both tokens hold the same bytes.
    public func isEqual(to other: borrowing NPSSO) -> Bool {
        token.isEqual(to: other.token)
    }

    private static func trimmed(_ bytes: [UInt8]) -> [UInt8] {
        var all = bytes
        let first = all.firstIndex { !isSpace($0) }
        let last = all.lastIndex { !isSpace($0) }
        guard let first, let last else {
            all.withUnsafeMutableBytes {
                SecretBytes.wipe($0)
            }
            return []
        }
        let kept = Array(all[first ... last])
        all.withUnsafeMutableBytes {
            SecretBytes.wipe($0)
        }
        return kept
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09 ... 0x0D).contains(byte)
    }

    private static func isValid(_ bytes: [UInt8]) -> Bool {
        !bytes.isEmpty && bytes.allSatisfy {
            (33 ... 126).contains($0) && ![34, 44, 59, 92].contains($0)
        }
    }
}
