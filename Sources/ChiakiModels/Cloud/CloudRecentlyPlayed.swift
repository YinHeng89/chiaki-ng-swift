import Foundation

/// A cloud title the account played recently.
public struct CloudRecentlyPlayed: Equatable, Sendable {
    /// The product id.
    public let productId: String

    /// When it was last played.
    public let lastPlayed: Date

    /// Describes a played title.
    ///
    /// - Parameters:
    ///   - productId: The product id.
    ///   - lastPlayed: When it was last played.
    public init(productId: String, lastPlayed: Date) {
        self.productId = productId
        self.lastPlayed = lastPlayed
    }
}
