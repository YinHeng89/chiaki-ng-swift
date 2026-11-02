import Foundation

/// Mixes console rumble with haptics converted to rumble and paces what is sent to the motors.
///
/// Console rumble expires after ``consoleHold`` without a refresh. Output is throttled to ``minimumInterval``,
/// re-sent every ``refreshInterval`` so the controller does not time out, and otherwise sent only when a motor
/// moves by at least ``step``.
public struct RumbleMix: Equatable, Sendable {
    /// What the motors were last told.
    public enum Output: Equatable, Sendable {
        /// Nothing is playing.
        case idle

        /// A level is playing, sent at the given time.
        case playing(RumbleLevel, sentAt: TimeInterval)
    }

    /// How long one rumble command lasts on the controller.
    public static let durationMilliseconds: UInt32 = 600

    /// How often a steady level is re-sent.
    public static let refreshInterval: TimeInterval = 0.4

    /// The shortest gap between two commands.
    public static let minimumInterval: TimeInterval = 0.03

    /// How long console rumble lasts without a refresh.
    public static let consoleHold: TimeInterval = 5

    /// The smallest motor change that is sent straight away.
    public static let step: UInt16 = 1024

    /// The console's last left motor value.
    public private(set) var consoleLeft: UInt8 = 0

    /// The console's last right motor value.
    public private(set) var consoleRight: UInt8 = 0

    /// When the console last set its motors.
    public private(set) var consoleAt: TimeInterval = 0

    /// The level converted from haptics.
    public private(set) var haptics = RumbleLevel.off

    /// What the motors were last told.
    public private(set) var output = Output.idle

    /// Creates a silent mix.
    public init() {
    }

    /// The console's rumble, or off once it has expired.
    ///
    /// - Parameters:
    ///   - now: The current time.
    ///   - strength: The user's rumble strength.
    /// - Returns: The console level.
    public func console(at now: TimeInterval, strength: Double) -> RumbleLevel {
        guard now >= consoleAt, now - consoleAt <= Self.consoleHold else {
            return .off
        }
        return RumbleLevel(left: consoleLeft, right: consoleRight, strength: strength)
    }

    /// The stronger of console rumble and haptics for each motor.
    ///
    /// - Parameters:
    ///   - now: The current time.
    ///   - strength: The user's rumble strength.
    /// - Returns: The level the motors should reach.
    public func target(at now: TimeInterval, strength: Double) -> RumbleLevel {
        console(at: now, strength: strength).merged(with: haptics)
    }

    /// Records a console rumble command.
    ///
    /// - Parameters:
    ///   - left: The left motor value.
    ///   - right: The right motor value.
    ///   - now: When it arrived.
    public mutating func setConsole(left: UInt8, right: UInt8, at now: TimeInterval) {
        consoleLeft = left
        consoleRight = right
        consoleAt = now
    }

    /// Records the level converted from haptics.
    ///
    /// - Parameter level: The level.
    public mutating func setHaptics(_ level: RumbleLevel) {
        haptics = level
    }

    /// Clears haptics and forgets what was sent.
    public mutating func silence() {
        haptics = .off
        output = .idle
    }

    /// The level to send now, if any.
    ///
    /// - Parameters:
    ///   - now: The current time.
    ///   - strength: The user's rumble strength.
    /// - Returns: The level to send, ``RumbleLevel/off`` to stop, or `nil` to send nothing.
    public mutating func next(at now: TimeInterval, strength: Double) -> RumbleLevel? {
        let target = target(at: now, strength: strength)
        switch output {
        case .idle:
            guard target != .off else {
                return nil
            }
            output = .playing(target, sentAt: now)
            return target
        case let .playing(sent, sentAt):
            let elapsed = now - sentAt
            if elapsed >= 0, elapsed < Self.minimumInterval {
                return nil
            }
            if target == .off {
                output = .idle
                return .off
            }
            guard elapsed < 0 || elapsed >= Self.refreshInterval || target.differs(from: sent, by: Self.step)
            else {
                return nil
            }
            output = .playing(target, sentAt: now)
            return target
        }
    }
}

/// The strength of a controller's low- and high-frequency rumble motors.
public struct RumbleLevel: Equatable, Sendable {
    /// Both motors off.
    public static let off = RumbleLevel(low: 0, high: 0)

    /// The low-frequency motor.
    public var low: UInt16

    /// The high-frequency motor.
    public var high: UInt16

    /// Creates a level from motor values.
    ///
    /// - Parameters:
    ///   - low: The low-frequency motor.
    ///   - high: The high-frequency motor.
    public init(low: UInt16, high: UInt16) {
        self.low = low
        self.high = high
    }

    /// Creates a level from the console's 8-bit motor values scaled by a strength.
    ///
    /// - Parameters:
    ///   - left: The console's left motor value.
    ///   - right: The console's right motor value.
    ///   - strength: The user's rumble strength, 0 to 1.
    public init(left: UInt8, right: UInt8, strength: Double) {
        let gain = strength.isFinite
            ? max(0, min(1, strength)) * 257
            : 0
        self.init(
            low: UInt16((Double(left) * gain).rounded()),
            high: UInt16((Double(right) * gain).rounded())
        )
    }

    /// Creates a level from haptic amplitudes, 0 to 1.
    ///
    /// - Parameters:
    ///   - hapticLow: The low-band amplitude.
    ///   - hapticHigh: The high-band amplitude.
    public init(hapticLow: Float, hapticHigh: Float) {
        self.init(low: Self.motor(hapticLow), high: Self.motor(hapticHigh))
    }

    /// Scales a 0 to 1 amplitude to the full motor range, treating non-finite or non-positive values as off
    /// and clamping above 1.
    ///
    /// - Parameter level: The amplitude.
    /// - Returns: The motor value.
    static func motor(_ level: Float) -> UInt16 {
        guard level.isFinite, level > 0 else {
            return 0
        }
        return UInt16((Double(min(1, level)) * Double(UInt16.max)).rounded())
    }

    /// Combines two levels by taking the stronger value for each motor.
    ///
    /// - Parameter other: The level to combine with.
    /// - Returns: The per-motor maximum of both levels.
    func merged(with other: RumbleLevel) -> RumbleLevel {
        RumbleLevel(low: max(low, other.low), high: max(high, other.high))
    }

    /// Reports whether either motor moved by at least a step from another level.
    ///
    /// - Parameters:
    ///   - other: The level to compare against.
    ///   - step: The smallest change that counts.
    /// - Returns: `true` when the low or high motor differs by `step` or more.
    func differs(from other: RumbleLevel, by step: UInt16) -> Bool {
        low.distance(to: other.low).magnitude >= UInt(step) || high.distance(to: other.high)
            .magnitude >= UInt(step)
    }
}
