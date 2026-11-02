import ChiakiFeatures
import ChiakiDiagnostics
import ChiakiModels
import CInput
import Dependencies
import Foundation
import PlatformUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Player one's touchpad: the on-screen virtual touchpad and the controller's own, and which of them the
/// console hears while both are touched.
@MainActor
final class TouchpadInput {
    /// The on-screen touchpad.
    let virtual: VirtualTouchpadModel

    private let environment: InputEnvironment
    private var physical: PhysicalTouchpad
    private var arbiter = TouchpadArbiter()
    private var observer: NSObjectProtocol?

    /// Creates the touchpads for a console's surface.
    ///
    /// - Parameters:
    ///   - environment: The player and controllers the touchpads read.
    ///   - surface: The console's touchpad surface.
    ///   - onScreen: Whether the on-screen touchpad may be shown.
    init(environment: InputEnvironment, surface: TouchpadSurface, onScreen: Bool) {
        self.environment = environment
        @Dependency(\.logger) var logger
        virtual = VirtualTouchpadModel(surface: surface, logger: logger, enabled: onScreen)
        physical = PhysicalTouchpad(surface: surface)
    }

    /// The console's touchpad surface.
    var surface: TouchpadSurface {
        physical.surface
    }

    /// The fingers on player one's controller touchpad.
    var physicalTouches: ControllerTouchSlots {
        physical.touches
    }

    /// Applies a native touch event to a touchpad.
    ///
    /// - Parameters:
    ///   - event: A touch down, motion or up event.
    ///   - touchpad: The touchpad.
    ///   - avoiding: Touch ids the console still holds, which new fingers must not reuse.
    nonisolated static func apply(
        _ event: nx_input_event,
        to touchpad: inout PhysicalTouchpad,
        avoiding: Set<UInt8>
    ) {
        let finger = PhysicalTouchpad.Finger(touchpad: Int(event.value), finger: Int(event.control))
        let x = Double(event.data.0)
        let y = Double(event.data.1)
        switch event.kind {
        case ControllerInputEvent.touchDown:
            touchpad.down(finger, x: x, y: y, avoiding: avoiding)
        case ControllerInputEvent.touchMotion:
            touchpad.moved(finger, x: x, y: y)
        case ControllerInputEvent.touchUp:
            touchpad.up(finger)
        default:
            break
        }
    }

    /// Lends the on-screen touchpad to the gamepad overlay.
    func adopt() {
        environment.virtualGamepadLink.attach(virtual)
        environment.sendVirtualGamepad(.touchpadAttached)
    }

    /// Starts listening to the on-screen touchpad.
    ///
    /// - Parameters:
    ///   - changed: Called when the on-screen touchpad's output changes.
    ///   - toggle: Called when the user asks to show or hide the on-screen touchpad in the stream's window.
    func attach(changed: @escaping () -> Void, toggle: @escaping @MainActor @Sendable () -> Void) {
        virtual.changed = changed
        observer = NotificationCenter.default.addObserver(
            forName: .toggleVirtualTouchpad, object: nil, queue: .main
        ) { [environment] notification in
            let target = notification.object as? PlatformWindow
            MainActor.assumeIsolated {
                guard let target, target === environment.player.view.window else {
                    return
                }
                toggle()
            }
        }
    }

    /// Stops listening and hides the on-screen touchpad.
    func detach() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        virtual.changed = {
        }
        virtual.hide()
        virtual.detach()
    }

    /// Takes the on-screen touchpad back from the gamepad overlay, which returns the gamepad to its saved
    /// presence.
    func abandon() {
        if environment.virtualGamepadLink.detach(virtual) {
            environment.sendVirtualGamepad(.touchpadDetached)
        }
    }

    /// Allows or forbids showing the on-screen touchpad.
    ///
    /// - Parameter onScreen: Whether the on-screen touchpad may be shown.
    func enable(_ onScreen: Bool) {
        virtual.enable(onScreen)
    }

    /// Shows or hides the on-screen touchpad.
    func toggle() {
        virtual.toggle()
    }

    /// Ends any touch on the on-screen touchpad.
    func cancel() {
        virtual.cancel()
    }

    /// Places the on-screen touchpad over the stream and advances its gestures.
    ///
    /// - Parameter view: The stream's view.
    func frame(over view: PlatformView) {
        virtual.attach(over: view)
        virtual.tick()
    }

    /// Forgets every finger on the controller's touchpad.
    func reset() {
        physical.reset()
    }

    /// Applies a touch from player one's controller.
    ///
    /// - Parameters:
    ///   - event: The touch event.
    ///   - avoiding: Touch ids the console still holds.
    func apply(_ event: nx_input_event, avoiding: Set<UInt8>) {
        Self.apply(event, to: &physical, avoiding: avoiding)
    }

    /// Whether the console hears a touchpad.
    ///
    /// - Parameters:
    ///   - source: The touchpad.
    ///   - keyboardPad: The pad the keyboard plays on.
    /// - Returns: `true` when the keyboard sits on a seat or the arbiter admits the source.
    func admits(_ source: TouchpadSource, keyboardPad: UInt8) -> Bool {
        keyboardPad != 0 || arbiter.admits(source)
    }

    /// Whether a click on the controller's touchpad reaches the console.
    ///
    /// - Parameter keyboardPad: The pad the keyboard plays on.
    /// - Returns: `false` while the on-screen touchpad holds the console's touchpad.
    func physicalClickAllowed(keyboardPad: UInt8) -> Bool {
        keyboardPad != 0 || !arbiter.suppresses(.physical)
    }

    /// Decides which touchpad the console hears after the contacts changed.
    ///
    /// - Parameters:
    ///   - keyboardPad: The pad the keyboard plays on.
    ///   - active: Whether the stream has input.
    func arbitrate(keyboardPad: UInt8, active: Bool) {
        let before = arbiter.phase
        arbiter.update(TouchpadArbiter.Contacts(
            virtual: keyboardPad == 0 && active && virtual.output.touch != nil,
            physical: physical.isActive
        ))
        let after = arbiter.phase
        guard before != after else {
            return
        }
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(
            .controller, .debug, "Touchpad ownership \(before) became \(after)"
        ))
    }

    /// Adds the on-screen touchpad's touch and click to a state.
    ///
    /// - Parameters:
    ///   - state: The state.
    ///   - active: Whether the stream has input.
    ///   - keyboardPad: The pad the keyboard plays on.
    /// - Returns: The state with the on-screen touchpad applied when the console hears it.
    func applying(to state: ControllerState, active: Bool, keyboardPad: UInt8) -> ControllerState {
        guard active, admits(.virtual, keyboardPad: keyboardPad) else {
            return state
        }
        let output = virtual.output
        var result = state
        if let touch = output.touch {
            result.touches = ControllerTouchSlots(first: touch)
        }
        if output.clicked {
            result.buttons |= PlayStationControl.touchpad.bit ?? 0
        }
        return result
    }

    #if os(macOS)
        /// Whether a mouse event lands on the on-screen touchpad.
        ///
        /// - Parameter event: The event.
        /// - Returns: `true` when the touchpad should handle it.
        func contains(_ event: NSEvent) -> Bool {
            virtual.contains(event)
        }
    #endif
}
