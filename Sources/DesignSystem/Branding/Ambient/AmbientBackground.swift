import PlatformUI
import SwiftUI

/// The app's backdrop: a tinted field with soft blue and lime glows and drifting logo symbols.
///
/// The symbols drift from the window edges toward the centre on Core Animation layers while
/// ``AmbientMotionState`` allows motion, the scene is active and the background is not paused.
/// With Reduce Motion on, or when a preview time is given, they are drawn once as a still frame.
/// The background ignores hit testing and is hidden from accessibility.
public struct AmbientBackground: View {
    @Environment(\.colorScheme) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientMotion) private var ambientMotion

    private static let symbols: [Image] = {
        let source = AmbientMotifArtwork.source
        return AmbientMotif.regions.map { region in
            guard let image = source.cropping(to: region) else {
                preconditionFailure("Invalid symbol region")
            }
            return Image(decorative: image, scale: 1)
        }
    }()

    /// The fixed time, in seconds, at which to draw a still frame, or `nil` to animate.
    let previewTime: Double?

    /// Whether the symbols keep to the window edges so content in the middle stays clear.
    let quiet: Bool

    /// Whether the drifting symbols hold their current frame.
    let paused: Bool

    private let lime = Color(
        red: AmbientMotif.lime.red,
        green: AmbientMotif.lime.green,
        blue: AmbientMotif.lime.blue
    )

    private let blue = Color(
        red: AmbientMotif.blue.red,
        green: AmbientMotif.blue.green,
        blue: AmbientMotif.blue.blue
    )

    /// Creates a background.
    ///
    /// - Parameters:
    ///   - previewTime: A fixed time, in seconds, to draw a still frame at, or `nil` to animate.
    ///   - quiet: Whether the symbols keep to the window edges.
    ///   - paused: Whether the drifting symbols hold their current frame.
    public init(previewTime: Double? = nil, quiet: Bool = false, paused: Bool = false) {
        self.previewTime = previewTime
        self.quiet = quiet
        self.paused = paused
    }

    private var dark: Bool {
        appearance == .dark
    }

    /// The layered field, glows, symbols and horizontal veil.
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                (dark
                    ? Color(red: 0.055, green: 0.085, blue: 0.13)
                    : Color(red: 0.94, green: 0.96, blue: 0.94))
                if !reduceTransparency {
                    RadialGradient(
                        colors: [
                            blue.opacity(
                                dark
                                    ? 0.36
                                    : 0.13
                            ), .clear
                        ],
                        center: .init(x: 0.05, y: 0.82), startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.85
                    )
                    RadialGradient(
                        colors: [
                            lime.opacity(
                                dark
                                    ? 0.10
                                    : 0.13
                            ), .clear
                        ],
                        center: .init(x: 0.95, y: 0.12), startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.65
                    )
                }
                if previewTime != nil || reduceMotion {
                    Canvas(rendersAsynchronously: true) { context, canvasSize in
                        draw(context: context, size: canvasSize, time: previewTime ?? 0)
                    }
                } else {
                    AmbientMotifLayers(
                        quiet: quiet,
                        dark: dark,
                        running: !paused && scenePhase == .active && ambientMotion.isRunning
                    )
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(
                            color: (dark
                                ? Color(red: 0.065, green: 0.085, blue: 0.12)
                                : Color(red: 0.94, green: 0.96, blue: 0.94)).opacity(0.45),
                            location: 0.5
                        ),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction {
            $0.animation = nil
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, time: Double) {
        for motif in AmbientMotif.all {
            let frame = motif.frame(time: time, size: size, quiet: quiet, dark: dark)
            var layer = context
            layer.translateBy(x: frame.center.x, y: frame.center.y)
            layer.rotate(by: .radians(frame.rotation))
            layer.scaleBy(x: frame.side, y: frame.side)
            layer.opacity = frame.opacity
            var symbol = context.resolve(Self.symbols[motif.kind])
            symbol.shading = .color(
                motif.kind == 0
                    ? blue
                    : lime
            )
            drawSymbol(symbol, in: layer, kind: motif.kind)
        }
    }

    private func drawSymbol(
        _ symbol: GraphicsContext.ResolvedImage,
        in context: GraphicsContext,
        kind: Int
    ) {
        var layer = context
        if kind == 0 {
            layer.clip(to: Path(ellipseIn: CGRect(x: -0.5, y: -0.5, width: 1, height: 1)))
        }
        let aspect = AmbientMotif.aspects[kind]
        layer.draw(symbol, in: CGRect(x: -0.5, y: -0.5 / aspect, width: 1, height: 1 / aspect))
    }
}

/// Hosts the Core Animation drifting symbols of ``AmbientBackground`` in SwiftUI.
private struct AmbientMotifLayers: PlatformViewRepresentable {
    /// The platform view that owns the symbol layers.
    typealias PlatformViewType = AmbientMotifLayerView

    /// Whether symbols away from the edges are faded out.
    let quiet: Bool

    /// Whether the background uses its dark appearance.
    let dark: Bool

    /// Whether the symbols advance; when false they hold their current frame.
    let running: Bool

    /// Creates the layer view and applies the initial configuration.
    ///
    /// - Parameter context: The representable context.
    /// - Returns: A configured ``AmbientMotifLayerView``.
    func makePlatformView(context: Context) -> AmbientMotifLayerView {
        let view = AmbientMotifLayerView()
        view.configure(quiet: quiet, dark: dark, running: running)
        return view
    }

    /// Applies the current configuration to an existing layer view.
    ///
    /// - Parameters:
    ///   - view: The layer view created by ``makePlatformView(context:)``.
    ///   - context: The representable context.
    func updatePlatformView(_ view: AmbientMotifLayerView, context: Context) {
        view.configure(quiet: quiet, dark: dark, running: running)
    }
}
