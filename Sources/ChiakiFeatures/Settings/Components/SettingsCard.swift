import DesignSystem
import SwiftUI

/// A titled group of settings rows on a tinted card.
public struct SettingsCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private let title: String?
    private let content: Content

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - title: The heading above the card, if any.
    ///   - content: The rows inside the card.
    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// The card.
    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
            }
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.controlBackground.opacity(fillOpacity), in: GlassPanel.Radius.small.shape)
            .overlay {
                GlassPanel.Radius.small.shape.strokeBorder(.primary.opacity(0.08))
            }
        }
    }

    private var fillOpacity: Double {
        if reduceTransparency {
            return 1
        }
        return colorScheme == .dark
            ? 0.18
            : 0.32
    }
}
