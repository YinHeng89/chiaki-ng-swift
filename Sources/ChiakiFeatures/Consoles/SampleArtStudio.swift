import ChiakiModels
import CoreGraphics
import CoreText
import Foundation
import SwiftUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Draws and remembers the made-up layered art of the developer preview console cards: a gradient backdrop,
/// a plain figure and the game's name as its logo.
///
/// The app builds one studio in its composition root and supplies it through
/// `EnvironmentValues/sampleArtStudio`, so every preview card shares what was drawn.
public final class SampleArtStudio: @unchecked Sendable {
    /// The two colours of a sample backdrop's gradient.
    public struct Palette: Sendable {
        /// The colour at the backdrop's top leading corner.
        public let near: CGColor
        /// The colour at the backdrop's bottom trailing corner.
        public let far: CGColor

        /// Creates a palette.
        ///
        /// - Parameters:
        ///   - near: The colour at the backdrop's top leading corner.
        ///   - far: The colour at the backdrop's bottom trailing corner.
        public init(near: CGColor, far: CGColor) {
            self.near = near
            self.far = far
        }
    }

    /// Creates a studio that has drawn nothing yet.
    public init() {}

    /// The gradients a sample game's backdrop is drawn with.
    public static let palettes = [
        Palette(near: CGColor(red: 0.10, green: 0.16, blue: 0.42, alpha: 1),
                far: CGColor(red: 0.74, green: 0.30, blue: 0.52, alpha: 1)),
        Palette(near: CGColor(red: 0.05, green: 0.30, blue: 0.34, alpha: 1),
                far: CGColor(red: 0.86, green: 0.62, blue: 0.24, alpha: 1)),
        Palette(near: CGColor(red: 0.26, green: 0.10, blue: 0.36, alpha: 1),
                far: CGColor(red: 0.24, green: 0.60, blue: 0.82, alpha: 1)),
        Palette(near: CGColor(red: 0.34, green: 0.12, blue: 0.10, alpha: 1),
                far: CGColor(red: 0.90, green: 0.50, blue: 0.22, alpha: 1)),
        Palette(near: CGColor(red: 0.08, green: 0.24, blue: 0.16, alpha: 1),
                far: CGColor(red: 0.52, green: 0.78, blue: 0.44, alpha: 1))
    ]

    private let lock = NSLock()
    private var drawn: [String: GameArtLayers] = [:]

    /// The art of a sample game, drawn once and then remembered.
    ///
    /// - Parameter name: The sample game's name.
    /// - Returns: The art in debug builds, or `nil` in release builds or when drawing fails.
    public func layers(named name: String) -> GameArtLayers? {
        #if DEBUG
            lock.withLock {
                if let held = drawn[name] {
                    return held
                }
                let made = Self.draw(name)
                drawn[name] = made
                return made
            }
        #else
            nil
        #endif
    }

    /// The gradient of a sample game, picked by its name so it stays the same between runs.
    ///
    /// - Parameter name: The sample game's name.
    /// - Returns: One of ``palettes``.
    public static func palette(for name: String) -> Palette {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palettes[sum % palettes.count]
    }

    /// Draws the art of a sample game.
    ///
    /// - Parameter name: The sample game's name.
    /// - Returns: The art, or `nil` when a layer cannot be drawn.
    public static func draw(_ name: String) -> GameArtLayers? {
        let palette = palette(for: name)
        guard let background = backdrop(palette), let hero = figure(), let logo = wordmark(name) else {
            return nil
        }
        return GameArtLayers(background: background, hero: hero, logo: logo)
    }

    private static func canvas(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func backdrop(_ palette: Palette) -> CGImage? {
        guard let context = canvas(width: 960, height: 540),
              let gradient = CGGradient(
                  colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                      palette.near,
                      palette.far
                  ] as CFArray,
                  locations: [0, 1]
              ) else {
            return nil
        }
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 960, y: 540), options: []
        )
        context.setFillColor(CGColor(gray: 1, alpha: 0.10))
        for (index, radius) in [220.0, 140.0, 90.0].enumerated() {
            let centre = CGPoint(x: 700 - Double(index) * 210, y: 400 - Double(index) * 120)
            context.fillEllipse(in: CGRect(
                x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
            ))
        }
        return context.makeImage()
    }

    private static func figure() -> CGImage? {
        guard let context = canvas(width: 480, height: 640) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 0.96, alpha: 0.92))
        context.fillEllipse(in: CGRect(x: 170, y: 440, width: 140, height: 140))
        context.addPath(CGPath(
            roundedRect: CGRect(x: 110, y: 0, width: 260, height: 420), cornerWidth: 110,
            cornerHeight: 110,
            transform: nil
        ))
        context.fillPath()
        return context.makeImage()
    }

    private static func wordmark(_ name: String) -> CGImage? {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 96, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
        let text = NSAttributedString(
            string: name.uppercased(),
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                    gray: 1,
                    alpha: 1
                ),
                NSAttributedString.Key(kCTKernAttributeName as String): 4
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let margin = 16.0
        guard bounds.width > 0, bounds.height > 0,
              let context = canvas(
                  width: Int((bounds.width + margin * 2).rounded(.up)),
                  height: Int((bounds.height + margin * 2).rounded(.up))
              ) else {
            return nil
        }
        context.textPosition = CGPoint(x: margin - bounds.minX, y: margin - bounds.minY)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}

extension EnvironmentValues {
    /// The studio that draws the developer preview cards' sample art, which the app supplies at its root.
    @Entry public var sampleArtStudio = SampleArtStudio()
}
