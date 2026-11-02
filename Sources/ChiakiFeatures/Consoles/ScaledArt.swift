import CoreGraphics
import SwiftUI

/// Keeps downsampled copies of art layers at the pixel sizes they are drawn at, so large key art is not
/// scaled
/// on every frame.
public final class ScaledArtCache: @unchecked Sendable {
    /// The cache art views use when the app has not supplied one, such as in a preview.
    public static let unsupplied = ScaledArtCache()
    private final class Entry {
        let source: CGImage
        let scaled: CGImage

        init(source: CGImage, scaled: CGImage) {
            self.source = source
            self.scaled = scaled
        }
    }

    private let entries = NSCache<NSString, Entry>()

    /// Creates a cache that holds up to 96 scaled images.
    public init() {
        entries.countLimit = 96
    }

    /// The largest size that fits an image into a box without changing its aspect ratio.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - box: The box to fit.
    /// - Returns: The fitted size.
    public static func fitted(_ image: CGImage, in box: CGSize) -> CGSize {
        let width = CGFloat(max(1, image.width))
        let height = CGFloat(max(1, image.height))
        let ratio = min(box.width / width, box.height / height)
        return CGSize(width: width * ratio, height: height * ratio)
    }

    /// Scales an image down to a pixel size, halving it repeatedly first so detail is averaged rather than
    /// dropped.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - width: The target width in pixels.
    ///   - height: The target height in pixels.
    /// - Returns: The scaled image, or the original when it is not larger or drawing fails.
    public static func downsampled(_ image: CGImage, width: Int, height: Int) -> CGImage {
        guard width > 0, height > 0, width < image.width || height < image.height else {
            return image
        }
        var current = image
        while current.width / 2 >= width, current.height / 2 >= height, current.width > width * 2 {
            guard let halved = drawn(current, width: current.width / 2, height: current.height / 2) else {
                break
            }
            current = halved
        }
        return drawn(current, width: width, height: height) ?? image
    }

    private static func drawn(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The image scaled to a pixel size, from the cache when it was scaled before.
    ///
    /// - Parameters:
    ///   - source: The image.
    ///   - width: The target width in pixels.
    ///   - height: The target height in pixels.
    /// - Returns: The scaled image.
    public func image(_ source: CGImage, width: Int, height: Int) -> CGImage {
        let key = "\(Unmanaged.passUnretained(source).toOpaque())-\(width)x\(height)" as NSString
        if let held = entries.object(forKey: key), held.source === source {
            return held.scaled
        }
        let scaled = Self.downsampled(source, width: width, height: height)
        entries.setObject(Entry(source: source, scaled: scaled), forKey: key)
        return scaled
    }
}

/// Measures and remembers where the visible figure of a transparent art layer sits, so a hero can be framed
/// by
/// its figure rather than its canvas.
public final class ArtContentBounds: @unchecked Sendable {
    /// The bounds art views use when the app has not supplied them, such as in a preview.
    public static let unsupplied = ArtContentBounds()
    private final class Entry {
        let source: CGImage
        let box: CGRect

        init(source: CGImage, box: CGRect) {
            self.source = source
            self.box = box
        }
    }

    /// The whole image, in unit coordinates, used when nothing visible can be measured.
    public static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The longest side, in pixels, an image is reduced to before it is measured.
    public static let sample = 96
    /// The percentage of visible weight trimmed from each end, so stray pixels do not widen the bounds.
    public static let trim = 5

    private let entries = NSCache<NSString, Entry>()

    /// Creates an empty cache of measured bounds.
    public init() {
    }

    /// Measures the bounds of an image's visible content.
    ///
    /// - Parameter image: The image.
    /// - Returns: The bounds in unit coordinates, or ``whole`` when the image is empty or cannot be drawn.
    public static func measured(_ image: CGImage) -> CGRect {
        let longest = max(image.width, image.height, 1)
        let width = max(1, image.width * sample / longest)
        let height = max(1, image.height * sample / longest)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else {
            return whole
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return whole
        }
        let alpha = data.bindMemory(to: UInt8.self, capacity: width * height)
        var columns = [Int](repeating: 0, count: width)
        var rows = [Int](repeating: 0, count: height)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let weight = Int(alpha[row * context.bytesPerRow + column])
                columns[column] += weight
                rows[row] += weight
            }
        }
        guard let across = bulk(columns), let down = bulk(rows) else {
            return whole
        }
        return CGRect(
            x: CGFloat(across.lowerBound) / CGFloat(width), y: CGFloat(down.lowerBound) / CGFloat(height),
            width: CGFloat(across.count) / CGFloat(width), height: CGFloat(down.count) / CGFloat(height)
        )
    }

    /// The span of a weight profile that holds its bulk, trimming ``trim`` percent from each end.
    ///
    /// - Parameter weights: The alpha weight of each column or row.
    /// - Returns: The kept indices, or `nil` when every weight is zero.
    public static func bulk(_ weights: [Int]) -> Range<Int>? {
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return nil
        }
        let trimmed = total * trim / 100
        var first = 0
        var last = weights.count - 1
        var before = 0
        while first < last, before + weights[first] <= trimmed {
            before += weights[first]
            first += 1
        }
        var after = 0
        while last > first, after + weights[last] <= trimmed {
            after += weights[last]
            last -= 1
        }
        return first ..< last + 1
    }

    /// The bounds of an image's visible content, from the cache when it was measured before.
    ///
    /// - Parameter source: The image.
    /// - Returns: The bounds in unit coordinates.
    public func box(of source: CGImage) -> CGRect {
        let key = "\(Unmanaged.passUnretained(source).toOpaque())" as NSString
        if let held = entries.object(forKey: key), held.source === source {
            return held.box
        }
        let box = Self.measured(source)
        entries.setObject(Entry(source: source, box: box), forKey: key)
        return box
    }
}

/// Draws an art layer at a size from a copy downsampled to the display's pixels.
public struct ScaledArt: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scaledArtCache) private var cache
    /// The art layer.
    public let image: CGImage
    /// The size to draw it at, in points.
    public let size: CGSize

    /// Creates a scaled art.
    ///
    /// - Parameters:
    ///   - image: The art layer.
    ///   - size: The size to draw it at, in points.
    public init(image: CGImage, size: CGSize) {
        self.image = image
        self.size = size
    }

    public var body: some View {
        Image(
            decorative: cache.image(
                image, width: Int((size.width * displayScale).rounded()),
                height: Int((size.height * displayScale).rounded())
            ),
            scale: displayScale
        )
        .interpolation(.high)
        .antialiased(true)
        .resizable()
        .frame(width: size.width, height: size.height)
    }
}

extension EnvironmentValues {
    /// The downsampled art copies scaled art views share, which the app supplies at its root.
    @Entry public var scaledArtCache = ScaledArtCache.unsupplied

    /// The measured art content bounds art views share, which the app supplies at its root.
    @Entry public var artContentBounds = ArtContentBounds.unsupplied
}
