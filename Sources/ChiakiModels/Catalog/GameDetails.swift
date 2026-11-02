import Foundation

/// What the store shows about one title on its detail page.
public struct GameDetails: Equatable, Sendable {
    /// Key art made of a background, a hero image and a logo.
    public struct LayeredArt: Equatable, Sendable {
        /// The background image.
        public let background: String

        /// The hero image.
        public let hero: String

        /// The logo image.
        public let logo: String

        /// Describes layered art.
        ///
        /// - Parameters:
        ///   - background: The background image.
        ///   - hero: The hero image.
        ///   - logo: The logo image.
        public init(background: String, hero: String, logo: String) {
            self.background = background
            self.hero = hero
            self.logo = logo
        }
    }

    /// Key art from a game hub: one cover and an optional logo.
    public struct GameHubArt: Equatable, Sendable {
        /// The cover image.
        public let cover: String

        /// The logo image.
        public let logo: String?

        /// Describes game hub art.
        ///
        /// - Parameters:
        ///   - cover: The cover image.
        ///   - logo: The logo image.
        public init(cover: String, logo: String? = nil) {
            self.cover = cover
            self.logo = logo
        }
    }

    /// The key art the store offers.
    public enum Art: Equatable, Sendable {
        /// Layered art.
        case layered(LayeredArt)

        /// Game hub art.
        case gameHub(GameHubArt)
    }

    /// The players' star rating.
    public struct StarRating: Equatable, Sendable {
        /// The average rating.
        public let average: Double

        /// The average as the store writes it.
        public let averageText: String

        /// How many ratings were given.
        public let ratings: Int

        /// The share of ratings per star count, from one star up.
        public let percentByStars: [Int]

        /// Describes a rating.
        ///
        /// - Parameters:
        ///   - average: The average.
        ///   - averageText: The average as written.
        ///   - ratings: How many ratings.
        ///   - percentByStars: The share per star count.
        public init(average: Double, averageText: String, ratings: Int, percentByStars: [Int]) {
            self.average = average
            self.averageText = averageText
            self.ratings = ratings
            self.percentByStars = percentByStars
        }
    }

    /// The age rating.
    public struct AgeRating: Equatable, Sendable {
        /// The rating authority, such as PEGI.
        public let authority: String

        /// The rating's name.
        public let name: String

        /// The rating's description.
        public let description: String

        /// The rating's icon.
        public let icon: String?

        /// The content descriptors.
        public let descriptors: [String]

        /// Describes an age rating.
        ///
        /// - Parameters:
        ///   - authority: The authority.
        ///   - name: The name.
        ///   - description: The description.
        ///   - icon: The icon.
        ///   - descriptors: The content descriptors.
        public init(
            authority: String = "",
            name: String,
            description: String = "",
            icon: String? = nil,
            descriptors: [String] = []
        ) {
            self.authority = authority
            self.name = name
            self.description = description
            self.icon = icon
            self.descriptors = descriptors
        }
    }

    /// The key art.
    public var art: Art?

    /// The screenshots.
    public var screenshots: [String]

    /// The trailers.
    public var trailers: [URL]

    /// The star rating.
    public var starRating: StarRating?

    /// The age rating.
    public var ageRating: AgeRating?

    /// The publisher.
    public var publisher: String

    /// When the title was released.
    public var releasedAt: Date?

    /// The genres.
    public var genres: [String]

    /// The layered art, when that is what the store offers.
    public var layeredArt: LayeredArt? {
        guard case .layered(let layered) = art else {
            return nil
        }
        return layered
    }

    /// Describes a detail page.
    ///
    /// - Parameters:
    ///   - art: The key art.
    ///   - screenshots: The screenshots.
    ///   - trailers: The trailers.
    ///   - starRating: The star rating.
    ///   - ageRating: The age rating.
    ///   - publisher: The publisher.
    ///   - releasedAt: When it was released.
    ///   - genres: The genres.
    public init(
        art: Art? = nil,
        screenshots: [String] = [],
        trailers: [URL] = [],
        starRating: StarRating? = nil,
        ageRating: AgeRating? = nil,
        publisher: String = "",
        releasedAt: Date? = nil,
        genres: [String] = []
    ) {
        self.art = art
        self.screenshots = screenshots
        self.trailers = trailers
        self.starRating = starRating
        self.ageRating = ageRating
        self.publisher = publisher
        self.releasedAt = releasedAt
        self.genres = genres
    }

    /// Describes a detail page with layered art.
    ///
    /// - Parameters:
    ///   - layeredArt: The layered art.
    ///   - screenshots: The screenshots.
    ///   - trailers: The trailers.
    ///   - starRating: The star rating.
    ///   - ageRating: The age rating.
    ///   - publisher: The publisher.
    ///   - releasedAt: When it was released.
    ///   - genres: The genres.
    public init(
        layeredArt: LayeredArt?,
        screenshots: [String] = [],
        trailers: [URL] = [],
        starRating: StarRating? = nil,
        ageRating: AgeRating? = nil,
        publisher: String = "",
        releasedAt: Date? = nil,
        genres: [String] = []
    ) {
        self.init(
            art: layeredArt.map(Art.layered),
            screenshots: screenshots,
            trailers: trailers,
            starRating: starRating,
            ageRating: ageRating,
            publisher: publisher,
            releasedAt: releasedAt,
            genres: genres
        )
    }
}

/// Which screenshot or trailer of the layered game detail is enlarged.
public enum GameDetailMedia: Equatable, Sendable {
    /// No media item is enlarged.
    case idle
    /// The media item at this index of the media rail is enlarged.
    case viewing(Int)
}
