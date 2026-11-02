import PlatformUI
import SwiftUI
import Testing
@testable import DesignSystem

@MainActor @Test(arguments: [ColorScheme.light, .dark])
func logoHasVisibleArtwork(appearance: ColorScheme) throws {
    let image = try #require(renderLogoLayers(size: 120, scale: 1))
    let pixelWidth = image.width
    let pixelHeight = image.height
    var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
    let context = try #require(
        CGContext(
            data: &pixels, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    let visible = stride(from: 3, to: pixels.count, by: 4).filter {
        pixels[$0] > 100
    }.count
    #expect(visible > 2500, "Logo rendered only \(visible) visible pixels")
    if let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] {
        let appearanceName = appearance == .dark
            ? "dark"
            : "light"
        try renderBackground(directory: directory, appearance: appearance, appearanceName: appearanceName)
    }
}

@MainActor private func renderBackground(
    directory: String,
    appearance: ColorScheme,
    appearanceName: String
) throws {
    let background = ImageRenderer(
        content: AmbientBackground(previewTime: 0)
            .environment(\.colorScheme, appearance)
            .frame(width: 1920, height: 1080)
    )
    let backgroundImage = try #require(background.cgImage)
    let backgroundData = try #require(
        NSBitmapImageRep(cgImage: backgroundImage).representation(using: .png, properties: [:])
    )
    try backgroundData.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent(
            "ambient-\(appearanceName).png"
        )
    )
}

@MainActor func renderLogoLayers(size: CGFloat, scale: CGFloat, ink: ChiakiLogoInk = .navy) -> CGImage? {
    let geometry = ChiakiLogoGeometry(size: size)
    let view = ChiakiLogoLayerView(
        frame: CGRect(x: 0, y: 0, width: geometry.width + geometry.padding * 2, height: size * 1.44)
    )
    view.configure(geometry: geometry, isConnecting: false, replay: 0, running: false, ink: ink)
    view.layout()
    let pixelWidth = Int((view.bounds.width * scale).rounded(.up))
    let pixelHeight = Int((view.bounds.height * scale).rounded(.up))
    guard let context = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.scaleBy(x: scale, y: scale)
    view.stage.render(in: context)
    return context.makeImage()
}

@MainActor @Test func darkAppearanceOutlinesTheNavyPartsInLime() throws {
    let artwork = ChiakiLogoArtwork.image(.outlined)
    let tiff = try #require(artwork.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let navy = try #require(ChiakiLogoArtwork.faceColor.usingColorSpace(.sRGB))
    let lime = try #require(ChiakiLogoArtwork.squareColor.usingColorSpace(.sRGB))
    func matches(_ color: NSColor?, _ expected: NSColor) -> Bool {
        guard let color = color?.usingColorSpace(.sRGB), color.alphaComponent > 0.98 else {
            return false
        }
        return abs(color.redComponent - expected.redComponent) < 0.03
            && abs(color.greenComponent - expected.greenComponent) < 0.03
            && abs(color.blueComponent - expected.blueComponent) < 0.03
    }
    #expect(matches(bitmap.colorAt(x: 780, y: 180), navy))
    #expect(matches(bitmap.colorAt(x: 1800, y: 220), lime))
    #expect(matches(bitmap.colorAt(x: 680, y: 380), lime))
    var row = 180
    while row > 0, matches(bitmap.colorAt(x: 780, y: row), navy) {
        row -= 1
    }
    #expect(matches(bitmap.colorAt(x: 780, y: row - 4), lime))
    if let directory = ProcessInfo.processInfo.environment["CHIAKI_RENDER_CHECK_DIR"] {
        let logo = try #require(renderLogoLayers(size: 120, scale: 2, ink: .outlined))
        let width = logo.width
        let height = logo.height
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(logo, in: CGRect(x: 0, y: 0, width: width, height: height))
        let composed = try #require(context.makeImage())
        let data = try #require(NSBitmapImageRep(cgImage: composed).representation(
            using: .png,
            properties: [:]
        ))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("logo-dark-ink.png"))
    }
}
