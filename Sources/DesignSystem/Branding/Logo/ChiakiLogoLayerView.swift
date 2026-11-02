import CoreGraphics
import PlatformUI
import QuartzCore
import SwiftUI

/// The platform view that draws the animated logo with Core Animation layers.
///
/// The layers are rebuilt only when the geometry, connecting pace, replay counter, display scale
/// or ink changes; pausing and resuming go through the inherited ``AmbientLayerHostView/clock``
/// so the animation continues from where it stopped.
final class ChiakiLogoLayerView: AmbientLayerHostView {
    private struct Configuration: Equatable {
        let geometry: ChiakiLogoGeometry
        let isConnecting: Bool
        let replay: Int
        let scale: CGFloat
        let ink: ChiakiLogoInk
    }

    private var configuration: Configuration?
    private var geometry = ChiakiLogoGeometry(size: 96)
    private var isConnecting = false
    private var replay = 0
    private var ink = ChiakiLogoInk.navy

    /// Creates an empty logo view that lets its layers draw past its bounds.
    ///
    /// - Parameter frameRect: The initial frame.
    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        #if os(macOS)
            layer?.masksToBounds = false
        #endif
    }

    /// Unsupported; the view is only created in code.
    ///
    /// - Parameter coder: The unarchiver, which is ignored.
    required init?(coder: NSCoder) {
        nil
    }

    /// Updates what the logo shows and whether it animates.
    ///
    /// - Parameters:
    ///   - geometry: The layout of the logo.
    ///   - isConnecting: Whether the signal waves travel at the faster connecting pace.
    ///   - replay: A counter that restarts the animation whenever it changes.
    ///   - running: Whether the animation advances.
    ///   - ink: The ink the logo is drawn in.
    func configure(
        geometry: ChiakiLogoGeometry,
        isConnecting: Bool,
        replay: Int,
        running: Bool,
        ink: ChiakiLogoInk
    ) {
        self.geometry = geometry
        self.ink = ink
        self.isConnecting = isConnecting
        self.replay = replay
        rebuildIfNeeded()
        clock.set(running: running)
    }

    /// Fits the stage to the view and rebuilds the layers if the configuration changed.
    override func arrange() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        CATransaction.commit()
        rebuildIfNeeded()
    }

    /// Rebuilds the layers at the new display scale.
    override func backingChanged() {
        rebuildIfNeeded()
    }

    private func rebuildIfNeeded() {
        let next = Configuration(
            geometry: geometry, isConnecting: isConnecting, replay: replay, scale: backingScale, ink: ink
        )
        guard next != configuration else {
            return
        }
        configuration = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.sublayers?.forEach {
            $0.removeFromSuperlayer()
        }
        build(next)
        CATransaction.commit()
    }

    private func build(_ configuration: Configuration) {
        let builder = ChiakiLogoLayerBuilder(
            geometry: configuration.geometry,
            scale: configuration.scale,
            begin: clock.now,
            isConnecting: configuration.isConnecting,
            ink: configuration.ink
        )
        let content = builder.content()
        stage.addSublayer(content)
        content.addSublayer(builder.base())
        builder.waves().forEach(content.addSublayer)
        content.addSublayer(builder.eyes())
        content.addSublayer(builder.fill())
        content.addSublayer(builder.cross())
    }
}

@MainActor
private struct ChiakiLogoLayerBuilder {
    let geometry: ChiakiLogoGeometry
    let scale: CGFloat
    let begin: CFTimeInterval
    let isConnecting: Bool
    let ink: ChiakiLogoInk

    func content() -> CALayer {
        let content = CALayer()
        content.frame = CGRect(
            x: geometry.padding,
            y: geometry.padding,
            width: geometry.width,
            height: geometry.size
        )
        let period = ChiakiLogoMotion.bobPeriod
        content.add(
            sampled("transform.translation.y", times: AmbientKeyframes.samples(count: 192), period: period) {
                ChiakiLogoMotion.bob($0 * period, in: geometry)
            },
            forKey: "bob"
        )
        return content
    }

    func base() -> CALayer {
        let base = CALayer()
        base.frame = geometry.artworkFrame(ink: ink, scale: scale)
        base.contents = ChiakiLogoArtwork.base(for: geometry, scale: scale, ink: ink)
        base.contentsGravity = .resize
        base.contentsScale = scale
        return base
    }

    func waves() -> [CALayer] {
        let color = ink == .outlined
            ? ChiakiLogoArtwork.outlineInk
            : ChiakiLogoArtwork.faceColor.cgColor
        let period = ChiakiLogoMotion.wavePeriod(connecting: isConnecting)
        let travel = [
            ChiakiLogoMotion.wavePath(progress: 0, in: geometry).cgPath,
            ChiakiLogoMotion.wavePath(progress: 1, in: geometry).cgPath
        ]
        return (0..<3).map { index in
            let phase = Double(index) / 3
            let wave = CAShapeLayer()
            wave.frame = geometry.bounds
            wave.fillColor = nil
            wave.strokeColor = color
            wave.lineWidth = geometry.waveLineWidth
            wave.lineCap = .round
            wave.contentsScale = scale
            wave.path = ChiakiLogoMotion.wavePath(progress: phase, in: geometry).cgPath
            wave.opacity = Float(ChiakiLogoMotion.waveOpacity(progress: phase))
            wave.add(
                AmbientKeyframes.repeating(
                    "path", values: travel, duration: period, offset: phase * period, begin: begin
                ),
                forKey: "path"
            )
            wave.add(
                sampled(
                    "opacity",
                    times: AmbientKeyframes.samples(count: 120),
                    period: period,
                    offset: phase * period
                ) {
                    ChiakiLogoMotion.waveOpacity(progress: $0)
                },
                forKey: "opacity"
            )
            return wave
        }
    }

    func eyes() -> CALayer {
        let eyes = CAShapeLayer()
        eyes.frame = geometry.bounds
        eyes.fillColor = ChiakiLogoArtwork.faceColor.cgColor
        eyes.contentsScale = scale
        eyes.path = ChiakiLogoMotion.eyelidPath(0, in: geometry)
        let period = ChiakiLogoMotion.blinkPeriod
        eyes.add(
            sampled("path", times: ChiakiLogoMotion.blinkKeyTimes(), period: period) {
                ChiakiLogoMotion.eyelidPath($0 * period, in: geometry)
            },
            forKey: "blink"
        )
        return eyes
    }

    func fill() -> CALayer {
        let fill = CAShapeLayer()
        fill.frame = geometry.bounds
        fill.fillColor = ChiakiLogoArtwork.squareColor.cgColor
        fill.contentsScale = scale
        fill.path = ChiakiLogoMotion.fillPath(0, in: geometry)
        let period = ChiakiLogoMotion.fillPeriod
        fill.add(
            sampled("path", times: AmbientKeyframes.samples(count: 192), period: period) {
                ChiakiLogoMotion.fillPath($0 * period, in: geometry)
            },
            forKey: "fill"
        )
        return fill
    }

    func cross() -> CALayer {
        let period = ChiakiLogoMotion.spinPeriod
        let times = ChiakiLogoMotion.spinKeyTimes()
        let hop = CALayer()
        hop.frame = geometry.bounds
        hop.add(
            sampled("transform.translation.y", times: times, period: period) {
                ChiakiLogoMotion.hop($0 * period, in: geometry)
            },
            forKey: "hop"
        )
        let cross = CALayer()
        let crossRect = geometry.crossRect
        let pivot = geometry.crossPivot
        cross.bounds = CGRect(origin: .zero, size: crossRect.size)
        cross.anchorPoint = CGPoint(
            x: (pivot.x - crossRect.minX) / crossRect.width,
            y: (pivot.y - crossRect.minY) / crossRect.height
        )
        cross.position = pivot
        cross.contents = ChiakiLogoArtwork.cross(
            for: geometry,
            scale: scale * ChiakiLogoArtwork.oversample,
            ink: ink
        )
        cross.contentsGravity = .resize
        cross.contentsScale = scale * ChiakiLogoArtwork.oversample
        cross.add(
            sampled("transform.rotation.z", times: times, period: period) {
                ChiakiLogoMotion.spinAngle(min($0, 1 - 1e-9) * period) * .pi / 180
            },
            forKey: "spin"
        )
        hop.addSublayer(cross)
        return hop
    }

    private func sampled(
        _ keyPath: String,
        times: [Double],
        period: Double,
        offset: Double = 0,
        value: (Double) -> Any
    ) -> CAKeyframeAnimation {
        AmbientKeyframes.repeating(
            keyPath,
            values: times.map(value),
            keyTimes: times,
            duration: period,
            offset: offset,
            begin: begin
        )
    }
}

/// The timing curves of the animated logo, as pure functions of elapsed time in seconds.
///
/// Each part of the logo loops on its own period: the whole logo bobs, three signal waves rise
/// from the antenna, the eyes blink twice, the square fills with lime and drains, and the cross
/// wobbles before hopping through a full turn. Distances scale with ``ChiakiLogoGeometry/size``.
enum ChiakiLogoMotion {
    /// The length in seconds of one up-and-down bob of the whole logo.
    static let bobPeriod = 6.4

    /// The length in seconds of one blink cycle, which holds two blinks.
    static let blinkPeriod = 6.24

    /// The length in seconds of one fill and drain of the lime square.
    static let fillPeriod = 6.4

    /// The length in seconds of one cross cycle: a gentle wobble followed by a full turn.
    static let spinPeriod = 5.4

    /// The time one signal wave takes to rise from the antenna and fade out.
    ///
    /// - Parameter connecting: Whether a connection is in progress.
    /// - Returns: 2.3 seconds while connecting, otherwise 3.6 seconds.
    static func wavePeriod(connecting: Bool) -> Double {
        connecting
            ? 2.3
            : 3.6
    }

    /// The smoothstep ease, which starts and ends with zero velocity.
    ///
    /// - Parameter value: The linear progress; values outside zero to one are clamped.
    /// - Returns: The eased progress from zero to one.
    static func smooth(_ value: Double) -> Double {
        let progress = min(1, max(0, value))
        return progress * progress * (3 - 2 * progress)
    }

    /// The vertical offset of the whole logo.
    ///
    /// - Parameters:
    ///   - elapsed: The time since the animation started, in seconds.
    ///   - geometry: The layout of the logo.
    /// - Returns: A sine offset in points, one hundred and twentieth of the logo height at its peak.
    static func bob(_ elapsed: Double, in geometry: ChiakiLogoGeometry) -> CGFloat {
        sin(elapsed * .pi / 3.2) * geometry.size / 120
    }

    /// How far one of the three staggered signal waves has travelled.
    ///
    /// - Parameters:
    ///   - elapsed: The time since the animation started, in seconds.
    ///   - index: The wave, from zero to two; each starts a third of a period after the previous one.
    ///   - connecting: Whether a connection is in progress.
    /// - Returns: The wave's progress from zero at the antenna to one at the top.
    static func waveProgress(_ elapsed: Double, index: Int, connecting: Bool) -> Double {
        (elapsed / wavePeriod(connecting: connecting) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
    }

    /// The arc of one signal wave above the antenna.
    ///
    /// The arc widens, rises and bends further as it travels, all linearly in `progress`, so
    /// interpolating between the paths at zero and one reproduces every frame in between.
    ///
    /// - Parameters:
    ///   - progress: The wave's progress from zero at the antenna to one at the top.
    ///   - geometry: The layout of the logo.
    /// - Returns: A quadratic arc in logo coordinates.
    static func wavePath(progress: Double, in geometry: ChiakiLogoGeometry) -> Path {
        let width = geometry.width
        let size = geometry.size
        let spread = width * (0.040 + 0.105 * progress)
        let crest = size * (0.16 - 0.24 * progress)
        let bend = size * (0.025 + 0.045 * progress)
        var wave = Path()
        wave.move(to: CGPoint(x: width * 0.13 - spread, y: crest + bend))
        wave.addQuadCurve(
            to: CGPoint(x: width * 0.13 + spread, y: crest + bend),
            control: CGPoint(x: width * 0.13, y: crest - bend)
        )
        return wave
    }

    /// The opacity of a signal wave, which fades in from the antenna and out at the top.
    ///
    /// - Parameter progress: The wave's progress from zero to one.
    /// - Returns: An opacity peaking at 0.85 halfway through.
    static func waveOpacity(progress: Double) -> Double {
        pow(max(0, sin(.pi * progress)), 0.8) * 0.85
    }

    /// How far the eyelids are closed during one blink.
    ///
    /// - Parameter time: The time since this blink started, in seconds.
    /// - Returns: Zero outside the 0.28 second blink; otherwise closing over 0.10 seconds to 0.94
    ///   and reopening over 0.18 seconds.
    static func blink(_ time: Double) -> Double {
        guard time >= 0, time < 0.28 else {
            return 0
        }
        return
            (time < 0.10
                ? smooth(time / 0.10)
                : 1 - smooth((time - 0.10) / 0.18)) * 0.94
    }

    /// The eyelids drawn over both eyes, closing from the top and the bottom at once.
    ///
    /// Each cycle of ``blinkPeriod`` blinks at 3.4 and 3.86 seconds. The path always holds four
    /// rectangles, collapsed to zero height when open, so it interpolates between key frames.
    ///
    /// - Parameters:
    ///   - elapsed: The time since the animation started, in seconds.
    ///   - geometry: The layout of the logo.
    /// - Returns: The eyelid rectangles in logo coordinates.
    static func eyelidPath(_ elapsed: Double, in geometry: ChiakiLogoGeometry) -> CGPath {
        let width = geometry.width
        let size = geometry.size
        let blinkTime = elapsed.truncatingRemainder(dividingBy: blinkPeriod)
        let closure = max(blink(blinkTime - 3.4), blink(blinkTime - 3.86))
        let path = CGMutablePath()
        for eye in ChiakiLogoGeometry.artworkEyes {
            let lid = size * eye.height / 1215 * closure / 2
            for eyeY in [size * eye.minY / 1215, size * eye.maxY / 1215 - lid] {
                path.addRect(
                    CGRect(
                        x: width * eye.minX / 2044,
                        y: eyeY,
                        width: width * eye.width / 2044,
                        height: lid
                    )
                )
            }
        }
        return path
    }

    /// The lime rising inside the square, filling and draining on a cosine over ``fillPeriod``.
    ///
    /// - Parameters:
    ///   - elapsed: The time since the animation started, in seconds.
    ///   - geometry: The layout of the logo.
    /// - Returns: One rectangle anchored to the bottom of the square, in logo coordinates.
    static func fillPath(_ elapsed: Double, in geometry: ChiakiLogoGeometry) -> CGPath {
        let width = geometry.width
        let size = geometry.size
        let fill = (1 - cos(elapsed * 2 * .pi / fillPeriod)) / 2
        let fillHeight = size * 290 / 1215 * fill
        let path = CGMutablePath()
        path.addRect(
            CGRect(
                x: width * 1691 / 2044,
                y: size * 556 / 1215 - fillHeight,
                width: width * 290 / 2044,
                height: fillHeight
            )
        )
        return path
    }

    /// The rotation of the cross.
    ///
    /// - Parameter elapsed: The time since the animation started, in seconds.
    /// - Returns: The angle in degrees: a wobble of up to five degrees for the first 3.4 seconds of
    ///   each ``spinPeriod``, then an eased full turn over 1.2 seconds.
    static func spinAngle(_ elapsed: Double) -> Double {
        let spinTime = elapsed.truncatingRemainder(dividingBy: spinPeriod)
        if spinTime < 3.4 {
            return sin(spinTime * .pi / 1.7) * 5
        }
        return smooth((spinTime - 3.4) / 1.2) * 360
    }

    /// The upward jump of the cross while it turns.
    ///
    /// - Parameters:
    ///   - elapsed: The time since the animation started, in seconds.
    ///   - geometry: The layout of the logo.
    /// - Returns: A vertical offset in points, zero outside the turn and peaking at seven
    ///   hundred and twentieths of the logo height.
    static func hop(_ elapsed: Double, in geometry: ChiakiLogoGeometry) -> CGFloat {
        let spinTime = elapsed.truncatingRemainder(dividingBy: spinPeriod)
        guard spinTime >= 3.4, spinTime <= 4.6 else {
            return 0
        }
        return -sin((spinTime - 3.4) / 1.2 * .pi) * geometry.size * 7 / 120
    }

    /// The key times for the eyelid animation, dense during both blinks and empty elsewhere.
    ///
    /// - Returns: Sorted fractions of ``blinkPeriod`` from zero to one.
    static func blinkKeyTimes() -> [Double] {
        var times = [0.0, 1.0]
        for start in [3.4, 3.86] {
            for step in 0...56 {
                times.append((start + Double(step) / 200) / blinkPeriod)
            }
        }
        return times.sorted()
    }

    /// The key times for the cross wobble, turn and hop, denser during the turn.
    ///
    /// - Returns: Sorted, unique fractions of ``spinPeriod`` from zero to one.
    static func spinKeyTimes() -> [Double] {
        var times = (0...204).map {
            Double($0) / 60 / spinPeriod
        }
        times += (0...240).map {
            (3.4 + Double($0) / 200) / spinPeriod
        }
        times.append(1)
        let cycle = times.filter {
            $0 <= 1
        }
        return Array(Set(cycle)).sorted()
    }
}
