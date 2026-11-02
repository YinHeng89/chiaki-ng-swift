import ChiakiModels
import Dependencies
import Observation
import SwiftUI

/// Carries what the stream's input reads from the on-screen gamepad without reaching into the store: the pad
/// state ``VirtualGamepadFeature`` last published, and the virtual touchpad the stream's input lent the
/// gamepad's views.
///
/// The input layer takes the pad once per frame on the main actor through ``take()``, so no frame waits on the
/// store. Every press published since the previous take is latched into that read, so a tap that comes and goes
/// between two frames is still sent to the console, and each button or trigger press stays in the reads for at
/// least ``minimumHold`` so the console samples it the way it would a finger on a real button. The touchpad is
/// held weakly; the stream's input owns it.
@MainActor @Observable public final class VirtualGamepadLink {
    /// The link the views see when the app has not supplied one, such as in a preview.
    public nonisolated static let unsupplied = VirtualGamepadLink()

    /// The least time a press stays in the reads, however quickly it was released.
    public static let minimumHold: Duration = .milliseconds(60)

    /// The held buttons and stick positions the reducer last published.
    @ObservationIgnored public private(set) var pad = ControllerState()

    @ObservationIgnored private var latched = ControllerState()
    @ObservationIgnored private var sent = ControllerState()
    @ObservationIgnored private var buttonsPressedAt: [UInt32: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var leftTriggerPressedAt: ContinuousClock.Instant?
    @ObservationIgnored private var rightTriggerPressedAt: ContinuousClock.Instant?
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant

    /// The virtual touchpad lent to the gamepad's views, if one is attached.
    public weak var touchpad: VirtualTouchpadModel?

    /// Creates a link with an idle pad and no touchpad.
    ///
    /// - Parameter now: Reads the time each take happens at, which tests replace.
    public nonisolated init(now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// Replaces the published pad state and latches whatever it presses until the next ``take()``.
    ///
    /// - Parameter state: The pad's held buttons and stick positions.
    func publish(_ state: ControllerState) {
        pad = state
        latched.merge(state)
    }

    /// Reads the pad for one frame: the current state together with every press published since the previous
    /// take, after which only the current state remains latched. A button or trigger released before
    /// ``minimumHold`` has passed since the read that first sent it stays pressed until it has.
    ///
    /// - Returns: The pad state the frame should send.
    public func take() -> ControllerState {
        let at = now()
        var seen = latched
        latched = pad
        for bit in Self.bits(of: sent.buttons & ~seen.buttons) where holding(
            since: buttonsPressedAt[bit],
            at: at
        ) {
            seen.buttons |= bit
        }
        if seen.leftTrigger == 0, holding(since: leftTriggerPressedAt, at: at) {
            seen.leftTrigger = sent.leftTrigger
        }
        if seen.rightTrigger == 0, holding(since: rightTriggerPressedAt, at: at) {
            seen.rightTrigger = sent.rightTrigger
        }
        for bit in Self.bits(of: seen.buttons & ~sent.buttons) {
            buttonsPressedAt[bit] = at
        }
        for bit in Self.bits(of: sent.buttons & ~seen.buttons) {
            buttonsPressedAt[bit] = nil
        }
        leftTriggerPressedAt = Self.pressedAt(
            leftTriggerPressedAt,
            was: sent.leftTrigger,
            now: seen.leftTrigger,
            at: at
        )
        rightTriggerPressedAt = Self.pressedAt(
            rightTriggerPressedAt, was: sent.rightTrigger, now: seen.rightTrigger, at: at
        )
        sent = seen
        return seen
    }

    private func holding(since: ContinuousClock.Instant?, at: ContinuousClock.Instant) -> Bool {
        guard let since else {
            return false
        }
        return at - since < Self.minimumHold
    }

    private static func pressedAt(
        _ since: ContinuousClock.Instant?, was: UInt8, now: UInt8, at: ContinuousClock.Instant
    ) -> ContinuousClock.Instant? {
        if now == 0 {
            return nil
        }
        return was == 0
            ? at
            : since
    }

    private static func bits(of mask: UInt32) -> [UInt32] {
        (0..<32).map { UInt32(1) << $0 }.filter { mask & $0 != 0 }
    }

    /// Lends a virtual touchpad to the gamepad's views.
    ///
    /// - Parameter model: The touchpad.
    public func attach(_ model: VirtualTouchpadModel) {
        touchpad = model
    }

    /// Takes a virtual touchpad back if it is the one lent.
    ///
    /// - Parameter model: The touchpad being torn down.
    /// - Returns: `true` when it was the lent touchpad and is now detached.
    @discardableResult
    public func detach(_ model: VirtualTouchpadModel) -> Bool {
        guard touchpad === model else {
            return false
        }
        touchpad = nil
        return true
    }
}

private enum VirtualGamepadLinkKey: TestDependencyKey {
    static var testValue: VirtualGamepadLink {
        VirtualGamepadLink()
    }
}

extension DependencyValues {
    /// The link ``VirtualGamepadFeature`` publishes the pad state into, which the app supplies at its root.
    public var virtualGamepadLink: VirtualGamepadLink {
        get {
            self[VirtualGamepadLinkKey.self]
        }
        set {
            self[VirtualGamepadLinkKey.self] = newValue
        }
    }
}

extension EnvironmentValues {
    /// The link the on-screen gamepad's views take the lent touchpad from, which the app supplies at its root.
    @Entry public var virtualGamepadLink = VirtualGamepadLink.unsupplied
}
