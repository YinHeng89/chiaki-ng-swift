import CoreGraphics
import Foundation

/// One of the logo symbols drifting across ``AmbientBackground``.
///
/// Each motif enters at its own point on the window edge and travels in a straight line toward
/// the centre over ``period`` seconds, growing and fading in and out on the way, while slowly
/// rocking. The position and size change linearly with progress, so two key frames reproduce the
/// whole journey.
struct AmbientMotif {
    /// Where and how one motif is drawn at a moment in its journey.
    struct Frame: Equatable {
        /// The centre of the symbol in the background's coordinates.
        let center: CGPoint

        /// The width of the symbol in points.
        let side: CGFloat

        /// The rotation of the symbol in radians.
        let rotation: Double

        /// The opacity of the symbol.
        let opacity: Double
    }

    /// The time in seconds one motif takes to travel from the edge to the centre.
    static let period = 28.0

    /// The time in seconds after which every motif's rocking repeats.
    static let rotationPeriod = 2 * Double.pi / 0.08

    /// The number of motifs in the background.
    static let count = 28

    /// The lime used to tint every symbol except the circle, as sRGB components.
    static let lime = (red: 0.80, green: 0.87, blue: 0.10)

    /// The blue used to tint the circle symbol, as sRGB components.
    static let blue = (red: 0.16, green: 0.35, blue: 0.48)

    /// The four symbols cut from the logo artwork, in source pixels, indexed by ``kind``.
    static let regions = [
        CGRect(x: 507, y: 139, width: 545, height: 545),
        CGRect(x: 1628, y: 203, width: 416, height: 416),
        CGRect(x: 30, y: 228, width: 473, height: 420),
        CGRect(x: 1090, y: 176, width: 472, height: 470)
    ]

    /// The width-to-height ratio of each symbol in ``regions``.
    static let aspects: [CGFloat] = [1, 1, 473.0 / 420.0, 472.0 / 470.0]

    /// Every motif, ordered from the farthest to the nearest so nearer ones draw on top.
    static let all: [AmbientMotif] = (0..<count).map { index in
        AmbientMotif(
            slot: index,
            depth: 0.25 + Double((index * 5) % 7) / 12,
            phase: Double((index * 11) % 28) / 28,
            kind: index % 4
        )
    }.sorted {
        $0.depth < $1.depth
    }

    /// The motif's evenly spaced entry point around the window edge, clockwise from the top left.
    let slot: Int

    /// How near the motif appears, from 0.25 to 0.75; nearer motifs are larger and more opaque.
    let depth: Double

    /// The fraction of ``period`` the motif has already travelled at time zero.
    let phase: Double

    /// The symbol drawn, as an index into ``regions``; kind zero is the circle.
    let kind: Int

    /// The motif's progress along its journey.
    ///
    /// - Parameter time: The time since the animation started, in seconds.
    /// - Returns: The progress from zero at the edge to one at the end of the journey.
    func progress(at time: Double) -> Double {
        (time / Self.period + phase).truncatingRemainder(dividingBy: 1)
    }

    /// The motif's rocking angle.
    ///
    /// - Parameter time: The time since the animation started, in seconds.
    /// - Returns: A rotation in radians around a fixed tilt that depends on ``phase``.
    func rotation(at time: Double) -> Double {
        sin(phase * 2 * .pi) * 0.12 + sin(time * 0.08 + phase * 2 * .pi) * 0.06
    }

    /// Where the motif is drawn at a moment in time.
    ///
    /// - Parameters:
    ///   - time: The time since the animation started, in seconds.
    ///   - size: The size of the background.
    ///   - quiet: Whether symbols away from the edges are faded out.
    ///   - dark: Whether the background uses its dark appearance.
    /// - Returns: The motif's frame at that time.
    func frame(time: Double, size: CGSize, quiet: Bool, dark: Bool) -> Frame {
        frame(
            progress: progress(at: time),
            rotation: rotation(at: time),
            size: size,
            quiet: quiet,
            dark: dark
        )
    }

    /// Where the motif is drawn at a point in its journey.
    ///
    /// - Parameters:
    ///   - progress: The progress from zero at the edge to one at the end of the journey.
    ///   - rotation: The rotation to report, in radians.
    ///   - size: The size of the background.
    ///   - quiet: Whether symbols away from the edges are faded out.
    ///   - dark: Whether the background uses its dark appearance.
    /// - Returns: The motif's frame, travelling from just beyond its entry point on the edge to
    ///   42 percent of the way out from the centre, fading in over the first 12 percent of the
    ///   journey and out over the last 18 percent.
    func frame(progress: Double, rotation: Double, size: CGSize, quiet: Bool, dark: Bool) -> Frame {
        let unit = min(size.width, size.height)
        let radial = 1.08 - progress * 0.66
        let side = unit * (0.034 + depth * 0.09) * (0.72 + progress * 0.60)
        let entry = entryPoint(size: size)
        let horizontal = size.width * 0.5 + (entry.x - size.width * 0.5) * radial
        let vertical = size.height * 0.5 + (entry.y - size.height * 0.5) * radial
        let edgeDistance = max(
            abs(horizontal / size.width - 0.5) * 2,
            abs(vertical / size.height - 0.5) * 2
        )
        let edgeVisibility =
            quiet
                ? max(0, min(1, (edgeDistance - 0.70) / 0.22)) * 0.35
                : 1
        let fade = min(1, progress / 0.12) * min(1, (1 - progress) / 0.18)
        let opacity =
            ((dark
                    ? 0.075
                    : 0.065) + depth
                * (dark
                    ? 0.13
                    : 0.10))
                * fade * edgeVisibility
        return Frame(
            center: CGPoint(x: horizontal, y: vertical),
            side: side,
            rotation: rotation,
            opacity: opacity
        )
    }

    private func entryPoint(size: CGSize) -> CGPoint {
        let distance = (Double(slot) + 0.5) / Double(Self.count) * 2 * (size.width + size.height)
        if distance < size.width {
            return CGPoint(x: distance, y: 0)
        }
        if distance < size.width + size.height {
            return CGPoint(x: size.width, y: distance - size.width)
        }
        if distance < 2 * size.width + size.height {
            return CGPoint(x: 2 * size.width + size.height - distance, y: size.height)
        }
        return CGPoint(x: 0, y: 2 * (size.width + size.height) - distance)
    }
}
