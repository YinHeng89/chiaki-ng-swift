import CoreGraphics
import Foundation
import Observation
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Decides the ``InputMode`` from the input the app receives.
///
/// Controller input and the navigation keys switch to controller mode at once. Pointer movement switches to
/// pointer mode only after it travels ``pointerTravelThreshold`` points within ``pointerTravelWindow``
/// seconds, so a nudged mouse does not hide the focus; a click or scroll switches immediately.
@MainActor
@Observable
public final class InputModeCenter {
    /// How far the pointer must travel to count as deliberate movement.
    public static let pointerTravelThreshold: CGFloat = 12

    /// How long pointer movement accumulates before it starts again from zero.
    public static let pointerTravelWindow: TimeInterval = 0.25

    /// The virtual key codes that move focus: Tab and the four arrow keys.
    public static let focusMoveKeyCodes: Set<UInt16> = MenuArrowKey.keyCodes.union([48])

    /// The virtual key codes that navigate menus: the focus move keys plus Return, Space and Enter.
    public static let navigationKeyCodes = focusMoveKeyCodes.union([36, 49, 76])

    /// The current mode.
    public private(set) var mode: InputMode
    @ObservationIgnored private var travel: CGFloat = 0
    @ObservationIgnored private var lastMovement: TimeInterval?

    /// Creates a center.
    ///
    /// - Parameter mode: The mode to start in.
    public init(mode: InputMode = .pointer) {
        self.mode = mode
    }

    /// Records controller input.
    ///
    /// - Returns: Whether the mode changed to ``InputMode/controller``.
    @discardableResult
    public func controllerInput() -> Bool {
        travel = 0
        lastMovement = nil
        guard mode != .controller else {
            return false
        }
        mode = .controller
        return true
    }

    /// Records pointer movement.
    ///
    /// - Parameters:
    ///   - dx: The horizontal distance moved.
    ///   - dy: The vertical distance moved.
    ///   - time: When the movement happened, in seconds since boot.
    /// - Returns: Whether the mode changed to ``InputMode/pointer``.
    @discardableResult
    public func pointerMoved(dx: CGFloat, dy: CGFloat, at time: TimeInterval) -> Bool {
        guard mode != .pointer else {
            return false
        }
        if let lastMovement, time - lastMovement > Self.pointerTravelWindow {
            travel = 0
        }
        lastMovement = time
        travel += hypot(dx, dy)
        guard travel >= Self.pointerTravelThreshold else {
            return false
        }
        return pointerAction()
    }

    /// Records a click, tap or scroll.
    ///
    /// - Returns: Whether the mode changed to ``InputMode/pointer``.
    @discardableResult
    public func pointerAction() -> Bool {
        travel = 0
        lastMovement = nil
        guard mode != .pointer else {
            return false
        }
        mode = .pointer
        return true
    }

    /// Records a navigation controller connecting or disconnecting.
    ///
    /// - Parameter connected: Whether a controller is now connected.
    /// - Returns: Whether the mode changed.
    @discardableResult
    public func controllerConnection(_ connected: Bool) -> Bool {
        if connected {
            return controllerInput()
        }
        return pointerAction()
    }

    #if os(macOS)
        /// Records a key press, switching to controller mode for a navigation key outside text entry.
        ///
        /// - Parameters:
        ///   - keyCode: The virtual key code.
        ///   - modifiers: The modifier keys held.
        ///   - editingText: Whether a text field has focus.
        /// - Returns: Whether the mode changed to ``InputMode/controller``.
        @discardableResult
        public func keyPressed(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                               editingText: Bool) -> Bool {
            guard !editingText,
                  Self.navigationKeyCodes.contains(keyCode),
                  modifiers.isDisjoint(with: [.command, .control, .option]) else {
                return false
            }
            return controllerInput()
        }
    #endif
}

/// Whether the user is driving the app with a controller or keyboard, or with a pointer or touch.
///
/// Focus is drawn only in ``controller`` mode; moving the pointer hides it.
public enum InputMode: Equatable, Sendable {
    /// A mouse, trackpad or touch is in use; focus highlights are hidden.
    case pointer
    /// A controller or the navigation keys are in use; the focused control is highlighted.
    case controller

    /// Whether a control's focus should be drawn.
    ///
    /// - Parameter focused: Whether the control has focus.
    /// - Returns: `true` only for a focused control in controller mode.
    public func shows(_ focused: Bool) -> Bool {
        self == .controller && focused
    }
}

extension EnvironmentValues {
    /// The current input mode, published by ``SwiftUICore/View/inputModeEnvironment()``.
    @Entry public var inputMode = InputMode.controller
}

/// Publishes the navigator's current ``InputMode`` to the views below.
///
/// Apply it with ``SwiftUICore/View/inputModeEnvironment()``. Without a navigator in the environment the
/// default ``InputMode/controller`` stays in place.
public struct InputModeEnvironment: ViewModifier {
    @Environment(\.menuNavigator) private var navigator

    /// Creates the modifier.
    public init() {
    }

    /// Sets ``SwiftUICore/EnvironmentValues/inputMode`` from the navigator.
    ///
    /// - Parameter content: The view tree.
    /// - Returns: The tree with the input mode published.
    public func body(content: Content) -> some View {
        if let navigator {
            content.environment(\.inputMode, navigator.inputMode.mode)
        } else {
            content
        }
    }
}

extension View {
    /// Publishes the current input mode to the views below.
    ///
    /// - Returns: The view wrapped in ``InputModeEnvironment``.
    public func inputModeEnvironment() -> some View {
        modifier(InputModeEnvironment())
    }
}
