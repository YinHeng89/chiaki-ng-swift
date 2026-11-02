import Foundation

/// Turns trackpad swipes and wheel notches into page turns: one turn per swipe, and wheel turns spaced out.
public struct CloudPageSwipe: Equatable, Sendable {
    /// A scroll sample.
    public enum Sample: Equatable, Sendable {
        /// A trackpad swipe began.
        case began
        /// The swipe moved by this amount.
        case moved(Double)
        /// The swipe ended.
        case ended
        /// Momentum after the swipe.
        case momentum
        /// A wheel notch of this amount.
        case wheel(Double)
    }

    /// How far a swipe travels before it turns the page.
    public static let travel = 36.0
    /// The smallest wheel movement that turns the page.
    public static let wheelNotch = 0.01
    /// How long a wheel turn blocks the next one, in seconds.
    public static let wheelLock = 0.65

    private var travelled = 0.0
    private var turned = false
    private var lockedUntil = 0.0

    /// Creates a recogniser with no swipe under way.
    public init() {
    }

    /// Reads one sample.
    ///
    /// - Parameters:
    ///   - sample: The scroll sample.
    ///   - time: When it arrived, in seconds.
    /// - Returns: `1` to turn forward, `-1` to turn back, or `nil` for no turn.
    public mutating func turn(for sample: Sample, at time: TimeInterval) -> Int? {
        switch sample {
        case .began:
            travelled = 0
            turned = false
        case .ended:
            travelled = 0
        case .momentum:
            break
        case .moved(let amount):
            guard !turned else {
                return nil
            }
            travelled += amount
            guard abs(travelled) >= Self.travel else {
                return nil
            }
            turned = true
            return direction(travelled)
        case .wheel(let amount):
            guard abs(amount) >= Self.wheelNotch, time >= lockedUntil else {
                return nil
            }
            lockedUntil = time + Self.wheelLock
            return direction(amount)
        }
        return nil
    }

    private func direction(_ amount: Double) -> Int {
        amount > 0
            ? 1
            : -1
    }
}
