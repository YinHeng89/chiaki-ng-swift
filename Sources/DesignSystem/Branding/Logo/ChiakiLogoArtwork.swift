import ChiakiAssets
import CoreImage
import CoreImage.CIFilterBuiltins
import PlatformUI
import SwiftUI

/// Decodes, outlines, slices and caches the bundled logo artwork.
///
/// Every image is rendered once per ink, size and display scale and then reused. The static
/// logo uses ``image(_:size:scale:)``; the animated logo uses ``base(for:scale:ink:)`` for
/// the still parts and ``cross(for:scale:ink:)`` for the spinning cross.
@MainActor
enum ChiakiLogoArtwork {
    private struct Key: Hashable {
        let size: CGFloat
        let scale: CGFloat
        let ink: ChiakiLogoInk
    }

    /// The bundled full-colour artwork, as drawn on light backgrounds.
    static let lightArtwork = loadArtwork("chiaking-color")

    /// How many times denser than the display the cross is rendered, so it stays sharp while rotating.
    static let oversample: CGFloat = 3

    #if os(macOS)
        private static let artworkPixels = NSBitmapImageRep(data: lightArtwork.tiffRepresentation!)!

        /// The navy of the mascot's face, sampled from the artwork and used for the eyelids and light-mode waves.
        static let faceColor = artworkPixels.colorAt(x: 780, y: 180)!

        /// The lime of the square, sampled from the artwork and used for its animated fill.
        static let squareColor = artworkPixels.colorAt(x: 1800, y: 220)!

        /// The opaque lime used for the dark-mode outline and dark-mode waves.
        static let outlineInk = CGColor(
            srgbRed: squareColor.redComponent,
            green: squareColor.greenComponent,
            blue: squareColor.blueComponent,
            alpha: 1
        )
    #else
        /// The navy of the mascot's face, sampled from the artwork and used for the eyelids and light-mode waves.
        static let faceColor = sampledColor(x: 780, y: 180)

        /// The lime of the square, sampled from the artwork and used for its animated fill.
        static let squareColor = sampledColor(x: 1800, y: 220)

        /// The opaque lime used for the dark-mode outline and dark-mode waves.
        static let outlineInk = squareColor.cgColor.copy(alpha: 1) ?? squareColor.cgColor
    #endif

    private static let navySource: CGImage = {
        guard let image = lightArtwork.platformCGImage,
              let decoded = render(width: image.width, height: image.height, draw: { context in
                  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
              })
        else {
            preconditionFailure("Unable to decode chiaki-ng artwork")
        }
        return decoded
    }()

    private static let signallessSource: CGImage = {
        let width = navySource.width
        let height = navySource.height
        let signal = ChiakiLogoGeometry(size: CGFloat(height)).signalRect
        guard let image = render(width: width, height: height, draw: { context in
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            context.draw(navySource, in: bounds)
            context.clear(CGRect(
                x: signal.minX, y: CGFloat(height) - signal.maxY, width: signal.width, height: signal.height
            ))
        }) else {
            preconditionFailure("Unable to remove the chiaki-ng signal artwork")
        }
        return image
    }()

    private static var outlinedSources = [CGFloat: CGImage]()
    private static var images = [ChiakiLogoInk: PlatformImage]()
    private static var bases = [Key: CGImage]()
    private static var sizedImages = [Key: PlatformImage]()
    private static var crosses = [Key: CGImage]()

    /// The whole logo resampled for one size and display scale, used when motion is reduced.
    ///
    /// - Parameters:
    ///   - ink: The ink to draw the logo in.
    ///   - size: The height of the logo in points.
    ///   - scale: The display scale, in pixels per point.
    /// - Returns: An image covering ``ChiakiLogoGeometry/artworkFrame(ink:scale:)``, or the
    ///   full-resolution artwork when resampling fails.
    static func image(_ ink: ChiakiLogoInk, size: CGFloat, scale: CGFloat) -> PlatformImage {
        let geometry = ChiakiLogoGeometry(size: size)
        let key = Key(size: size, scale: scale, ink: ink)
        if let cached = sizedImages[key] {
            return cached
        }
        let frame = geometry.artworkFrame(ink: ink, scale: scale)
        let pixelWidth = Int((frame.width * scale).rounded(.up))
        let pixelHeight = Int((frame.height * scale).rounded(.up))
        let artwork = source(ink, outline: geometry.artworkOutlineRadius(scale: scale))
        guard let pixels = resampled(artwork, width: pixelWidth, height: pixelHeight) else {
            return image(ink)
        }
        let sized = PlatformImage(cgImage: pixels, size: frame.size)
        sizedImages[key] = sized
        return sized
    }

    /// The whole logo at the source artwork's resolution, cropped to the artwork's own bounds.
    ///
    /// - Parameter ink: The ink to draw the logo in.
    /// - Returns: ``lightArtwork`` for ``ChiakiLogoInk/navy``, otherwise the outlined artwork with
    ///   the outline beyond the original bounds cropped away.
    static func image(_ ink: ChiakiLogoInk) -> PlatformImage {
        guard ink != .navy else {
            return lightArtwork
        }
        if let cached = images[ink] {
            return cached
        }
        let padded = source(ink, outline: ChiakiLogoGeometry.outlineRadius)
        let padding = ChiakiLogoGeometry.artworkPadding(outline: ChiakiLogoGeometry.outlineRadius)
        guard let cropped = padded.cropping(to: CGRect(
            x: padding,
            y: padding,
            width: CGFloat(padded.width) - padding * 2,
            height: CGFloat(padded.height) - padding * 2
        )) else {
            return lightArtwork
        }
        let image = PlatformImage(cgImage: cropped, size: lightArtwork.size)
        images[ink] = image
        return image
    }

    /// The still parts of the animated logo, with the signal and cross regions cut out.
    ///
    /// - Parameters:
    ///   - geometry: The layout of the logo.
    ///   - scale: The display scale, in pixels per point.
    ///   - ink: The ink to draw the logo in.
    /// - Returns: A bitmap covering ``ChiakiLogoGeometry/artworkFrame(ink:scale:)``, or `nil` when it
    ///   cannot be rendered.
    static func base(for geometry: ChiakiLogoGeometry, scale: CGFloat, ink: ChiakiLogoInk) -> CGImage? {
        let key = Key(size: geometry.size, scale: scale, ink: ink)
        if let cached = bases[key] {
            return cached
        }
        let frame = geometry.artworkFrame(ink: ink, scale: scale)
        let pixelWidth = Int((frame.width * scale).rounded(.up))
        let pixelHeight = Int((frame.height * scale).rounded(.up))
        let artwork = source(ink, outline: geometry.artworkOutlineRadius(scale: scale))
        guard let artwork = resampled(artwork, width: pixelWidth, height: pixelHeight) else {
            return nil
        }
        let image = render(width: pixelWidth, height: pixelHeight) { context in
            context.scaleBy(
                x: CGFloat(pixelWidth) / frame.width,
                y: CGFloat(pixelHeight) / frame.height
            )
            context.translateBy(x: -frame.minX, y: -frame.minY)
            let mask = CGMutablePath()
            for rect in [frame, geometry.signalRect, geometry.crossRect] {
                mask.addRect(flipped(rect, height: geometry.size))
            }
            context.addPath(mask)
            context.clip(using: .evenOdd)
            context.interpolationQuality = .high
            context.draw(artwork, in: flipped(frame, height: geometry.size))
        }
        bases[key] = image
        return image
    }

    /// The cross region of the logo, drawn on its own so it can spin.
    ///
    /// - Parameters:
    ///   - geometry: The layout of the logo.
    ///   - scale: The pixel density to render at, normally the display scale times ``oversample``.
    ///   - ink: The ink to draw the logo in.
    /// - Returns: A bitmap covering ``ChiakiLogoGeometry/crossRect``, or `nil` when it cannot be rendered.
    static func cross(for geometry: ChiakiLogoGeometry, scale: CGFloat, ink: ChiakiLogoInk) -> CGImage? {
        let key = Key(size: geometry.size, scale: scale, ink: ink)
        let artwork = source(ink, outline: geometry.artworkOutlineRadius(scale: scale / oversample))
        if let cached = crosses[key] {
            return cached
        }
        let rect = geometry.crossRect
        let pixelWidth = Int((rect.width * scale).rounded(.up))
        let pixelHeight = Int((rect.height * scale).rounded(.up))
        let image = render(width: pixelWidth, height: pixelHeight) { context in
            context.scaleBy(
                x: CGFloat(pixelWidth) / rect.width,
                y: CGFloat(pixelHeight) / rect.height
            )
            context.interpolationQuality = .high
            let local = flipped(rect, height: geometry.size)
            let frame = flipped(
                geometry.artworkFrame(ink: ink, scale: scale / oversample), height: geometry.size
            )
            context.draw(
                artwork,
                in: frame.offsetBy(dx: -local.minX, dy: -local.minY)
            )
        }
        crosses[key] = image
        return image
    }

    /// Draws into a new premultiplied sRGB bitmap.
    ///
    /// - Parameters:
    ///   - width: The bitmap width in pixels.
    ///   - height: The bitmap height in pixels.
    ///   - draw: Draws the content into the bitmap's context, whose origin is the bottom left.
    /// - Returns: The finished bitmap, or `nil` when either dimension is zero or the context cannot be created.
    static func render(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }
        draw(context)
        return context.makeImage()
    }
}

extension ChiakiLogoArtwork {
    private static func loadArtwork(_ name: String) -> PlatformImage {
        guard let url = ChiakiAssets.url(forResource: name, withExtension: "png"),
              let image = PlatformImage(contentsOf: url)
        else {
            preconditionFailure("Missing bundled chiaki-ng artwork: \(name)")
        }
        return image
    }

    private static func source(_ ink: ChiakiLogoInk, outline radius: CGFloat) -> CGImage {
        switch ink {
        case .navy:
            return navySource
        case .outlined:
            if let cached = outlinedSources[radius] {
                return cached
            }
            let image = outlined(signallessSource, radius: radius)
            outlinedSources[radius] = image
            return image
        }
    }

    private static func outlined(_ image: CGImage, radius: CGFloat) -> CGImage {
        let padding = ChiakiLogoGeometry.artworkPadding(outline: radius)
        let artwork = CGRect(
            x: padding, y: padding, width: CGFloat(image.width), height: CGFloat(image.height)
        )
        let width = image.width + Int(padding) * 2
        let height = image.height + Int(padding) * 2
        guard let padded = render(width: width, height: height, draw: { context in
            context.draw(image, in: artwork)
        }),
            let outline = outlineMask(padded, radius: radius),
            let output = render(width: width, height: height, draw: { context in
                let extent = CGRect(x: 0, y: 0, width: width, height: height)
                context.setFillColor(outlineInk)
                context.saveGState()
                context.clip(to: extent, mask: outline)
                context.fill(extent)
                context.restoreGState()
                for eye in ChiakiLogoGeometry.artworkEyes {
                    context.fill(CGRect(
                        x: artwork.minX + eye.minX, y: artwork.maxY - eye.maxY,
                        width: eye.width, height: eye.height
                    ))
                }
                context.draw(image, in: artwork)
            })
        else {
            preconditionFailure("Unable to outline chiaki-ng artwork")
        }
        return output
    }

    private static func outlineMask(_ image: CGImage, radius: CGFloat) -> CGImage? {
        guard let mask = navyMask(image) else {
            return nil
        }
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let grow = CIFilter.morphologyMaximum()
        grow.inputImage = CIImage(cgImage: mask)
        grow.radius = Float(radius)
        let soften = CIFilter.gaussianBlur()
        soften.inputImage = grow.outputImage
        soften.radius = 1.2
        guard let grown = soften.outputImage?.cropped(to: extent),
              let gray = CGColorSpace(name: CGColorSpace.linearGray)
        else {
            return nil
        }
        return CIContext(options: [.workingColorSpace: NSNull()]).createCGImage(
            grown, from: extent, format: .L8, colorSpace: gray
        )
    }

    private static func navyMask(_ image: CGImage) -> CGImage? {
        render(width: image.width, height: image.height) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for row in 0..<image.height {
                let line = data + row * context.bytesPerRow
                for column in 0..<image.width {
                    let pixel = line + column * 4
                    let alpha = pixel[3]
                    let navy = alpha > 0 && CGFloat(pixel[1]) / CGFloat(alpha) < 0.5
                    let value = navy
                        ? alpha
                        : 0
                    pixel[0] = value
                    pixel[1] = value
                    pixel[2] = value
                    pixel[3] = value
                }
            }
        }
    }

    private static func resampled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let vertical = CGFloat(height) / CGFloat(image.height)
        let horizontal = CGFloat(width) / CGFloat(image.width)
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.scale = Float(vertical)
        filter.aspectRatio = Float(horizontal / vertical)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        guard let output = filter.outputImage?.cropped(to: extent),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        return CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
            .createCGImage(output, from: extent, format: .RGBA8, colorSpace: space)
    }

    #if !os(macOS)
        private static func sampledColor(x column: Int, y row: Int) -> PlatformColor {
            var components = [CGFloat](repeating: 0, count: 4)
            let source = navySource
            _ = render(width: source.width, height: source.height) { context in
                context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
                guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                let pixel = data + row * context.bytesPerRow + column * 4
                let alpha = CGFloat(pixel[3])
                guard alpha > 0 else {
                    return
                }
                components = [
                    CGFloat(pixel[0]) / alpha,
                    CGFloat(pixel[1]) / alpha,
                    CGFloat(pixel[2]) / alpha,
                    alpha / 255
                ]
            }
            return PlatformColor(
                red: components[0], green: components[1], blue: components[2], alpha: components[3]
            )
        }
    #endif

    private static func flipped(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
