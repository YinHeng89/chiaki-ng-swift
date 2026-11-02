import PlatformUI
import QuartzCore
import SwiftUI

/// The platform view that animates every ``AmbientMotif`` as its own Core Animation layer.
///
/// Each symbol gets a repeating travel animation (position, scale and opacity) and a separate
/// rocking rotation. The layers are rebuilt only when the size, quietness or appearance changes;
/// pausing goes through the inherited ``AmbientLayerHostView/clock``.
final class AmbientMotifLayerView: AmbientLayerHostView {
    private struct Configuration: Equatable {
        let size: CGSize
        let quiet: Bool
        let dark: Bool
    }

    private var configuration: Configuration?
    private var quiet = false
    private var dark = false

    /// Creates an empty view; the symbols are built once it has a size.
    ///
    /// - Parameter frameRect: The initial frame.
    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
    }

    /// Unsupported; the view is only created in code.
    ///
    /// - Parameter coder: The unarchiver, which is ignored.
    required init?(coder: NSCoder) {
        nil
    }

    /// Updates how the symbols are drawn and whether they move.
    ///
    /// - Parameters:
    ///   - quiet: Whether symbols away from the edges are faded out.
    ///   - dark: Whether the background uses its dark appearance.
    ///   - running: Whether the symbols advance.
    func configure(quiet: Bool, dark: Bool, running: Bool) {
        self.quiet = quiet
        self.dark = dark
        rebuildIfNeeded()
        clock.set(running: running)
    }

    /// Rebuilds the symbols when the view's size changed.
    override func arrange() {
        rebuildIfNeeded()
    }

    private static func frame(
        _ motif: AmbientMotif,
        progress: Double,
        configuration: Configuration
    ) -> AmbientMotif.Frame {
        motif.frame(
            progress: progress,
            rotation: 0,
            size: configuration.size,
            quiet: configuration.quiet,
            dark: configuration.dark
        )
    }

    private static func symbol(_ motif: AmbientMotif, configuration: Configuration) -> CALayer {
        let current = motif.frame(
            time: 0,
            size: configuration.size,
            quiet: configuration.quiet,
            dark: configuration.dark
        )
        let symbol = CALayer()
        symbol.bounds = CGRect(x: 0, y: 0, width: 100, height: 100 / AmbientMotif.aspects[motif.kind])
        symbol.contents = AmbientMotifArtwork.tinted[motif.kind]
        symbol.contentsGravity = .resize
        symbol.position = current.center
        symbol.opacity = Float(current.opacity)
        symbol.transform = CATransform3DScale(
            CATransform3DMakeRotation(current.rotation, 0, 0, 1),
            current.side / 100,
            current.side / 100,
            1
        )
        return symbol
    }

    private static func travel(
        _ motif: AmbientMotif,
        configuration: Configuration,
        begin: CFTimeInterval
    ) -> CAAnimationGroup {
        let start = frame(motif, progress: 0, configuration: configuration)
        let end = frame(motif, progress: 1, configuration: configuration)
        let opacityTimes = AmbientKeyframes.samples(count: 560)
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [start.center as NSValue, end.center as NSValue]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [start.side / 100, end.side / 100]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = opacityTimes.map {
            frame(motif, progress: $0, configuration: configuration).opacity
        }
        opacity.keyTimes = opacityTimes.map {
            NSNumber(value: $0)
        }
        for animation in [position, scale, opacity] {
            animation.duration = AmbientMotif.period
            animation.calculationMode = .linear
        }
        let travel = CAAnimationGroup()
        travel.animations = [position, scale, opacity]
        travel.duration = AmbientMotif.period
        travel.repeatCount = .infinity
        travel.timeOffset = motif.phase * AmbientMotif.period
        travel.beginTime = begin
        travel.isRemovedOnCompletion = false
        travel.fillMode = .both
        return travel
    }

    private static func rotation(_ motif: AmbientMotif, begin: CFTimeInterval) -> CAKeyframeAnimation {
        let times = AmbientKeyframes.samples(count: 320)
        return AmbientKeyframes.repeating(
            "transform.rotation.z",
            values: times.map {
                motif.rotation(at: $0 * AmbientMotif.rotationPeriod)
            },
            keyTimes: times,
            duration: AmbientMotif.rotationPeriod,
            begin: begin
        )
    }

    private func rebuildIfNeeded() {
        let next = Configuration(size: bounds.size, quiet: quiet, dark: dark)
        guard next != configuration else {
            return
        }
        configuration = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        stage.sublayers?.forEach {
            $0.removeFromSuperlayer()
        }
        if next.size.width > 0, next.size.height > 0 {
            build(next)
        }
        CATransaction.commit()
    }

    private func build(_ configuration: Configuration) {
        let begin = clock.now
        for motif in AmbientMotif.all {
            let symbol = Self.symbol(motif, configuration: configuration)
            symbol.add(Self.travel(motif, configuration: configuration, begin: begin), forKey: "travel")
            symbol.add(Self.rotation(motif, begin: begin), forKey: "rotation")
            stage.addSublayer(symbol)
        }
    }
}
