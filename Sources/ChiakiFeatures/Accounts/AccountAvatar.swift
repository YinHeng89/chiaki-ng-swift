import SwiftUI
import ComposableArchitecture
import PlatformUI
import DesignSystem

/// A 40 point circular account picture, decoded once and cached, or the name's first letter when
/// there is no usable image.
public struct AccountAvatar: View {
    /// The encoded avatar image, or `nil` to show the initial.
    public let data: Data?
    /// The account name whose first letter stands in for a missing avatar.
    public let name: String

    /// Creates an account avatar.
    ///
    /// - Parameters:
    ///   - data: The encoded avatar image, or `nil` to show the initial.
    ///   - name: The account name whose first letter stands in for a missing avatar.
    public init(data: Data?, name: String) {
        self.data = data
        self.name = name
    }

    private static let decoded: NSCache<NSData, PlatformImage> = {
        let cache = NSCache<NSData, PlatformImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 8_000_000
        return cache
    }()
    private var image: PlatformImage? {
        guard let data else {
            return nil
        }
        let key = data as NSData
        if let image = Self.decoded.object(forKey: key) {
            return image
        }
        guard let image = PlatformImage(data: data) else {
            return nil
        }
        Self.decoded.setObject(image, forKey: key, cost: data.count)
        return image
    }
    public var body: some View {
        Group {
            if let image {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased()).font(.title3.weight(.medium))
            }
        }
        .frame(width: 40, height: 40)
        .background(Palette.accent.opacity(0.18), in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}
