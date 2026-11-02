import Foundation

/// A title in the account's cloud library.
public struct CloudGame: Codable, Equatable, Identifiable, Sendable {
    /// The product id, which identifies the title.
    public var id: String {
        productId
    }

    /// The game's product id as a strong ``ProductID``, or `nil` when the catalog left it empty.
    public var product: ProductID? {
        ProductID(rawValue: productId)
    }

    /// The product id.
    public let productId: String

    /// The title's name.
    public let name: String

    /// The cover image.
    public let imageUrl: String?

    /// The landscape cover image.
    public let landscapeImageUrl: String?

    /// The platform label, such as `PS5`.
    public let platform: String

    /// Whether the account owns the title.
    public let isOwned: Bool

    /// Whether the title is included with PlayStation Plus.
    public let plusCatalog: Bool

    /// The streaming service, `pscloud` or `psnow`.
    public let streamServiceType: String

    /// The concept page.
    public let conceptUrl: String?

    /// The concept id.
    public let conceptId: String?

    /// Whether the library shows the title.
    public let visible: Bool

    /// Why the title is hidden, when it is.
    public let hideReason: String?

    /// What the account may do with the title.
    public let standing: CloudStanding

    /// Why the title may not be launched, when it may not.
    public let launchRefusal: CloudLaunchRefusal?

    /// Whether the title must be added to the library before it streams.
    public let needsLibraryAdd: Bool

    /// Whether the title can be added to the library.
    public let canBeAddedToLibrary: Bool

    /// Whether the storefront must be asked before the title is launched.
    public let needsStorefrontCheck: Bool

    /// When the title may first be played.
    public let release: CloudReleaseDate

    /// The account's ownership id.
    public let ownershipId: String?

    /// Whether the account holds the title only as a trial, which streams like a full game while
    /// The store reports the trial active.
    public let isTrial: Bool

    /// Whether the title is a trial that has ended, which cannot be launched until the game is bought and which
    /// the library does not list: the store reports its play time used up, or the core remembers the stream
    /// service refusing its launch as an ended trial.
    public let trialEnded: Bool

    /// Whether the title is a PS5 Play First Trial, a timed trial whose play time can be used up, rather than
    /// an ordinary trial or demo with no reported time limit.
    public let isPlayFirstTrial: Bool

    /// The trial version the store offers for a game that is only for sale, or `nil` when it offers none the
    /// account does not already hold.
    public private(set) var trialOffer: CloudTrialOffer?

    /// The games the title bundles, when it is a bundle.
    public let bundle: CloudBundle?

    /// The other generation's version of the game on the other streaming service, or `nil` when the store
    /// links none.
    public let otherVersion: CloudOtherVersion?

    /// Describes a title.
    ///
    /// - Parameters:
    ///   - productId: The product id.
    ///   - name: The name.
    ///   - imageUrl: The cover image.
    ///   - landscapeImageUrl: The landscape cover image.
    ///   - platform: The platform label.
    ///   - isOwned: Whether it is owned.
    ///   - plusCatalog: Whether it is included with PlayStation Plus.
    ///   - streamServiceType: The streaming service.
    ///   - conceptUrl: The concept page.
    ///   - conceptId: The concept id.
    ///   - visible: Whether the library shows it.
    ///   - hideReason: Why it is hidden.
    ///   - standing: What the account may do with it.
    ///   - launchRefusal: Why it may not be launched.
    ///   - needsLibraryAdd: Whether it must be added to the library.
    ///   - canBeAddedToLibrary: Whether it can be added to the library.
    ///   - needsStorefrontCheck: Whether the storefront must be asked.
    ///   - release: When it may first be played.
    ///   - ownershipId: The ownership id.
    ///   - isTrial: Whether it is held only as a trial.
    ///   - trialEnded: Whether it is a trial that has ended.
    ///   - isPlayFirstTrial: Whether it is a timed Play First Trial.
    ///   - trialOffer: The trial version the store offers instead.
    ///   - bundle: The games it bundles.
    ///   - otherVersion: The other generation's version on the other service.
    public init(
        productId: String,
        name: String,
        imageUrl: String? = nil,
        landscapeImageUrl: String? = nil,
        platform: String = "PS5",
        isOwned: Bool = false,
        plusCatalog: Bool = false,
        streamServiceType: String = "pscloud",
        conceptUrl: String? = nil,
        conceptId: String? = nil,
        visible: Bool = true,
        hideReason: String? = nil,
        standing: CloudStanding = .mayStream,
        launchRefusal: CloudLaunchRefusal? = nil,
        needsLibraryAdd: Bool = false,
        canBeAddedToLibrary: Bool = false,
        needsStorefrontCheck: Bool = false,
        release: CloudReleaseDate = .unrestricted,
        ownershipId: String? = nil,
        isTrial: Bool = false,
        trialEnded: Bool = false,
        isPlayFirstTrial: Bool = false,
        trialOffer: CloudTrialOffer? = nil,
        bundle: CloudBundle? = nil,
        otherVersion: CloudOtherVersion? = nil
    ) {
        self.productId = productId
        self.name = name
        self.imageUrl = imageUrl
        self.landscapeImageUrl = landscapeImageUrl
        self.platform = platform
        self.isOwned = isOwned
        self.plusCatalog = plusCatalog
        self.streamServiceType = streamServiceType
        self.conceptUrl = conceptUrl
        self.conceptId = conceptId
        self.visible = visible
        self.hideReason = hideReason
        self.standing = standing
        self.launchRefusal = launchRefusal
        self.needsLibraryAdd = needsLibraryAdd
        self.canBeAddedToLibrary = canBeAddedToLibrary
        self.needsStorefrontCheck = needsStorefrontCheck
        self.release = release
        self.ownershipId = ownershipId
        self.isTrial = isTrial
        self.trialEnded = trialEnded
        self.isPlayFirstTrial = isPlayFirstTrial
        self.trialOffer = trialOffer
        self.bundle = bundle
        self.otherVersion = otherVersion
    }

    /// The title without its store trial offer, for a game whose signed-in store page no longer offers the
    /// account the trial.
    public var withoutTrialOffer: CloudGame {
        var game = self
        game.trialOffer = nil
        return game
    }

    /// The platform of the other generation's version when this title leads the pair, such as `PS4` beside a
    /// PS5 title, or `nil` when it leads no pair.
    public var otherPlatform: String? {
        guard let otherVersion, otherVersion.leads else {
            return nil
        }
        return platform.lowercased() == "ps5"
            ? "PS4"
            : "PS5"
    }

    /// Whether the title is a bundle.
    public var isBundle: Bool {
        bundle != nil
    }

    /// Whether the account owns the title on PS5.
    public var isOwnedPS5: Bool {
        isOwned && platform.lowercased() == "ps5"
    }

    /// Whether the title is in the cloud catalog rather than only on sale.
    public var isInCatalog: Bool {
        platform.lowercased() != "ps5" || streamServiceType == "psnow" || plusCatalog
    }

    /// Whether the title is only on sale.
    public var isStoreOnly: Bool {
        !isInCatalog && !isOwned
    }
}

/// A trial version the PlayStation Store offers for a PS5 cloud game the account does not hold, which the
/// library labels on the game's store card; the trial itself is taken in the store.
public enum CloudTrialOffer: String, Codable, Equatable, Sendable {
    /// An ordinary trial, which the store calls a demo.
    case demo

    /// A timed Play First Trial, which the account may already have used up, since the store deletes a used trial
    /// from the account while the store keeps offering it.
    case playFirstTrial
}

/// What the account may do with a cloud title.
public enum CloudStanding: String, Codable, Equatable, Sendable {
    /// The title may be streamed now.
    case mayStream

    /// The title is in the account's library.
    case inLibrary

    /// The title is included with PlayStation Plus Premium.
    case included

    /// The title is on sale in the store.
    case store

    /// Ownership is not known yet.
    case ownershipUnknown

    /// The label the library shows for the standing.
    public var label: String {
        switch self {
        case .mayStream:
            "May stream"
        case .inLibrary:
            "In your library"
        case .included:
            "Included with Premium"
        case .store, .ownershipUnknown:
            "View in Store"
        }
    }
}

/// The games a cloud bundle holds.
public struct CloudBundle: Codable, Equatable, Sendable {
    /// Whether the account owns the bundle.
    public let isOwned: Bool

    /// The games in it.
    public let games: [CloudBundledGame]

    /// Describes a bundle.
    ///
    /// - Parameters:
    ///   - isOwned: Whether it is owned.
    ///   - games: Its games.
    public init(isOwned: Bool, games: [CloudBundledGame]) {
        self.isOwned = isOwned
        self.games = games
    }
}

/// One game inside a cloud bundle.
public struct CloudBundledGame: Codable, Equatable, Identifiable, Sendable {
    /// The product id, which identifies the game.
    public var id: String {
        productId
    }

    /// The game's product id.
    public let productId: String

    /// The entitlement that grants it.
    public let entitlementId: String

    /// Whether the account owns it.
    public let isOwned: Bool

    /// Why it may not be launched, when it may not.
    public let launchRefusal: CloudLaunchRefusal?

    /// Describes a bundled game.
    ///
    /// - Parameters:
    ///   - productId: The product id.
    ///   - entitlementId: The entitlement id.
    ///   - isOwned: Whether it is owned.
    ///   - launchRefusal: Why it may not be launched.
    public init(
        productId: String,
        entitlementId: String,
        isOwned: Bool,
        launchRefusal: CloudLaunchRefusal? = nil
    ) {
        self.productId = productId
        self.entitlementId = entitlementId
        self.isOwned = isOwned
        self.launchRefusal = launchRefusal
    }
}

/// When a cloud title may first be played.
public enum CloudReleaseDate: Codable, Equatable, Sendable {
    /// The title is released.
    case unrestricted

    /// The title unlocks at a known time.
    case scheduled(Date)

    /// The title has no announced release date.
    case unannounced

    /// The label the library shows, or `nil` once the title is playable.
    ///
    /// - Parameter now: The current time.
    /// - Returns: The label.
    public func label(now: Date = Date()) -> String? {
        switch self {
        case .unrestricted:
            return nil
        case .unannounced:
            return "Release date not announced"
        case .scheduled(let date):
            let remaining = date.timeIntervalSince(now)
            guard remaining > 0 else {
                return nil
            }
            guard remaining < 86400 * 7 else {
                return "Releases " + date.formatted(date: .abbreviated, time: .shortened)
            }
            return "Releases in " + Self.countdown(.seconds(remaining.rounded(.up)))
        }
    }

    /// Whether the title is still waiting for its release at a time: it has no announced date, or its date
    /// is later.
    ///
    /// - Parameter now: The time to compare with, ideally the server's.
    /// - Returns: Whether the title cannot be played yet.
    public func awaitsRelease(at now: Date) -> Bool {
        switch self {
        case .unrestricted:
            false
        case .unannounced:
            true
        case .scheduled(let date):
            date > now
        }
    }

    /// The scheduled release time still to come, or `nil` when there is none.
    ///
    /// - Parameter now: The time to compare with.
    /// - Returns: The time the title unlocks, when that is later than `now`.
    public func unlock(after now: Date) -> Date? {
        guard case .scheduled(let date) = self, date > now else {
            return nil
        }
        return date
    }

    /// A countdown such as `2d 03:04:05`.
    ///
    /// - Parameter remaining: The time left.
    /// - Returns: The countdown text.
    public static func countdown(_ remaining: Duration) -> String {
        let total = max(0, remaining.components.seconds)
        let clock = String(
            format: "%02lld:%02lld:%02lld",
            total % 86400 / 3600,
            total % 3600 / 60,
            total % 60
        )
        let days = total / 86400
        return days == 0
            ? clock
            : "\(days)d " + clock
    }
}
