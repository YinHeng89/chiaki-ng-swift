import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// A cloud cover that decodes to the size it is drawn at, showing a held decode at once when there is one.
public struct CloudArtworkView: View {
    private struct Request: Hashable {
        let url: URL?
        let box: ArtworkBox?
    }

    /// The cover's address.
    public let url: URL?
    /// Whether the cover fills its frame, cropping what overhangs, or fits inside it whole.
    public let contentMode: ContentMode
    @Environment(\.catalog) private var catalog
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var imageURL: URL?
    @State private var box: ArtworkBox?

    /// Creates a cover.
    ///
    /// - Parameters:
    ///   - url: The cover's address, or `nil` for the placeholder.
    ///   - contentMode: Whether the cover fills its frame or fits inside it whole.
    public init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    private var shownImage: CGImage? {
        image ?? url.flatMap { catalog.heldThumbnail($0, nil) }
    }

    private var placeholderOpacity: Double {
        shownImage == nil || contentMode == .fit
            ? 0.06
            : 0
    }

    public var body: some View {
        let scale = displayScale
        Rectangle()
            .fill(.white.opacity(placeholderOpacity))
            .overlay {
                if let image = shownImage {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
                } else {
                    Image(systemName: "gamecontroller").foregroundStyle(.white.opacity(0.4))
                }
            }
            .clipped()
            .onGeometryChange(for: ArtworkBox?.self) { geometry in
                ArtworkBox(points: geometry.size, scale: scale)
            } action: {
                box = $0
            }
            .task(id: Request(url: url, box: box)) {
                await load(url: url, box: box)
            }
    }

    private func load(url: URL?, box: ArtworkBox?) async {
        guard let url else {
            image = nil
            imageURL = nil
            return
        }
        if imageURL != url {
            image = catalog.heldThumbnail(url, nil)
            imageURL = image == nil
                ? nil
                : url
        }
        guard let box else {
            return
        }
        if let cached = catalog.heldThumbnail(url, box) {
            if cached !== image {
                image = cached
                imageURL = url
            }
            return
        }
        let thumbnail = try? await catalog.thumbnail(url, box)
        guard !Task.isCancelled, let thumbnail else {
            return
        }
        image = thumbnail
        imageURL = url
    }
}

extension EnvironmentValues {
    /// The cloud catalog the library and stream screens draw their artwork from and the release countdowns read
    /// the server time from, which the app supplies at its root.
    @Entry public var catalog = CatalogClient.testValue
}
