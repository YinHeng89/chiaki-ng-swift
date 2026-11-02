import Foundation

/// Speeds up page turns while a direction is held on the page bar.
public struct CloudPageHold: Equatable, Sendable {
    /// The longest pause between presses that keeps a streak going, in seconds.
    public static let gap = 0.35

    private var forward = true
    private var last = -Double.infinity
    private var streak = 0

    /// Creates a hold with no streak.
    public init() {
    }

    /// Reads one press.
    ///
    /// - Parameters:
    ///   - wanted: Whether the press turns forward.
    ///   - time: When it happened, in seconds.
    /// - Returns: How many pages the press turns: 1, then 2, 5 and 10 as the streak grows.
    public mutating func step(forward wanted: Bool, at time: TimeInterval) -> Int {
        streak = wanted == forward && time - last <= Self.gap
            ? streak + 1
            : 0
        forward = wanted
        last = time
        switch streak {
        case ..<4:
            return 1
        case ..<10:
            return 2
        case ..<20:
            return 5
        default:
            return 10
        }
    }
}
