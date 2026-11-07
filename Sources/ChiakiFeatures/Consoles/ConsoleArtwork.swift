import ChiakiModels
import SwiftUI
import ChiakiAssets
import PlatformUI
import ComposableArchitecture

/// Product art of a PS5 or PS4 console, redrawn at the exact pixel size of its height, with a symbol as
/// fallback.
public struct ConsoleArtwork: View {
    /// The height the art is drawn at, in points.
    public var height: CGFloat = 280
    /// Which console generation is shown.
    public var kind: RegistrationFlow.ConsoleKind = .ps5
    @Environment(\.displayScale) private var displayScale

    /// Creates a console artwork.
    ///
    /// - Parameters:
    ///   - height: The height the art is drawn at, in points.
    ///   - kind: Which console generation is shown.
    public init(height: CGFloat = 280, kind: RegistrationFlow.ConsoleKind = .ps5) {
        self.height = height
        self.kind = kind
    }

    private static func load(_ name: String) -> PlatformImage? {
        ChiakiAssets.url(forResource: name, withExtension: "png").flatMap {
            PlatformImage(contentsOf: $0)
        }
    }
    private static let ps5 = load("console-ps5")
    private static let ps4 = load("console-ps4")

    public var body: some View {
        Group {
            if let image = ConsoleArtworkRenderer.image(
                source: kind == .ps5
                    ? Self.ps5
                    : Self.ps4,
                name: kind.rawValue,
                height: height,
                displayScale: displayScale
            ) {
                Image(platformImage: image)
                    .interpolation(.high)
                    .drawingGroup(opaque: false, colorMode: .linear)
            } else {
                Image(systemName: "gameconsole").resizable().scaledToFit()
            }
        }
        .frame(height: height)
        .accessibilityLabel(
            kind == .ps5
                ? .consolesArtworkPs5
                : .consolesArtworkPs4
        )
    }
}

@MainActor
private enum ConsoleArtworkRenderer {
    private static let cache = NSCache<NSString, PlatformImage>()

    static func image(
        source: PlatformImage?,
        name: String,
        height: CGFloat,
        displayScale: CGFloat
    ) -> PlatformImage? {
        guard let source,
              let cgImage = source.platformCGImage,
              cgImage.height > 0 else {
            return nil
        }

        let scale = max(displayScale, 1)
        let pixelHeight = max(Int((height * scale).rounded(.up)), 1)
        let aspectRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let pixelWidth = max(Int((CGFloat(pixelHeight) * aspectRatio).rounded()), 1)
        let key = "\(name)-\(pixelWidth)x\(pixelHeight)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return source
        }

        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )

        guard let rendered = context.makeImage() else {
            return source
        }
        let image = PlatformImage(
            cgImage: rendered,
            size: CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        )
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The DualSense controller silhouette, tinted with the secondary style; shows nothing when the asset is
/// missing.
public struct DualSenseArtwork: View {
    private static let image = ChiakiAssets.url(forResource: "dualsense", withExtension: "png")
        .flatMap {
            PlatformImage(contentsOf: $0)
        }
    public var body: some View {
        if let image = Self.image {
            Image(platformImage: image).renderingMode(.template).resizable().interpolation(.high)
                .scaledToFit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(.consolesArtworkDualSense)
        }
    }
}
