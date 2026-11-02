import PlatformUI
import SwiftUI

/// The chiaki-ng mascot logo, animated when motion is allowed and static otherwise.
///
/// The logo bobs, blinks, sends signal waves, fills its square and spins its cross while
/// ``AmbientMotionState`` reports that ambient motion is running. With Reduce Motion on it shows
/// the still artwork instead. Clicking the logo restarts the animation, and raising ``spins`` turns the whole
/// logo once, unless Reduce Motion is on. It is decoration, so it never takes keyboard or controller focus.
public struct ChiakiLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.ambientMotion) private var ambientMotion
    @State private var replay = 0
    @State private var turns = 0.0

    /// The height of the logo in points; the width follows the artwork's aspect ratio.
    let size: CGFloat

    /// Whether the signal waves travel at the faster pace that shows a connection in progress.
    let isConnecting: Bool

    /// How many times the logo has been asked to spin; each increase turns it once.
    let spins: Int

    /// Creates a logo.
    ///
    /// - Parameters:
    ///   - size: The height of the logo in points.
    ///   - isConnecting: Whether the signal waves travel at the faster connecting pace.
    ///   - spins: How many times the logo has been asked to spin; each increase turns it once.
    public init(size: CGFloat = 96, isConnecting: Bool = false, spins: Int = 0) {
        self.size = size
        self.isConnecting = isConnecting
        self.spins = spins
    }

    private var geometry: ChiakiLogoGeometry {
        ChiakiLogoGeometry(size: size)
    }

    private var artwork: some View {
        let ink = ChiakiLogoInk(colorScheme)
        let margin = geometry.artworkMargin(ink: ink, scale: displayScale)
        return Image(platformImage: ChiakiLogoArtwork.image(ink, size: size, scale: displayScale))
            .resizable()
            .interpolation(.high)
            .frame(width: geometry.width + margin * 2, height: size + margin * 2)
            .padding(-margin)
    }

    private var animatedArtwork: some View {
        ChiakiLogoLayers(
            geometry: geometry,
            isConnecting: isConnecting,
            replay: replay,
            running: ambientMotion.isRunning,
            ink: ChiakiLogoInk(colorScheme)
        )
        .frame(width: geometry.width + geometry.padding * 2, height: size + geometry.padding * 2)
        .padding(-geometry.padding)
    }

    /// The logo as a plain, unfocusable button that restarts the animation when clicked.
    public var body: some View {
        Button {
            replay += 1
        } label: {
            Group {
                if reduceMotion {
                    artwork
                } else {
                    animatedArtwork
                }
            }
            .frame(width: geometry.width, height: size, alignment: .center)
            .rotationEffect(.degrees(turns * 360))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("chiaki-ng logo")
        .accessibilityHint("Restart logo animation")
        .onChange(of: spins) { previous, current in
            guard current > previous, !reduceMotion else {
                return
            }
            withAnimation(.spring(duration: 1.1, bounce: 0.25)) {
                turns += 1
            }
        }
    }
}

/// Hosts the Core Animation logo in SwiftUI and forwards configuration changes to it.
private struct ChiakiLogoLayers: PlatformViewRepresentable {
    /// The platform view that owns the logo's layers.
    typealias PlatformViewType = ChiakiLogoLayerView

    /// The layout of the logo.
    let geometry: ChiakiLogoGeometry

    /// Whether the signal waves travel at the faster connecting pace.
    let isConnecting: Bool

    /// A counter that restarts every animation from the beginning whenever it changes.
    let replay: Int

    /// Whether the animation advances; when false it holds its current frame.
    let running: Bool

    /// The ink the logo is drawn in.
    let ink: ChiakiLogoInk

    /// Creates the layer view and applies the initial configuration.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: A configured ``ChiakiLogoLayerView``.
    func makePlatformView(context: Context) -> ChiakiLogoLayerView {
        let view = ChiakiLogoLayerView()
        configure(view)
        return view
    }

    /// Applies the current configuration to an existing layer view.
    ///
    /// - Parameters:
    ///   - view: The layer view created by ``makePlatformView(context:)``.
    ///   - context: The representable context.
    func updatePlatformView(_ view: ChiakiLogoLayerView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ChiakiLogoLayerView) {
        view.configure(
            geometry: geometry,
            isConnecting: isConnecting,
            replay: replay,
            running: running,
            ink: ink
        )
    }
}
