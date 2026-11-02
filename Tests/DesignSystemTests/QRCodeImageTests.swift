import CoreImage
import Testing
@testable import DesignSystem

@MainActor @Test func aStorePageCodeScansBackToThePage() throws {
    let page = "https://store.playstation.com/en-gb/concept/10010334"
    let code = try #require(QRCodeImage.image(of: page))
    let detector = try #require(CIDetector(
        ofType: CIDetectorTypeQRCode,
        context: nil,
        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    ))
    let scaled = CIImage(cgImage: code).samplingNearest().transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let quietZone = scaled.extent.insetBy(dx: -40, dy: -40)
    let padded = scaled.composited(over: CIImage(color: .white).cropped(to: quietZone))
    let read = detector.features(in: padded).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    #expect(read == [page])
}

@MainActor @Test func noCodeIsDrawnForEmptyText() {
    #expect(QRCodeImage.image(of: "") == nil)
}
