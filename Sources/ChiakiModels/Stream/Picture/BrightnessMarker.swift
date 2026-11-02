/// Where the HDR heatmap's brightness marker points, as a fraction of the picture from its top-left corner.
///
/// The D-pad and arrow keys nudge it by ``nudgeStep``; the left stick glides it at up to ``glideSpeed`` of the
/// picture a second, with a gentle curve past ``stickDeadZone``. It never leaves the picture.
public struct BrightnessMarker: Equatable, Sendable {
    /// A one-step move of the marker.
    public enum Nudge: Equatable, Sendable {
        /// Towards the left edge.
        case left

        /// Towards the right edge.
        case right

        /// Towards the top edge.
        case up

        /// Towards the bottom edge.
        case down
    }

    /// How far one nudge moves the marker, as a fraction of the picture.
    public static let nudgeStep = 0.01

    /// The fastest the stick glides the marker, in pictures a second.
    public static let glideSpeed = 0.6

    /// The stick deflection, from 0 to 1, below which the stick does not move the marker.
    public static let stickDeadZone = 0.2

    /// The centre of the picture.
    public static let centre = BrightnessMarker(x: 0.5, y: 0.5)

    /// The horizontal position, from 0 at the left edge to 1 at the right.
    public let x: Double

    /// The vertical position, from 0 at the top edge to 1 at the bottom.
    public let y: Double

    /// Places the marker, keeping it on the picture.
    ///
    /// - Parameters:
    ///   - x: The horizontal position.
    ///   - y: The vertical position.
    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// Whether a stick deflection is past the dead zone, so the stick glides the marker and direction commands
    /// from it are ignored.
    ///
    /// - Parameters:
    ///   - dx: The horizontal deflection, from -1 to 1.
    ///   - dy: The vertical deflection, from -1 to 1.
    /// - Returns: `true` past the dead zone.
    public static func stickDeflected(dx: Double, dy: Double) -> Bool {
        (dx * dx + dy * dy).squareRoot() > stickDeadZone
    }

    /// The marker moved one step.
    ///
    /// - Parameter nudge: The direction.
    /// - Returns: The moved marker.
    public func nudged(_ nudge: Nudge) -> BrightnessMarker {
        switch nudge {
        case .left:
            BrightnessMarker(x: x - Self.nudgeStep, y: y)
        case .right:
            BrightnessMarker(x: x + Self.nudgeStep, y: y)
        case .up:
            BrightnessMarker(x: x, y: y - Self.nudgeStep)
        case .down:
            BrightnessMarker(x: x, y: y + Self.nudgeStep)
        }
    }

    /// The marker after the stick has been held for a while.
    ///
    /// - Parameters:
    ///   - dx: The horizontal deflection, from -1 to 1.
    ///   - dy: The vertical deflection, from -1 to 1.
    ///   - seconds: How long the stick was held.
    /// - Returns: The moved marker, or the same marker inside the dead zone.
    public func glided(dx: Double, dy: Double, seconds: Double) -> BrightnessMarker {
        let magnitude = min((dx * dx + dy * dy).squareRoot(), 1)
        guard magnitude > Self.stickDeadZone, seconds > 0 else {
            return self
        }
        let reach = (magnitude - Self.stickDeadZone) / (1 - Self.stickDeadZone)
        let speed = Self.glideSpeed * reach * reach / magnitude * seconds
        return BrightnessMarker(x: x + dx * speed, y: y + dy * speed)
    }
}
