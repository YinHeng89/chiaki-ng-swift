import CoreGraphics

/// The layout of the logo at one height, in points, derived from the 2044 by 1215 pixel source artwork.
///
/// Rectangles use a top-left origin. The animated parts of the logo (signal waves, eyes, square
/// fill and cross) are positioned from these values so they line up with the static artwork.
struct ChiakiLogoGeometry: Equatable {
    /// The radius, in source artwork pixels, of the outline drawn around the navy parts in dark mode.
    static let outlineRadius: CGFloat = 22

    /// The two eyes of the mascot, in source artwork pixels with a top-left origin.
    static let artworkEyes = [
        CGRect(x: 659, y: 307, width: 68, height: 177),
        CGRect(x: 816, y: 307, width: 68, height: 177)
    ]

    /// The thinnest outline, in device pixels, so the dark-mode outline stays visible at small sizes.
    static let minimumOutlinePixels: CGFloat = 1.25

    /// The height of the logo in points.
    let size: CGFloat

    /// The width of the logo in points, keeping the source artwork's aspect ratio.
    var width: CGFloat {
        size * 2044 / 1215
    }

    /// The margin around the logo that leaves room for the bob, the cross hop and the outermost wave.
    var padding: CGFloat {
        size * 0.22
    }

    /// The logo's own rectangle at the origin.
    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: size)
    }

    /// The top-left region holding the signal waves, cut from the static base and redrawn as animated strokes.
    var signalRect: CGRect {
        CGRect(x: 0, y: 0, width: width * 0.262, height: size * 0.186)
    }

    /// The region holding the cross, cut from the static base and drawn as its own spinning layer.
    var crossRect: CGRect {
        CGRect(x: width * 0.529, y: size * 0.136, width: width * 0.239, height: size * 0.407)
    }

    /// The point the cross spins around.
    var crossPivot: CGPoint {
        CGPoint(x: width * 0.6485, y: size * 0.3395)
    }

    /// The stroke width of each signal wave.
    var waveLineWidth: CGFloat {
        size * 0.035
    }

    /// The dark-mode outline width in points at this size.
    ///
    /// - Parameter scale: The display scale, in pixels per point.
    /// - Returns: The outline scaled from ``outlineRadius``, never thinner than ``minimumOutlinePixels``.
    func outlineWidth(scale: CGFloat) -> CGFloat {
        max(size * Self.outlineRadius / 1215, Self.minimumOutlinePixels / scale)
    }

    /// The outline radius to draw on the source artwork so it appears ``outlineWidth(scale:)`` wide.
    ///
    /// - Parameter scale: The display scale, in pixels per point.
    /// - Returns: The radius in source artwork pixels, rounded to half a pixel so cached outlines are reused.
    func artworkOutlineRadius(scale: CGFloat) -> CGFloat {
        (outlineWidth(scale: scale) * 1215 / size * 2).rounded() / 2
    }

    /// The transparent border, in source artwork pixels, needed around the artwork to hold an outline.
    ///
    /// - Parameter radius: The outline radius in source artwork pixels.
    /// - Returns: The radius rounded up, plus two pixels for the softening blur.
    static func artworkPadding(outline radius: CGFloat) -> CGFloat {
        radius.rounded(.up) + 2
    }

    /// How far, in points, the drawn artwork extends past ``bounds``.
    ///
    /// - Parameters:
    ///   - ink: The ink the logo is drawn in.
    ///   - scale: The display scale, in pixels per point.
    /// - Returns: Zero for ``ChiakiLogoInk/navy``, otherwise the outline padding converted to points.
    func artworkMargin(ink: ChiakiLogoInk, scale: CGFloat) -> CGFloat {
        guard ink == .outlined else {
            return 0
        }
        return Self.artworkPadding(outline: artworkOutlineRadius(scale: scale)) * size / 1215
    }

    /// The rectangle the drawn artwork covers, including any outline.
    ///
    /// - Parameters:
    ///   - ink: The ink the logo is drawn in.
    ///   - scale: The display scale, in pixels per point.
    /// - Returns: ``bounds`` grown on every side by ``artworkMargin(ink:scale:)``.
    func artworkFrame(ink: ChiakiLogoInk, scale: CGFloat) -> CGRect {
        let margin = artworkMargin(ink: ink, scale: scale)
        return bounds.insetBy(dx: -margin, dy: -margin)
    }
}
