import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code of some text, drawn dark on a light quiet zone so phone cameras read it in either appearance.
///
/// The code comes from Core Image's QR code generator at medium error correction and is scaled up without
/// smoothing, so every module keeps sharp edges. Nothing is drawn when the text cannot be encoded.
public struct QRCodeImage: View {
    /// The text the code encodes.
    let text: String
    /// The side of the drawn code, in points.
    let side: CGFloat
    /// What VoiceOver says for the code.
    let label: String

    /// Creates the code.
    ///
    /// - Parameters:
    ///   - text: The text to encode, usually an address.
    ///   - side: The side of the drawn code, in points.
    ///   - label: What VoiceOver says for the code.
    public init(_ text: String, side: CGFloat, label: String) {
        self.text = text
        self.side = side
        self.label = label
    }

    /// The code on its quiet zone.
    public var body: some View {
        Group {
            if let image = Self.image(of: text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(side * Self.quietZone)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    /// The share of the side kept white around the modules.
    static let quietZone: CGFloat = 0.06

    /// The QR code of some text, one pixel per module.
    ///
    /// - Parameter text: The text to encode.
    /// - Returns: The code, or `nil` when the text is empty or cannot be encoded.
    static func image(of text: String) -> CGImage? {
        guard !text.isEmpty else {
            return nil
        }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            return nil
        }
        return context.createCGImage(output, from: output.extent)
    }

    private static let context = CIContext()
}
