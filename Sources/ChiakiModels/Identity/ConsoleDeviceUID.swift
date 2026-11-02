/// The 32-byte identifier PlayStation Network gives a console on an account.
///
/// Internet pairing and remote play address a console by it. It is stored in
/// `registrations.remote_device_id`. A PS4 that is the account's primary console is reported with every byte
/// set to `0x41`; see ``isMainPS4``.
public struct ConsoleDeviceUID: Hashable, Sendable {
    /// The number of bytes in the identifier.
    public static let byteCount = 32

    /// The byte every position holds for the account's primary PS4.
    public static let mainPS4Byte: UInt8 = 0x41

    /// The identifier bytes.
    public let bytes: [UInt8]

    /// Wraps the bytes PSN reported.
    ///
    /// - Parameter bytes: The identifier bytes.
    /// - Returns: `nil` unless `bytes` holds exactly ``byteCount`` bytes.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        self.bytes = Array(bytes)
    }

    /// Whether the identifier names the account's primary PS4 rather than one console.
    public var isMainPS4: Bool {
        bytes.allSatisfy {
            $0 == Self.mainPS4Byte
        }
    }
}
