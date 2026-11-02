import SwiftUI

#if canImport(AppKit)
    import AppKit

    extension NSImage {
        /// The image's bitmap, rendered at its natural size.
        public var platformCGImage: CGImage? {
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    extension Image {
        /// Creates a SwiftUI image from a platform image.
        ///
        /// - Parameter platformImage: The `NSImage` to show.
        public init(platformImage: PlatformImage) {
            self.init(nsImage: platformImage)
        }
    }
#else
    import UIKit

    extension UIImage {
        /// Loads an image from a file URL, matching the `NSImage` initialiser of the same shape.
        ///
        /// - Parameter url: The file to read.
        public convenience init?(contentsOf url: URL) {
            self.init(contentsOfFile: url.path)
        }

        /// Wraps a bitmap at the scale that makes it fill a size in points, matching the `NSImage`
        /// initialiser of the same shape.
        ///
        /// - Parameters:
        ///   - cgImage: The bitmap.
        ///   - size: The size in points the bitmap should cover.
        public convenience init(cgImage: CGImage, size: CGSize) {
            let scale: CGFloat = size.width > 0
                ? CGFloat(cgImage.width) / size.width
                : 1
            self.init(cgImage: cgImage, scale: scale, orientation: .up)
        }

        /// The image's bitmap.
        public var platformCGImage: CGImage? {
            cgImage
        }
    }

    extension Image {
        /// Creates a SwiftUI image from a platform image.
        ///
        /// - Parameter platformImage: The `UIImage` to show.
        public init(platformImage: PlatformImage) {
            self.init(uiImage: platformImage)
        }
    }
#endif
