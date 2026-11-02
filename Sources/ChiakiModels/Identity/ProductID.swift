/// The PlayStation Store product id of a game, such as `"UP9000-PPSA01411_00-0000000000000000"`.
///
/// The catalog, cloud library, title checks and caches key games by it. The value is opaque text owned by
/// PSN; the only rule enforced is that it is not empty. It encodes as a bare string.
public struct ProductID: RawRepresentable, Hashable, Sendable, Codable {
    /// The product id text.
    public let rawValue: String

    /// Wraps a product id.
    ///
    /// - Parameter rawValue: The product id text.
    /// - Returns: `nil` when the text is empty.
    public init?(rawValue: String) {
        guard !rawValue.isEmpty else {
            return nil
        }
        self.rawValue = rawValue
    }
}
