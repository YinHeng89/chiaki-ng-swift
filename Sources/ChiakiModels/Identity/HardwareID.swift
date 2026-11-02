import Foundation

/// The six-byte hardware id a PlayStation console reports in discovery and registration.
///
/// The database stores it in `consoles.hardware_id` as twelve lowercase hex digits, and discovery shows it in
/// uppercase. Every initialiser validates its input, so a ``HardwareID`` always holds exactly six bytes.
public struct HardwareID: Hashable, Sendable {
    /// The number of bytes in a hardware id.
    public static let byteCount = 6

    /// The six bytes, in the order the console sends them.
    public let bytes: [UInt8]

    /// Wraps the bytes a console reported.
    ///
    /// - Parameter bytes: The hardware id bytes.
    /// - Returns: `nil` unless `bytes` holds exactly ``byteCount`` bytes.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        self.bytes = Array(bytes)
    }

    /// Reads a hardware id from hex text, ignoring separators.
    ///
    /// Characters that are not ASCII hex digits, such as `:` or `-`, are skipped, matching how stored and
    /// typed ids have always been read. The digits that remain may be in either case.
    ///
    /// - Parameter hex: Text holding twelve hex digits, such as `"a1b2c3d4e5f6"` or `"A1:B2:C3:D4:E5:F6"`.
    /// - Returns: `nil` unless exactly twelve hex digits remain.
    public init?(hex: some StringProtocol) {
        let digits = hex.utf8.filter(Hex.isDigit)
        guard digits.count == Self.byteCount * 2,
              let bytes = Hex.decode(utf8: digits)
        else {
            return nil
        }
        self.bytes = bytes
    }

    /// The bytes as `Data`, as the core's console calls take them.
    public var data: Data {
        Data(bytes)
    }

    /// Twelve lowercase hex digits, the form stored in `consoles.hardware_id`.
    public var hex: String {
        Hex.encode(bytes, letterCase: .lower)
    }

    /// Twelve uppercase hex digits, the form discovery shows.
    public var uppercaseHex: String {
        Hex.encode(bytes, letterCase: .upper)
    }
}
