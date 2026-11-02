import Foundation

/// Reads presses of a controller's Create button as the gestures PS5 cloud takes: a single tap, a double tap or a
/// long press.
///
/// ```
/// idle --down--> pressed --up--> released --down--> finished (double tap) --up--> idle
/// pressed --held long--> finished (long press)
/// released --no second tap in time--> idle (single tap)
/// ```
public struct CreateButtonGesture: Equatable, Sendable {
    /// What the Create button was pressed as.
    public enum Press: Equatable, Sendable {
        /// One short press.
        case singleTap

        /// Two short presses in quick succession.
        case doubleTap

        /// A press held down.
        case longPress
    }

    /// Where the gesture is.
    public enum State: Equatable, Sendable {
        /// The button is up and no press is pending.
        case idle

        /// The button went down at this time.
        case pressed(since: TimeInterval)

        /// The button came up at this time after a short press, waiting for a second tap.
        case released(time: TimeInterval)

        /// The gesture was reported and waits for the button to come up.
        case finished
    }

    /// The controller button code of the Create button.
    public static let button = 4

    /// How long the button is held before it counts as a long press, in seconds.
    public static let longPressSeconds = 0.5

    /// How soon a second tap must follow the first to count as a double tap, in seconds.
    public static let doubleTapSeconds = 0.3

    /// Where the gesture is.
    public private(set) var state = State.idle

    /// Creates an idle gesture.
    public init() {}

    /// Records the button going down or up.
    ///
    /// - Parameters:
    ///   - down: Whether the button went down.
    ///   - now: The time, in seconds.
    /// - Returns: A double tap at the second press, otherwise `nil`.
    public mutating func button(down: Bool, now: TimeInterval) -> Press? {
        switch (state, down) {
        case (.idle, true):
            state = .pressed(since: now)
            return nil
        case (.pressed, false):
            state = .released(time: now)
            return nil
        case (.released, true):
            state = .finished
            return .doubleTap
        case (.finished, false):
            state = .idle
            return nil
        default:
            return nil
        }
    }

    /// Reports a press whose time ran out.
    ///
    /// - Parameter now: The time, in seconds.
    /// - Returns: A long press once the button was held long enough, a single tap once no second tap came,
    ///   otherwise `nil`.
    public mutating func expire(now: TimeInterval) -> Press? {
        switch state {
        case let .pressed(since) where now - since >= Self.longPressSeconds:
            state = .finished
            return .longPress
        case let .released(time) where now - time >= Self.doubleTapSeconds:
            state = .idle
            return .singleTap
        default:
            return nil
        }
    }

    /// Forgets any press in progress.
    public mutating func reset() {
        state = .idle
    }
}
