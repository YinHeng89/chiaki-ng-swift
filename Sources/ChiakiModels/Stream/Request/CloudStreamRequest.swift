/// A request to stream one cloud title for one profile.
public struct CloudStreamRequest: Equatable, Sendable {
    /// The app profile the title is streamed for.
    public let profile: ProfileID

    /// The title launched.
    public let title: CloudStreamTitle

    /// The launch the catalog already cleared, when it did; a retry drops it and checks again.
    public private(set) var clearance: CloudLaunchClearanceToken?

    /// The game invitation the stream joins once it plays, when it was started to accept one.
    public var joining: CloudGameInvitation?

    /// Describes a cloud request.
    ///
    /// - Parameters:
    ///   - profile: The profile the title is streamed for.
    ///   - title: The title launched.
    ///   - clearance: The cleared launch, if any.
    ///   - joining: The game invitation to join once the stream plays, if any.
    public init(
        profile: ProfileID,
        title: CloudStreamTitle,
        clearance: CloudLaunchClearanceToken? = nil,
        joining: CloudGameInvitation? = nil
    ) {
        self.profile = profile
        self.title = title
        self.clearance = clearance
        self.joining = joining
    }

    /// The same request without its clearance, so a retry is checked again.
    public var uncleared: CloudStreamRequest {
        var request = self
        request.clearance = nil
        return request
    }
}

/// The cloud title a cloud stream launches.
public struct CloudStreamTitle: Hashable, Sendable {
    /// The catalog product launched.
    public let product: ProductID

    /// The title's name.
    public let name: String

    /// The service that streams it.
    public let service: CloudService

    /// The platform the catalog lists, such as `PS5`.
    public let platform: String

    /// Whether the account owns the title.
    public let isOwned: Bool

    /// Whether the title is in the PlayStation Plus catalog.
    public let plusCatalog: Bool

    /// The artwork address shown while the stream starts.
    public let artwork: String?

    /// The other generation's version of the game, on the other streaming service.
    public let otherVersion: ProductID?

    /// Describes a cloud title.
    ///
    /// - Parameters:
    ///   - product: The catalog product.
    ///   - name: The title's name.
    ///   - service: The service that streams it.
    ///   - platform: The platform the catalog lists.
    ///   - isOwned: Whether the account owns it.
    ///   - plusCatalog: Whether it is in the PlayStation Plus catalog.
    ///   - artwork: The artwork address.
    ///   - otherVersion: The other generation's version of the game.
    public init(
        product: ProductID,
        name: String,
        service: CloudService,
        platform: String = "PS5",
        isOwned: Bool = false,
        plusCatalog: Bool = false,
        artwork: String? = nil,
        otherVersion: ProductID? = nil
    ) {
        self.product = product
        self.name = name
        self.service = service
        self.platform = platform
        self.isOwned = isOwned
        self.plusCatalog = plusCatalog
        self.artwork = artwork
        self.otherVersion = otherVersion
    }
}
