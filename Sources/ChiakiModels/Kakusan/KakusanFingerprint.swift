import Foundation

/// The 32-byte fingerprint two Kakusan participants compare to verify each other.
public struct KakusanFingerprint: Hashable, Sendable, CustomStringConvertible {
    /// The fingerprint's length in bytes.
    public static let length = 32

    /// The fingerprint's bytes.
    public let bytes: Data

    /// Validates a fingerprint.
    ///
    /// - Parameter bytes: The bytes; any other length is refused.
    public init?(_ bytes: Data) {
        guard bytes.count == Self.length else {
            return nil
        }
        self.bytes = Data(bytes)
    }

    /// The fingerprint as four-digit uppercase hex groups.
    public var groups: [String] {
        stride(from: 0, to: bytes.count, by: 2).map { offset in
            let start = bytes.startIndex + offset
            return Hex.encode(bytes[start ..< start + 2], letterCase: .upper)
        }
    }

    /// The groups four to a line, for display.
    public var lines: [String] {
        let groups = groups
        return stride(from: 0, to: groups.count, by: 4).map { start in
            groups[start ..< min(start + 4, groups.count)].joined(separator: " ")
        }
    }

    /// The first four groups.
    public var short: String {
        groups.prefix(4).joined(separator: " ")
    }

    /// Every group, space separated.
    public var description: String {
        groups.joined(separator: " ")
    }
}
