import Foundation

/// Tracks a single controller button press while the user is binding a button, deciding on release whether it
/// assigns that button or cancels the capture.
public struct ControllerButtonCaptureState {
    /// How a button capture ends.
    public enum Outcome: Equatable {
        /// The pressed button was released quickly and should be assigned; carries its button code.
        case assign(Int)
        /// The button was held for at least `holdToCancel` seconds, so the capture is abandoned.
        case cancel
    }

    /// How long, in seconds, a button must be held before releasing it cancels the capture instead of
    /// assigning it.
    public static let holdToCancel: TimeInterval = 1
    private var pressed: (code: Int, since: TimeInterval)?

    /// Creates a controller button capture state.
    public init() {
    }

    /// Whether the capture has already produced an outcome; once set, further input is ignored.
    public private(set) var finished = false

    /// Feeds a button press or release into the capture.
    ///
    /// Only the first button pressed is tracked. Releasing it finishes the capture with an assignment, or
    /// with a cancellation if it was held for `holdToCancel` or longer.
    /// - Parameters:
    ///   - code: The controller button code.
    ///   - down: Whether the button went down rather than up.
    ///   - now: The current time in seconds, used to measure how long the button was held.
    /// - Returns: Whether the event was consumed by the capture, and the outcome when the capture finished.
    public mutating func button(_ code: Int, down: Bool,
                                now: TimeInterval) -> (consumed: Bool, outcome: Outcome?) {
        guard !finished else {
            return (false, nil)
        }
        if down {
            guard pressed == nil else {
                return (true, nil)
            }
            pressed = (code, now)
            return (true, nil)
        }
        guard let pressed, pressed.code == code else {
            return (false, nil)
        }
        finished = true
        self.pressed = nil
        return (true, now - pressed.since < Self.holdToCancel
            ? .assign(code)
            : .cancel)
    }

    /// Cancels the capture once the tracked button has been held for `holdToCancel` without being released.
    /// - Parameter now: The current time in seconds.
    /// - Returns: `.cancel` when the hold threshold has been reached, otherwise `nil`.
    public mutating func expire(now: TimeInterval) -> Outcome? {
        guard !finished, let pressed, now - pressed.since >= Self.holdToCancel else {
            return nil
        }
        finished = true
        self.pressed = nil
        return .cancel
    }
}
