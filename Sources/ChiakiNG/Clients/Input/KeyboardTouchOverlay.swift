import CInput
import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiFeatures
import ChiakiModels
import Foundation
import Video
#if os(macOS)
    import AppKit
#else
    import GameController
#endif

/// The keyboard and the touchpads of a stream, layered over player one's controller or sent from the
/// keyboard's own couch seat.
///
/// While the keyboard plays as player one, its keys, the on-screen gamepad and whichever touchpad the console
/// hears form the overlay of pad `0`. Once the keyboard sits on a couch seat, its state is sent to that seat
/// directly.
@MainActor
final class KeyboardTouchOverlay {
    private let environment: InputEnvironment
    private let keyboard: StreamKeyboardInput
    private let touchpad: TouchpadInput
    private let seats: CouchSeatInput

    /// Creates the keyboard and touchpads of a stream.
    ///
    /// - Parameters:
    ///   - environment: The player and pipeline the overlay sends to.
    ///   - configuration: The controls configuration, which says whether the on-screen touchpad may be shown.
    ///   - options: The stream's touchpad surface, and whether it types on the console and offers a microphone.
    ///   - seats: The couch seats, which say where the keyboard plays.
    init(
        environment: InputEnvironment,
        configuration: ControlsConfiguration,
        options: StreamInputOptions,
        seats: CouchSeatInput
    ) {
        self.environment = environment
        self.seats = seats
        keyboard = StreamKeyboardInput(
            environment: environment,
            surface: options.touchpadSurface,
            rawKeyboard: options.rawKeyboard,
            microphone: options.microphone
        )
        touchpad = TouchpadInput(
            environment: environment,
            surface: options.touchpadSurface,
            onScreen: configuration.onScreenTouchpad
        )
    }

    /// The console's touchpad surface.
    var surface: TouchpadSurface {
        touchpad.surface
    }

    /// The fingers on player one's touchpad that the console already holds.
    private var heldTouches: Set<UInt8> {
        environment.pipeline.lastSent(pad: 0).touches.ids.union(seats.keyboardLast.touches.ids)
    }

    #if os(macOS)
        /// Starts reading the keyboard and the mouse, and takes the on-screen touchpad.
        ///
        /// - Parameter consumes: Decides for each event whether the stream takes it.
        func attachKeyboard(_ consumes: @escaping @MainActor (NSEvent) -> Bool) {
            touchpad.adopt()
            keyboard.install(consumes)
        }
    #else
        /// Starts typing the hardware keyboard on the console, and takes the on-screen touchpad with the
        /// on-screen gamepad in its saved presence.
        ///
        /// - Parameters:
        ///   - configuration: The controls configuration the stream starts with.
        ///   - typed: Called on the main actor for each key change.
        func attachKeyboard(
            _ configuration: ControlsConfiguration,
            typed: @escaping @MainActor @Sendable (GCKeyCode, Bool) -> Void
        ) {
            environment.sendVirtualGamepad(.preferred(configuration.virtualGamepad))
            touchpad.adopt()
            keyboard.attach(typed)
        }
    #endif

    /// Starts following the on-screen touchpad.
    ///
    /// - Parameters:
    ///   - changed: Called when its touches change.
    ///   - toggle: Called when it is shown or hidden.
    func attachTouchpad(changed: @escaping () -> Void, toggle: @escaping @MainActor @Sendable () -> Void) {
        touchpad.attach(changed: changed, toggle: toggle)
    }

    /// Gives up the on-screen touchpad and, on iOS, stops typing the hardware keyboard.
    func abandon() {
        touchpad.abandon()
        #if os(iOS)
            keyboard.detach()
        #endif
    }

    /// Stops reading the keyboard and the on-screen touchpad.
    func detach() {
        #if os(macOS)
            keyboard.remove()
        #endif
        touchpad.detach()
    }

    /// Releases the keys typed on the console when a configuration no longer types on it, and takes a newly
    /// saved on-screen gamepad presence and on-screen touchpad choice.
    ///
    /// - Parameter configuration: The new configuration.
    func reload(_ configuration: ControlsConfiguration) {
        if !keyboard.typesOnConsole(configuration) {
            keyboard.releaseTypedKeys()
        }
        touchpad.enable(configuration.onScreenTouchpad)
        environment.sendVirtualGamepad(.preferred(configuration.virtualGamepad))
    }

    /// Releases every key typed on the console and every touch, when the stream gains or loses input.
    func interrupt() {
        keyboard.releaseTypedKeys()
        touchpad.cancel()
    }

    /// Clears the keyboard, pad `0`'s input and the touchpads.
    ///
    /// - Parameter active: Whether the stream has input.
    func clear(active: Bool) {
        keyboard.reset()
        environment.pipeline.resetInput(pad: 0)
        touchpad.reset()
        touchpad.arbitrate(keyboardPad: seats.keyboardPad, active: active)
    }

    /// Clears the keyboard's controller state.
    func resetKeyboard() {
        keyboard.reset()
    }

    /// Follows the player's view with the on-screen touchpad.
    func frame() {
        touchpad.frame(over: environment.player.view)
    }

    /// Applies a touch from player one's controller.
    ///
    /// - Parameter event: The touch.
    func touch(_ event: nx_input_event) {
        touchpad.apply(event, avoiding: heldTouches)
        touchpad.arbitrate(keyboardPad: seats.keyboardPad, active: true)
        publish(active: true)
    }

    /// Reads the fingers already on player one's controller's touchpad while the stream has input.
    ///
    /// - Parameters:
    ///   - device: Player one's controller, if any.
    ///   - active: Whether the stream has input.
    func seed(from device: ControllerDevice?, active: Bool) {
        let timing = SlowStep("reading the touchpad")
        defer {
            timing.finish()
        }
        guard active, let device else {
            return
        }
        for event in environment.backend.touchFingers(device.id) {
            touchpad.apply(event, avoiding: heldTouches)
        }
        touchpad.arbitrate(keyboardPad: seats.keyboardPad, active: true)
    }

    /// Shows or hides the on-screen touchpad unless the stream stopped.
    ///
    /// - Parameter phase: The stream input's phase.
    func toggleTouchpad(phase: StreamInputPhase) {
        guard phase != .stopped else {
            return
        }
        touchpad.toggle()
    }

    /// Asks the stream window to switch the microphone on or off.
    func toggleMicrophone() {
        NotificationCenter.default.post(name: .toggleStreamMicrophone, object: environment.player.view.window)
    }

    /// Carries out a shortcut a controller lane recognised.
    ///
    /// - Parameters:
    ///   - action: The shortcut.
    ///   - phase: The stream input's phase.
    func perform(_ action: GameInputLane.Action, phase: StreamInputPhase) {
        switch action {
        case .toggleTouchpad:
            toggleTouchpad(phase: phase)
        case .toggleMicrophone:
            toggleMicrophone()
        }
    }

    /// Sends a changed on-screen touchpad to wherever the keyboard plays.
    ///
    /// - Parameter active: Whether the stream has input.
    func submitTouchpad(active: Bool) {
        guard active else {
            return
        }
        touchpad.arbitrate(keyboardPad: seats.keyboardPad, active: true)
        submitKeys(active: true)
    }

    /// Sends the keyboard's state to wherever it plays.
    ///
    /// - Parameter active: Whether the stream has input.
    func submitKeys(active: Bool) {
        if seats.keyboardPad == 0 {
            publish(active: active)
        } else {
            submitSeat(active: active)
        }
    }

    /// Sends the keyboard's state to its couch seat when it changed.
    ///
    /// - Parameter active: Whether the stream has input.
    func submitSeat(active: Bool) {
        let state = touchpad.applying(to: keyboard.state, active: active, keyboardPad: seats.keyboardPad)
        guard seats.keyboardPad != 0, state != seats.keyboardLast else {
            return
        }
        let sample = ControllerSampleWriter.sample(of: state)
        if environment.player.send(sample, pad: Int(seats.keyboardPad)) {
            seats.keyboardLast = state
        }
    }

    /// Sends pad `0`'s overlay: the keyboard, the on-screen gamepad and the touchpad the console hears.
    ///
    /// - Parameter active: Whether the stream has input.
    func publish(active: Bool) {
        let keys = seats.keyboardPad == 0
            ? touchpad.applying(to: keyboard.state, active: active, keyboardPad: 0)
            : ControllerState()
        var overlaid = keys
        overlaid.merge(environment.virtualGamepadLink.take())
        environment.pipeline.setOverlay(pad: 0, GameInputLane.Overlay(
            keys: overlaid,
            touches: touchpad.admits(.physical, keyboardPad: seats.keyboardPad)
                ? touchpad.physicalTouches
                : keys.touches,
            suppressTouchpadClick: !touchpad.physicalClickAllowed(keyboardPad: seats.keyboardPad)
        ))
    }

    /// Takes the keyboard off its couch seat, releasing everything it held there.
    ///
    /// - Parameters:
    ///   - pad: The keyboard's seat.
    ///   - active: Whether the stream has input.
    func vacateSeat(_ pad: UInt8, active: Bool) {
        keyboard.reset()
        submitSeat(active: active)
        seats.releaseKeyboard()
        environment.player.setControllerButtons(
            0, l2: 0, r2: 0, leftX: 0, leftY: 0, rightX: 0, rightY: 0, pad: Int(pad)
        )
    }

    #if os(macOS)
        /// Decides whether the stream takes a keyboard or mouse event, and acts on it.
        ///
        /// - Parameters:
        ///   - event: The event.
        ///   - phase: The stream input's phase.
        ///   - configuration: The controls configuration.
        /// - Returns: `true` when the stream took the event.
        func consumes(_ event: NSEvent, phase: StreamInputPhase,
                      configuration: ControlsConfiguration) -> Bool {
            switch keyboard.handle(event, phase: phase, configuration: configuration, touchpad: touchpad) {
            case .passed:
                return false
            case .consumed:
                return true
            case .toggleMicrophone:
                toggleMicrophone()
                return true
            case .toggleTouchpad:
                toggleTouchpad(phase: phase)
                return true
            case .mapped:
                submitKeys(active: phase == .active)
                return true
            }
        }
    #else
        /// Types one hardware key change on the console.
        ///
        /// - Parameters:
        ///   - code: The key.
        ///   - pressed: Whether it went down.
        ///   - phase: The stream input's phase.
        ///   - configuration: The controls configuration.
        func type(
            _ code: GCKeyCode,
            pressed: Bool,
            phase: StreamInputPhase,
            configuration: ControlsConfiguration
        ) {
            keyboard.type(code, pressed: pressed, phase: phase, configuration: configuration)
        }
    #endif
}
