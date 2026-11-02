import Foundation

/// A Kakusan participant's 32-byte public key.
public struct KakusanPublicKey: Hashable, Sendable, CustomStringConvertible {
    /// The key's length in bytes.
    public static let length = 32

    /// The key's bytes.
    public let bytes: Data

    /// Validates a key.
    ///
    /// - Parameter bytes: The bytes; any other length is refused.
    public init?(_ bytes: Data) {
        guard bytes.count == Self.length else {
            return nil
        }
        self.bytes = Data(bytes)
    }

    /// The first four bytes in hex, enough to tell keys apart in logs.
    public var description: String {
        Hex.encode(bytes.prefix(4))
    }
}
