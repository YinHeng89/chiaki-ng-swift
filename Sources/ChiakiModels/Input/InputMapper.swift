import Foundation

/// Turns key and button presses into a console ``ControllerState`` through an ``InputPreset``.
///
/// A release only clears what its own press set, so two sources bound to one control release it only when both
/// are up. Stick directions remember when they were pressed so ``state(at:ramp:)`` can ramp them.
public struct InputMapper: Sendable {
    private static let stickDirections: Set<PlayStationControl> = [
        .leftStickLeft, .leftStickRight, .leftStickUp, .leftStickDown,
        .rightStickLeft, .rightStickRight, .rightStickUp, .rightStickDown
    ]

    private var held: [String: PlayStationControl] = [:]
    private var pressedAt: [PlayStationControl: TimeInterval] = [:]

    /// The touchpad the touchpad bindings press on.
    public var touchSurface: TouchpadSurface

    /// Creates a mapper with nothing held.
    ///
    /// - Parameter touchSurface: The touchpad for touchpad bindings.
    public init(touchSurface: TouchpadSurface = .ps5) {
        self.touchSurface = touchSurface
    }

    /// Records a press or release.
    ///
    /// - Parameters:
    ///   - source: The kind of input.
    ///   - code: The key or button code.
    ///   - down: Whether it was pressed.
    ///   - preset: The bindings in force.
    ///   - time: When it happened, for stick ramping.
    public mutating func press(source: InputSource, code: Int, down: Bool, preset: InputPreset,
                               at time: TimeInterval = 0) {
        let key = "\(source.rawValue):\(code)"
        if !down {
            guard let target = held.removeValue(forKey: key) else {
                return
            }
            if !held.values.contains(target) {
                pressedAt.removeValue(forKey: target)
            }
        } else if let binding = preset.bindings.first(where: { $0.source == source && $0.code == code }) {
            if Self.stickDirections.contains(binding.target), pressedAt[binding.target] == nil {
                pressedAt[binding.target] = time
            }
            held[key] = binding.target
        }
    }

    /// Releases everything.
    public mutating func reset() {
        held.removeAll(keepingCapacity: true)
        pressedAt.removeAll(keepingCapacity: true)
    }

    /// The state with stick directions ramped by how long each has been held.
    ///
    /// - Parameters:
    ///   - time: The current time.
    ///   - ramp: How directions ramp to full deflection.
    /// - Returns: The console state.
    public func state(at time: TimeInterval, ramp: StickRamp) -> ControllerState {
        var result = state
        func magnitude(_ direction: PlayStationControl) -> Double {
            pressedAt[direction].map { ramp.magnitude(after: time - $0) } ?? 0
        }
        func stick(_ left: PlayStationControl, _ right: PlayStationControl, _ up: PlayStationControl,
                   _ down: PlayStationControl) -> (Int16, Int16) {
            var x = magnitude(right) - magnitude(left)
            var y = magnitude(down) - magnitude(up)
            let length = (x * x + y * y).squareRoot()
            if length > 1 {
                x /= length
                y /= length
            }
            return (Int16((x * 32767).rounded()), Int16((y * 32767).rounded()))
        }
        (result.leftX, result.leftY) = stick(.leftStickLeft, .leftStickRight, .leftStickUp, .leftStickDown)
        (result.rightX, result.rightY) = stick(
            .rightStickLeft,
            .rightStickRight,
            .rightStickUp,
            .rightStickDown
        )
        return result
    }

    /// The state with every held stick direction at full deflection.
    public var state: ControllerState {
        var result = ControllerState()
        let targets = Set(held.values)
        for target in targets {
            result.buttons |= target.bit ?? 0
        }
        result.leftTrigger = targets.contains(.leftTrigger)
            ? 255
            : 0
        result.rightTrigger = targets.contains(.rightTrigger)
            ? 255
            : 0
        func axis(_ negative: PlayStationControl, _ positive: PlayStationControl) -> Int16 {
            Int16((targets.contains(positive)
                    ? 32767
                    : 0) - (targets.contains(negative)
                ? 32767
                : 0))
        }
        result.leftX = axis(.leftStickLeft, .leftStickRight)
        result.leftY = axis(.leftStickUp, .leftStickDown)
        result.rightX = axis(.rightStickLeft, .rightStickRight)
        result.rightY = axis(.rightStickUp, .rightStickDown)
        let presses = [PlayStationControl.touchpadLeft, .touchpadRight].compactMap { target in
            targets.contains(target)
                ? target.touchpadRegion.map(touchSurface.press)
                : nil
        }
        if !presses.isEmpty {
            result.buttons |= PlayStationControl.touchpad.bit ?? 0
            result.touches = ControllerTouchSlots(first: presses.first, second: presses.dropFirst().first)
        }
        return result
    }

    /// Applies a dead zone and optional inversion to a raw axis value.
    ///
    /// - Parameters:
    ///   - value: The raw value, nominally -32767 to 32767.
    ///   - deadZone: The fraction of travel ignored around centre, 0 up to but not including 1.
    ///   - inverted: Whether to flip the axis.
    /// - Returns: The rescaled value, 0 inside the dead zone or for an invalid dead zone.
    public static func calibrated(_ value: Int, deadZone: Double, inverted: Bool = false) -> Int16 {
        guard deadZone.isFinite, (0..<1).contains(deadZone) else {
            return 0
        }
        let normalized = max(-1, min(1, Double(value) / 32767))
        guard abs(normalized) > deadZone else {
            return 0
        }
        let magnitude = (abs(normalized) - deadZone) / (1 - deadZone)
        let direction = (normalized < 0
            ? -1.0
            : 1.0) * (inverted
            ? -1
            : 1)
        return Int16(max(-32767, min(32767, magnitude * direction * 32767)))
    }
}

/// How a digital stick direction, such as a held key, ramps up to full deflection.
public struct StickRamp: Equatable, Sendable {
    /// The ramp used for keyboard stick bindings.
    public static let keyboard = StickRamp(initial: 0.35, duration: 0.25)

    /// The deflection when the direction is first pressed, 0 to 1.
    public var initial: Double

    /// The time to reach full deflection.
    public var duration: TimeInterval

    /// Creates a ramp.
    ///
    /// - Parameters:
    ///   - initial: The starting deflection.
    ///   - duration: The time to full deflection.
    public init(initial: Double, duration: TimeInterval) {
        self.initial = initial
        self.duration = duration
    }

    /// The deflection after a direction has been held for `elapsed`.
    ///
    /// - Parameter elapsed: How long the direction has been held.
    /// - Returns: The deflection, 0 to 1.
    public func magnitude(after elapsed: TimeInterval) -> Double {
        guard duration > 0, elapsed.isFinite else {
            return 1
        }
        return min(1, initial + (1 - initial) * max(0, elapsed) / duration)
    }
}
