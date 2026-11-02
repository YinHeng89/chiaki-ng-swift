import CoreGraphics
import Foundation

/// The decoded images the layered game detail draws, held by reference so state compares them cheaply.
///
/// Two values are equal only when they are the same instance: images are decoded once and never compared
/// pixel by pixel.
public final class GameArtLayers: Equatable, @unchecked Sendable {
    /// Separate background, hero and logo layers.
    public struct Layered {
        /// The full-width backdrop.
        public let background: CGImage
        /// The character or key art drawn over the backdrop.
        public let hero: CGImage
        /// The title logo.
        public let logo: CGImage
    }

    /// Game Hub art: one cover and an optional logo.
    public struct GameHub {
        /// The cover used as the backdrop.
        public let cover: CGImage
        /// The title logo, when the store publishes one.
        public let logo: CGImage?
    }

    /// The kind of art the game has.
    public enum Art {
        /// Separate layers.
        case layered(Layered)
        /// A Game Hub cover.
        case gameHub(GameHub)
    }

    /// The art the detail draws.
    public let art: Art

    /// Holds separate layers.
    ///
    /// - Parameters:
    ///   - background: The full-width backdrop.
    ///   - hero: The art drawn over the backdrop.
    ///   - logo: The title logo.
    public init(background: CGImage, hero: CGImage, logo: CGImage) {
        art = .layered(Layered(background: background, hero: hero, logo: logo))
    }

    /// Holds Game Hub art.
    ///
    /// - Parameters:
    ///   - cover: The cover used as the backdrop.
    ///   - logo: The title logo, if any.
    public init(cover: CGImage, logo: CGImage?) {
        art = .gameHub(GameHub(cover: cover, logo: logo))
    }

    /// The image drawn behind everything else.
    public var backdrop: CGImage {
        switch art {
        case .layered(let layered):
            layered.background
        case .gameHub(let gameHub):
            gameHub.cover
        }
    }

    /// The title logo, if the art has one.
    public var logo: CGImage? {
        switch art {
        case .layered(let layered):
            layered.logo
        case .gameHub(let gameHub):
            gameHub.logo
        }
    }

    /// The separate layers, or `nil` for Game Hub art.
    public var layered: Layered? {
        guard case .layered(let layered) = art else {
            return nil
        }
        return layered
    }

    /// Compares by identity.
    ///
    /// - Parameters:
    ///   - lhs: One set of layers.
    ///   - rhs: Another set of layers.
    /// - Returns: Whether both are the same instance.
    public static func == (lhs: GameArtLayers, rhs: GameArtLayers) -> Bool {
        lhs === rhs
    }
}

/// The size a piece of game detail art is drawn at, which sets the box it decodes to.
public enum GameArtSize: Sendable {
    /// The full-width backdrop.
    case backdrop
    /// The key art drawn over the backdrop.
    case hero
    /// The title logo.
    case logo
    /// A screenshot tile in the media rail.
    case tile
    /// A small icon.
    case icon
    /// An enlarged screenshot.
    case enlarged

    /// The width the store's image service is asked to resize to, or `nil` to fetch the original.
    public var resizedWidth: Int? {
        switch self {
        case .tile:
            640
        case .backdrop, .hero, .logo, .icon, .enlarged:
            nil
        }
    }

    /// The box the image decodes to.
    public var box: ArtworkBox {
        switch self {
        case .backdrop, .hero, .logo, .enlarged:
            ArtworkBox.full
        case .tile:
            ArtworkBox(width: 640, height: 384)
        case .icon:
            ArtworkBox(width: 256, height: 256)
        }
    }

    /// The addresses to try, in order: the resized image when this size asks for one, then the original.
    ///
    /// - Parameter url: The original image address.
    /// - Returns: The addresses to fetch, the original last.
    public func candidates(for url: URL) -> [URL] {
        guard let resizedWidth,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [url]
        }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "w", value: String(resizedWidth))
        ]
        guard let resized = components.url else {
            return [url]
        }
        return [resized, url]
    }
}
