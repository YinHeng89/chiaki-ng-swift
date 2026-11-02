import CoreGraphics

/// The pixel box an image is decoded to fill, bucketed so near sizes share one decode.
///
/// Widths and heights round up to a multiple of ``step`` and are clamped between ``minimum`` and ``maximum``,
/// so a card that resizes by a point or two keeps the image it already has.
public struct ArtworkBox: Hashable, Sendable {
    /// The bucket size in pixels.
    public static let step = 64
    /// The smallest side a box has.
    public static let minimum = 128
    /// The largest side a box has.
    public static let maximum = 2_560
    /// The box heroes, backdrops and logos decode to.
    public static let full = ArtworkBox(width: maximum, height: maximum)

    /// The bucketed width in pixels.
    public let width: Int
    /// The bucketed height in pixels.
    public let height: Int

    /// Creates a box from pixel sides.
    ///
    /// - Parameters:
    ///   - width: The wanted width in pixels.
    ///   - height: The wanted height in pixels.
    public init(width: Int, height: Int) {
        self.width = Self.bucket(width)
        self.height = Self.bucket(height)
    }

    /// Creates the box a view of this size needs on a display of this scale.
    ///
    /// - Parameters:
    ///   - points: The view's size in points.
    ///   - scale: The display scale.
    /// - Returns: `nil` when the size or the scale is empty or not finite.
    public init?(points: CGSize, scale: CGFloat) {
        guard points.width > 0, points.height > 0, points.width.isFinite, points.height.isFinite,
              scale > 0, scale.isFinite else {
            return nil
        }
        self.init(
            width: Int((points.width * scale).rounded(.up)),
            height: Int((points.height * scale).rounded(.up))
        )
    }

    /// Tells whether an image decoded for this box is large enough for another.
    ///
    /// - Parameter other: The box wanted.
    /// - Returns: `true` when both sides are at least as large.
    public func covers(_ other: ArtworkBox) -> Bool {
        width >= other.width && height >= other.height
    }

    /// The smallest box that covers both boxes.
    ///
    /// - Parameter other: The other box.
    /// - Returns: The larger side of each.
    public func union(_ other: ArtworkBox) -> ArtworkBox {
        ArtworkBox(width: max(width, other.width), height: max(height, other.height))
    }

    /// The longest side an image of this source size decodes to so that it fills the box.
    ///
    /// - Parameters:
    ///   - sourceWidth: The source image's width in pixels.
    ///   - sourceHeight: The source image's height in pixels.
    /// - Returns: The longest side in pixels, never larger than the source.
    public func fillPixelSize(sourceWidth: Int, sourceHeight: Int) -> Int {
        guard sourceWidth > 0, sourceHeight > 0 else {
            return max(width, height)
        }
        let scale = max(Double(width) / Double(sourceWidth), Double(height) / Double(sourceHeight))
        let longest = max(sourceWidth, sourceHeight)
        return min(longest, Int((Double(longest) * scale).rounded(.up)))
    }

    private static func bucket(_ value: Int) -> Int {
        let rounded = (max(value, 1) + step - 1) / step * step
        return min(max(rounded, minimum), maximum)
    }
}
