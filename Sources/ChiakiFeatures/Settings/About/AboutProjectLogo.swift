import ChiakiAssets
import PlatformUI
import SwiftUI

/// An affiliated project's logo in a small rounded tile, as the About pages list it.
struct AboutProjectLogo: View {
    /// The logo to draw.
    let logo: AboutProject.Logo

    /// The tile's width and height.
    var side: CGFloat = 32

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side / 4, style: .continuous)
    }

    /// The logo, or a neutral stand-in while it loads or when it cannot be read.
    var body: some View {
        content
            .frame(width: side, height: side)
            .clipShape(shape)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch logo {
        case .bundled(let name):
            if let image = Self.bundled(name) {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                standIn("photo")
            }
        case .remote(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    standIn("photo")
                }
            }
        case .symbol(let name):
            standIn(name)
        }
    }

    private func standIn(_ symbol: String) -> some View {
        ZStack {
            shape.fill(Color.primary.opacity(0.08))
            Image(systemName: symbol)
                .font(.system(size: side * 0.45, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private static func bundled(_ name: String) -> PlatformImage? {
        ChiakiAssets.url(forResource: name, withExtension: "png").flatMap { url in
            PlatformImage(contentsOf: url)
        }
    }
}
