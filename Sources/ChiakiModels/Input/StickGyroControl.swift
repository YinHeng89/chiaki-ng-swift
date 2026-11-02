import Foundation
import simd

/// The state machine deciding when the right stick steers the gyro instead of acting as a stick.
///
/// In ``StickGyroMode/whileHeld`` a short press of the hold control without moving the stick is passed on as a
/// tap; pressing and moving the stick past ``turnThreshold`` turns.
public struct StickGyroControl: Equatable, Sendable {
    /// Where the control is.
    public enum Phase: Equatable, Sendable {
        /// Stick gyro is off.
        case off

        /// Waiting for the hold control.
        case waiting

        /// The hold control is pressed but the stick has not moved enough.
        case pressed

        /// The stick steers the gyro.
        case turning

        /// A tap of the hold control is being passed on until the given microsecond time.
        case tapping(until: UInt64)
    }

    /// How long a passed-on tap lasts, in microseconds.
    public static let tapMicroseconds: UInt64 = 100_000

    /// The stick deflection that starts turning.
    public static let turnThreshold = 0.25

    /// The configured mode.
    public private(set) var mode: StickGyroMode

    /// The current phase.
    public private(set) var phase: Phase

    /// Creates a control at rest for a mode.
    ///
    /// - Parameter mode: The mode.
    public init(mode: StickGyroMode) {
        self.mode = mode
        phase = Self.resting(mode)
    }

    /// Switches mode, resetting the phase when it changes.
    ///
    /// - Parameter next: The new mode.
    public mutating func configure(_ next: StickGyroMode) {
        guard next != mode else {
            return
        }
        mode = next
        phase = Self.resting(next)
    }

    /// Records the hold control going down or up.
    ///
    /// - Parameters:
    ///   - down: Whether it was pressed.
    ///   - now: The time in microseconds.
    public mutating func hold(down: Bool, at now: UInt64) {
        guard mode == .whileHeld else {
            return
        }
        switch (phase, down) {
        case (.waiting, true), (.tapping, true):
            phase = .pressed
        case (.pressed, false):
            phase = .tapping(until: now + Self.tapMicroseconds)
        case (.turning, false):
            phase = .waiting
        default:
            break
        }
    }

    /// Records the stick's deflection, starting a turn once it passes the threshold while held.
    ///
    /// - Parameter magnitude: The deflection, 0 to 1.
    public mutating func stick(magnitude: Double) {
        if phase == .pressed, magnitude > Self.turnThreshold {
            phase = .turning
        }
    }

    /// Ends a passed-on tap once its time is up.
    ///
    /// - Parameter now: The time in microseconds.
    /// - Returns: `true` when a tap just ended.
    @discardableResult
    public mutating func tick(at now: UInt64) -> Bool {
        guard case let .tapping(until) = phase, now >= until else {
            return false
        }
        phase = .waiting
        return true
    }

    /// Returns to rest, for example when input focus is lost.
    public mutating func release() {
        phase = Self.resting(mode)
    }

    /// Whether the stick steers the gyro.
    public var turning: Bool {
        phase == .turning
    }

    /// Whether the right stick is withheld from the console.
    public var capturesRightStick: Bool {
        switch phase {
        case .pressed, .turning:
            true
        case .off, .waiting, .tapping:
            false
        }
    }

    /// Whether a tap is being passed on.
    public var tapping: Bool {
        if case .tapping = phase {
            return true
        }
        return false
    }

    private static func resting(_ mode: StickGyroMode) -> Phase {
        switch mode {
        case .off, .automatic:
            .off
        case .whileHeld:
            .waiting
        case .always:
            .turning
        }
    }
}

/// The constants and curve that turn right-stick deflection into gyro rates.
public enum StickGyro {
    /// The turn rate at full deflection, in radians per second.
    public static let fullTurnRate: Float = 4

    /// The furthest the view may tilt up or down.
    public static let pitchLimit = Float.pi * 80 / 180

    /// The response curve exponent.
    public static let response: Float = 1.8

    /// The world's up axis.
    public static let up = SIMD3<Float>(0, 1, 0)

    /// The angular rates for a stick position.
    ///
    /// - Parameters:
    ///   - x: The horizontal deflection.
    ///   - y: The vertical deflection.
    ///   - inverted: Whether vertical is inverted.
    /// - Returns: Pitch and yaw rates in radians per second.
    public static func rates(x: Int16, y: Int16, inverted: Bool) -> SIMD3<Float> {
        let horizontal = Float(x) / 32767
        let vertical = Float(inverted
            ? -Int(y)
            : Int(y)) / 32767
        let length = (horizontal * horizontal + vertical * vertical).squareRoot()
        guard length > 0 else {
            return SIMD3()
        }
        let scale = fullTurnRate * pow(min(1, length), response) / length
        return SIMD3(-vertical * scale, -horizontal * scale, 0)
    }
}

/// The virtual controller orientation that stick gyro integrates, and the motion samples it produces.
public struct StickGyroPose: Equatable, Sendable {
    /// One synthesised motion reading.
    public struct Sample: Equatable, Sendable {
        /// The angular velocity in controller axes.
        public let gyro: SIMD3<Float>

        /// The gravity direction in controller axes.
        public let gravity: SIMD3<Float>
    }

    /// The current orientation.
    public private(set) var orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    private var last: UInt64?

    /// Creates a level, centred pose.
    public init() {
    }

    /// Gravity in controller axes.
    public var gravity: SIMD3<Float> {
        orientation.inverse.act(StickGyro.up)
    }

    /// The tilt up or down, in radians.
    public var pitch: Float {
        asin(max(-1, min(1, -gravity.z)))
    }

    /// Integrates stick rates since the last turn.
    ///
    /// - Parameters:
    ///   - stick: The rates from ``StickGyro/rates(x:y:inverted:)``.
    ///   - now: The time in microseconds.
    /// - Returns: The motion reading to send.
    public mutating func turn(_ stick: SIMD3<Float>, at now: UInt64) -> Sample {
        let allowed = limited(stick)
        defer {
            last = now
        }
        if let last, now > last {
            let seconds = min(Float(now - last) / 1_000_000, 0.1)
            let yaw = simd_quatf(angle: allowed.y * seconds, axis: StickGyro.up)
            let tilt = simd_quatf(angle: allowed.x * seconds, axis: SIMD3(1, 0, 0))
            orientation = simd_normalize(yaw * orientation * tilt)
        }
        let gyro = SIMD3(allowed.x, 0, 0) + orientation.inverse.act(SIMD3(0, allowed.y, 0))
        return Sample(gyro: gyro, gravity: gravity)
    }

    /// The rates with tilting stopped at ``StickGyro/pitchLimit``.
    ///
    /// - Parameter rates: The requested rates.
    /// - Returns: The rates allowed from the current pitch.
    public func limited(_ rates: SIMD3<Float>) -> SIMD3<Float> {
        let current = pitch
        guard (current >= StickGyro.pitchLimit && rates.x > 0) ||
            (current <= -StickGyro.pitchLimit && rates.x < 0)
        else {
            return rates
        }
        return SIMD3(0, rates.y, rates.z)
    }

    /// Forgets the last time, so the next turn does not integrate a gap.
    public mutating func pause() {
        last = nil
    }

    /// Returns to the level, centred pose.
    public mutating func recentre() {
        self = StickGyroPose()
    }
}

/// The saved choice for steering the console's gyro with the right stick.
public enum StickGyroMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Off for controllers with sensors, while held otherwise.
    case automatic

    /// Never.
    case off

    /// While the gyro hold control is pressed and the stick moves.
    case whileHeld

    /// Always.
    case always

    /// The mode in force for a controller.
    ///
    /// - Parameter sensors: Whether the controller has motion sensors.
    /// - Returns: The mode, with ``automatic`` resolved.
    public func resolved(sensors: Bool) -> StickGyroMode {
        guard self == .automatic else {
            return self
        }
        return sensors
            ? .off
            : .whileHeld
    }
}
