import CoreGraphics

/// The pure geometry both navigators use to choose the next focus stop from control frames.
///
/// A navigator collects the frames of the focusable controls in a window and asks this type which one lies
/// in a direction, which comes next in reading order, or which is nearest to a point. AppKit window
/// coordinates grow upwards and UIKit coordinates grow downwards; ``Orientation`` hides the difference.
public struct FocusGeometry: Sendable {
    /// Which way the vertical axis of the frames grows.
    public enum Orientation: Sendable {
        /// The y axis grows upwards, as in AppKit window coordinates.
        case yUp
        /// The y axis grows downwards, as in UIKit and SwiftUI global coordinates.
        case yDown
    }

    /// The smallest height a control may have and still be a focus stop.
    public static let minimumStopHeight: CGFloat = 14

    /// The height from which a frame is a container rather than a control.
    public static let maximumStopHeight: CGFloat = 200

    /// The distance kept between a revealed control and the edge of its scroll view.
    public static let revealMargin: CGFloat = 28

    /// How far a frame must clear the origin vertically to count as above or below it.
    public static let verticalClearance: CGFloat = 2

    /// The axis orientation of the frames this geometry compares.
    public let orientation: Orientation

    /// Creates a geometry for one axis orientation.
    ///
    /// - Parameter orientation: Which way the frames' y axis grows.
    public init(orientation: Orientation) {
        self.orientation = orientation
    }

    /// Geometry for AppKit window coordinates.
    public static let appKit = FocusGeometry(orientation: .yUp)

    /// Geometry for UIKit and SwiftUI global coordinates.
    public static let touch = FocusGeometry(orientation: .yDown)

    /// Whether two frames belong to the same control, as when a control and its focus proxy overlap.
    ///
    /// - Parameters:
    ///   - first: One frame.
    ///   - second: The other frame.
    /// - Returns: `true` when the centres and sizes match within a few points.
    public static func isSameControl(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.midX - second.midX) <= 2
            && abs(first.midY - second.midY) <= 2
            && abs(first.width - second.width) <= 6
            && abs(first.height - second.height) <= 6
    }

    /// Whether a frame is the size of a control that can be a focus stop.
    ///
    /// - Parameter frame: A control's frame.
    /// - Returns: `true` for a non-empty frame between ``minimumStopHeight`` and ``maximumStopHeight``.
    public static func isStopSized(_ frame: CGRect) -> Bool {
        frame.height >= minimumStopHeight && frame.height < maximumStopHeight && frame.width > 0
    }

    /// Whether one frame comes before another in reading order: top to bottom, then leading to trailing.
    ///
    /// - Parameters:
    ///   - first: One frame.
    ///   - second: The other frame.
    /// - Returns: `true` when `first` is read before `second`.
    public func precedes(_ first: CGRect, _ second: CGRect) -> Bool {
        if abs(first.midY - second.midY) > 4 {
            switch orientation {
            case .yUp:
                return first.midY > second.midY
            case .yDown:
                return first.midY < second.midY
            }
        }
        return first.midX < second.midX
    }

    /// Whether a frame's centre lies below a vertical limit.
    ///
    /// - Parameters:
    ///   - frame: A control's frame.
    ///   - limit: A y position in the same coordinates.
    /// - Returns: `true` when the frame's centre is at or below `limit`.
    public func isBelow(_ frame: CGRect, limit: CGFloat) -> Bool {
        switch orientation {
        case .yUp:
            frame.midY <= limit
        case .yDown:
            frame.midY >= limit
        }
    }

    /// Whether a frame lies beyond the origin in a direction.
    ///
    /// - Parameters:
    ///   - frame: A candidate frame.
    ///   - origin: The focused control's frame.
    ///   - direction: The direction pressed.
    /// - Returns: `true` when the candidate clears the origin on that side.
    public func lies(_ frame: CGRect, beyond origin: CGRect, toward direction: MenuMoveDirection) -> Bool {
        switch (direction, orientation) {
        case (.up, .yUp), (.down, .yDown):
            frame.minY >= origin.maxY + Self.verticalClearance
        case (.down, .yUp), (.up, .yDown):
            frame.maxY <= origin.minY - Self.verticalClearance
        case (.left, _):
            frame.midX < origin.minX
        case (.right, _):
            frame.midX > origin.maxX
        }
    }

    /// Whether a frame overlaps the origin across the axis of movement, so it is in line with it.
    ///
    /// - Parameters:
    ///   - frame: A candidate frame.
    ///   - origin: The focused control's frame.
    ///   - direction: The direction pressed.
    /// - Returns: `true` when the two frames share a column for vertical moves or a row for horizontal ones.
    public static func isAligned(_ frame: CGRect, with origin: CGRect,
                                 toward direction: MenuMoveDirection) -> Bool {
        if direction.isVertical {
            return min(frame.maxX, origin.maxX) - max(frame.minX, origin.minX) > 0
        }
        return min(frame.maxY, origin.maxY) - max(frame.minY, origin.minY) > 0
    }

    /// How far a candidate is from the origin for a move; lower is closer.
    ///
    /// - Parameters:
    ///   - frame: A candidate frame.
    ///   - origin: The focused control's frame.
    ///   - direction: The direction pressed.
    ///   - horizontalWeight: How much sideways distance counts against a vertical move.
    /// - Returns: The weighted distance between centres.
    public static func score(
        _ frame: CGRect,
        from origin: CGRect,
        toward direction: MenuMoveDirection,
        horizontalWeight: CGFloat
    ) -> CGFloat {
        if direction.isVertical {
            return abs(frame.midY - origin.midY) + horizontalWeight * abs(frame.midX - origin.midX)
        }
        return abs(frame.midX - origin.midX) + 0.25 * abs(frame.midY - origin.midY)
    }

    /// Chooses the frame focus should move to.
    ///
    /// Only frames beyond the origin in the direction count. Of those, frames in line with the origin win;
    /// with `allowUnaligned` a vertical move may also reach frames that are not in line. The closest by
    /// ``score(_:from:toward:horizontalWeight:)`` is chosen.
    ///
    /// - Parameters:
    ///   - direction: The direction pressed.
    ///   - origin: The focused control's frame.
    ///   - frames: The candidate frames, already filtered to focus stops other than the origin.
    ///   - allowUnaligned: Whether a vertical move may reach frames out of line with the origin.
    ///   - horizontalWeight: How much sideways distance counts against a vertical move.
    /// - Returns: The index in `frames` of the chosen frame, or `nil` when no frame lies that way.
    public func target(
        toward direction: MenuMoveDirection,
        from origin: CGRect,
        among frames: [CGRect],
        allowUnaligned: Bool = false,
        horizontalWeight: CGFloat = 0.1
    ) -> Int? {
        let ahead = frames.indices.filter { index in
            lies(frames[index], beyond: origin, toward: direction)
        }
        let eligible = allowUnaligned && direction.isVertical
            ? ahead
            : ahead.filter { index in
                Self.isAligned(frames[index], with: origin, toward: direction)
            }
        return eligible.min { first, second in
            Self.score(frames[first], from: origin, toward: direction, horizontalWeight: horizontalWeight)
                < Self.score(
                    frames[second],
                    from: origin,
                    toward: direction,
                    horizontalWeight: horizontalWeight
                )
        }
    }

    /// Chooses the frame whose centre is nearest to a target rectangle's centre.
    ///
    /// - Parameters:
    ///   - target: The rectangle focus should land near, such as a control that disappeared.
    ///   - frames: The candidate frames.
    /// - Returns: The index in `frames` of the nearest frame, or `nil` when `frames` is empty.
    public static func nearest(to target: CGRect, among frames: [CGRect]) -> Int? {
        frames.indices.min { first, second in
            hypot(frames[first].midX - target.midX, frames[first].midY - target.midY)
                < hypot(frames[second].midX - target.midX, frames[second].midY - target.midY)
        }
    }

    /// Orders frames for a sequential move and picks the one after the origin.
    ///
    /// - Parameters:
    ///   - origin: The focused control's frame, or `nil` when nothing is focused.
    ///   - frames: The candidate frames, excluding the origin.
    ///   - backward: Whether to move backwards in reading order.
    /// - Returns: The index in `frames` to focus: the next one after the origin, wrapping to the first, or
    ///   the first one when nothing is focused.
    public func sequentialTarget(after origin: CGRect?, among frames: [CGRect], backward: Bool) -> Int? {
        let sorted = frames.indices.sorted { first, second in
            precedes(frames[first], frames[second])
        }
        let ordered = backward
            ? Array(sorted.reversed())
            : sorted
        guard let origin else {
            return ordered.first
        }
        let following = ordered.filter { index in
            backward
                ? precedes(frames[index], origin)
                : precedes(origin, frames[index])
        }
        return (following + ordered).first
    }
}
