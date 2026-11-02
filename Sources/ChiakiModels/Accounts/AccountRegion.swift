/// The country and language PSN reported for an account.
public struct AccountRegion: Hashable, Sendable {
    /// The country code.
    public let country: String

    /// The language code.
    public let language: String

    /// Describes a region.
    ///
    /// - Parameters:
    ///   - country: The country code.
    ///   - language: The language code.
    public init(country: String, language: String) {
        self.country = country
        self.language = language
    }
}
