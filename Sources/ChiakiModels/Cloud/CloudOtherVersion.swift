/// The other generation's version of a cloud title, listed on the other streaming service.
///
/// The PlayStation Store sells the PS4 and PS5 versions of a cross-generation game together; PS Now streams the PS4
/// version and PS5 cloud the PS5 one.
public struct CloudOtherVersion: Codable, Equatable, Hashable, Sendable {
    /// The product id the other version is listed under.
    public let productId: String

    /// Whether the title that holds this link leads the pair, so the library shows it and offers the other
    /// version inside it.
    public let leads: Bool

    /// Describes the other version.
    ///
    /// - Parameters:
    ///   - productId: The product id the other version is listed under.
    ///   - leads: Whether the title holding the link leads the pair.
    public init(productId: String, leads: Bool) {
        self.productId = productId
        self.leads = leads
    }

    /// The other version's product id as a ``ProductID``, or `nil` when it does not parse.
    public var product: ProductID? {
        ProductID(rawValue: productId)
    }
}
