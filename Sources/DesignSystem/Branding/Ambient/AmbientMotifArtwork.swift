import ChiakiAssets
import CoreGraphics
import Foundation
import PlatformUI
import SwiftUI

/// The decoded logo artwork and the tinted symbols cut from it for ``AmbientBackground``.
@MainActor
enum AmbientMotifArtwork {
    /// The full-colour logo artwork decoded from the asset bundle.
    static let source: CGImage = {
        guard let url = ChiakiAssets.url(forResource: "chiaking-color", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let source = decoded(data)
        else {
            preconditionFailure("Missing chiaki-ng symbol artwork")
        }
        return source
    }()

    /// Each symbol in ``AmbientMotif/regions`` filled with its tint: blue clipped to a circle for
    /// kind zero, lime for the rest. Indexed by ``AmbientMotif/kind``.
    static let tinted: [CGImage] = {
        let artwork = source
        return AmbientMotif.regions.enumerated().map { kind, region in
            guard let symbol = artwork.cropping(to: region),
                  let image = tint(symbol, kind: kind)
            else {
                preconditionFailure("Invalid symbol region")
            }
            return image
        }
    }()

    private static func decoded(_ data: Data) -> CGImage? {
        #if os(macOS)
            NSBitmapImageRep(data: data)?.cgImage
        #else
            UIImage(data: data)?.cgImage
        #endif
    }

    private static func tint(_ symbol: CGImage, kind: Int) -> CGImage? {
        let color =
            kind == 0
                ? AmbientMotif.blue
                : AmbientMotif.lime
        let rect = CGRect(x: 0, y: 0, width: symbol.width, height: symbol.height)
        return ChiakiLogoArtwork.render(width: symbol.width, height: symbol.height) { context in
            if kind == 0 {
                context.addEllipse(in: rect)
                context.clip()
            }
            context.interpolationQuality = .high
            context.draw(symbol, in: rect)
            context.setBlendMode(.sourceIn)
            context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
            context.fill(rect)
        }
    }
}
