import Foundation

/// The 16-byte id a host gives a Kakusan guest.
public struct KakusanGuestID: Hashable, Sendable, CustomStringConvertible {
    /// The id's length in bytes.
    public static let length = 16

    /// The id's bytes.
    public let bytes: Data

    /// Validates an id.
    ///
    /// - Parameter bytes: The bytes; any other length is refused.
    public init?(_ bytes: Data) {
        guard bytes.count == Self.length else {
            return nil
        }
        self.bytes = Data(bytes)
    }

    /// The first four bytes in hex, enough to tell guests apart in logs.
    public var description: String {
        Hex.encode(bytes.prefix(4))
    }
}
