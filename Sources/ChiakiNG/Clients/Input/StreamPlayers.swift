import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import Foundation
import Video
#if os(macOS)
    import AppKit
#else
    import GameController
#endif

/// Who plays a stream and how: player one, the couch seats and the keyboard overlay, the input's
/// ``StreamInputPhase``, and the lanes, feedback, motion and lights kept in step with them.
///
/// Every change of who plays where, of the configuration or of the phase goes through here, so that the
/// pipeline's lanes, player one's haptics, the motion sensors, the microphone light and the lightbars always
/// follow the same players.
@MainActor
final class StreamPlayers {
    /// Player one's controller and its feedback.
    let playerOne: PlayerOneInput

    /// The couch seats.
    let seats: CouchSeatInput

    /// The keyboard and touchpads layered over the controllers.
    let overlay: KeyboardTouchOverlay

    /// The motion sensors and the device's own motion.
    let motion: MotionInput

    /// The controllers' lightbars.
    let lights: LightbarController

    /// Whether the stream has input, has lost it, or has stopped.
    private(set) var phase = StreamInputPhase.suspended

    private let environment: InputEnvironment
    private let microphone: Bool
    private var configuration: ControlsConfiguration
    private var pipelineToken: UUID?

    /// The controllers players 2 to 4 chose in the controls settings, by preference key and keyed by pad.
    var chosenControllers: [UInt8: String] {
        var chosen: [UInt8: String] = [:]
        for player in 1..<ControlsConfiguration.playerCount {
            if let key = configuration.controllerKey(forPlayer: player) {
                chosen[UInt8(player)] = key
            }
        }
        return chosen
    }

    /// Creates the players of a stream.
    ///
    /// - Parameters:
    ///   - environment: The player, controllers and services the input reaches.
    ///   - configuration: The controls configuration.
    ///   - options: What the stream offers its input.
    init(environment: InputEnvironment, configuration: ControlsConfiguration, options: StreamInputOptions) {
        self.environment = environment
        self.configuration = configuration
        microphone = options.microphone
        let rumble = RumbleDriver(environment: environment)
        let seats = CouchSeatInput(environment: environment, rumble: rumble)
        self.seats = seats
        playerOne = PlayerOneInput(
            environment: environment,
            configuration: configuration,
            rumble: rumble,
            consoleHaptics: options.consoleHaptics
        )
        overlay = KeyboardTouchOverlay(
            environment: environment,
            configuration: configuration,
            options: options,
            seats: seats
        )
        motion = MotionInput(environment: environment)
        lights = LightbarController(environment: environment, configured: configuration.lightbars)
    }

    /// Binds the pipeline, chooses player one and starts reading the keyboard.
    func begin() {
        lights.adopt(configured: configuration.lightbars)
        pipelineToken = environment.pipeline.bind(player: environment.player) { [weak self] action in
            self?.perform(action)
        }
        refreshDevice()
        assignLane(pad: 0)
        playerOne.resolve()
        syncDeviceMotion()
        #if os(iOS)
            overlay.attachKeyboard(configuration) { [weak self] code, pressed in
                self?.type(code, pressed: pressed)
            }
        #else
            overlay.attachKeyboard { [weak self] event in
                self?.consumes(event) ?? true
            }
        #endif
    }

    /// Starts following the on-screen touchpad.
    func attachTouchpad() {
        overlay.attachTouchpad(
            changed: { [weak self] in
                self?.submitTouchpad()
            },
            toggle: { [weak self] in
                self?.toggleTouchpad()
            }
        )
    }

    /// Stops the input, before the stream's coordinator attachment is released.
    func stop() {
        phase = .stopped
        lights.end()
        overlay.abandon()
        #if os(iOS)
            playerOne.stopPhoneRumble()
            motion.senseDevice(false)
        #endif
    }

    /// Releases every seat, lane and controller output once the input stopped.
    func release() {
        overlay.detach()
        for pad in seats.pads {
            route(pad: pad, device: nil)
        }
        clear()
        if let pipelineToken {
            environment.pipeline.unbind(pipelineToken)
        }
        pipelineToken = nil
        playerOne.endFeedback()
        syncMotionSensors()
        environment.microphoneLight.attach(nil)
        lights.stopEvents()
        syncLights()
    }

    /// Applies a changed controls configuration to every player.
    ///
    /// - Parameter next: The configuration.
    func reload(configuration next: ControlsConfiguration) {
        configuration = next
        overlay.reload(next)
        if playerOne.reload(next) {
            configureFeedback()
        }
        seats.reload(next)
        for pad in seats.pads {
            assignLane(pad: pad)
        }
        assignLane(pad: 0)
        syncDeviceMotion()
        reloadLights()
    }

    /// Puts a controller, the keyboard or nothing on a couch seat.
    ///
    /// - Parameters:
    ///   - pad: The seat's pad.
    ///   - device: The controller or keyboard, or `nil` to empty the seat.
    func route(pad: UInt8, device: ControllerDevice?) {
        defer {
            refreshDevice()
            environment.coordinator.updateStreamPreferredKey(playerOne.preferredKey)
        }
        if seats.keyboardPad == pad {
            overlay.vacateSeat(pad, active: phase == .active)
        }
        let routing = seats.route(
            pad: pad,
            device: device,
            configuration: configuration,
            surface: overlay.surface
        )
        switch routing.placement {
        case .keyboard:
            if routing.vacated != nil {
                environment.pipeline.release(pad: pad)
            }
            seats.vacate(pad)
            overlay.resetKeyboard()
            overlay.publish(active: phase == .active)
            seats.seatKeyboard(on: pad)
        case .empty:
            seats.release(routing.vacated, pad: pad)
            seats.vacate(pad)
            lights.forgetGameColor(pad: pad)
        case .controller(let seat):
            seats.release(routing.vacated, pad: pad)
            seats.seat(seat, on: pad)
            assignLane(pad: pad)
        }
    }

    /// Makes a controller or the keyboard player one.
    ///
    /// - Parameter chosen: The controller or keyboard.
    func assignPlayerOne(_ chosen: ControllerDevice) {
        guard playerOne.prefer(chosen, seated: seats.holds(chosen.id)) else {
            return
        }
        refreshDevice(adopting: chosen.isKeyboard
            ? nil
            : chosen.id)
        environment.coordinator.updateStreamPreferredKey(playerOne.preferredKey)
    }

    /// Records the colour the game set for a pad's lightbar.
    ///
    /// - Parameters:
    ///   - pad: The pad.
    ///   - color: The colour as `0xRRGGBB`.
    func gameLight(pad: UInt8, color: UInt32) {
        guard phase != .stopped, pad < 4 else {
            return
        }
        lights.setGameColor(pad: pad, color: color)
        syncLights()
    }

    /// Takes the lightbar choices the app currently shows.
    func reloadLights() {
        guard phase != .stopped else {
            return
        }
        lights.adopt(configured: configuration.lightbars)
        syncLights()
    }

    /// Moves the input to a new phase when the stream window gains or loses input.
    ///
    /// Everything held is released, and the feedback, motion and touchpads follow the new phase.
    ///
    /// - Parameter next: The new phase.
    func change(to next: StreamInputPhase) {
        let message = next.focusMessage(
            releasing: environment.pipeline.lastSent(pad: 0).buttons | seats.keyboardLast.buttons
        )
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(message))
        phase = next
        overlay.interrupt()
        environment.sendVirtualGamepad(.releasedAll)
        clear()
        environment.pipeline.setLive(pad: 0, next == .active)
        overlay.submitSeat(active: next == .active)
        configureFeedback()
        syncMotionSensors()
        overlay.seed(from: playerOne.device, active: next == .active)
    }

    /// Clears player one's feedback, the keyboard and pad `0`'s input.
    func clear() {
        playerOne.clearFeedback()
        overlay.clear(active: phase == .active)
    }

    /// Looks at the free controllers, moves player one when it should, and makes every output follow.
    ///
    /// - Parameter chosen: A controller to adopt as player one, if one was chosen.
    func refreshDevice(adopting chosen: UInt32? = nil) {
        let timing = SlowStep("choosing the stream's controller")
        defer {
            timing.finish()
        }
        let seated = seats.seatedDevices
        let devices = environment.connectedDevices().filter { !seated.contains($0.id) }
        if case .changed(let next) = playerOne.choose(from: devices, adopting: chosen) {
            clear()
            playerOne.adopt(next, configuration: configuration)
            assignLane(pad: 0)
            configureFeedback()
            overlay.seed(from: playerOne.device, active: phase == .active)
            environment.coordinator.updateStreamPreferredKey(playerOne.preferredKey)
        }
        syncMotionSensors()
        environment.microphoneLight.attach(microphone && playerOne.device?.adaptiveTriggers == true
            ? playerOne.device?.id
            : nil)
        syncLights()
    }

    /// Routes player one's haptics for the current phase.
    func configureFeedback() {
        playerOne.configureFeedback(hasInput: phase == .active) { [weak self] in
            self?.configureFeedback()
        }
    }

    /// Enables the motion sensors of the controllers whose motion reaches the stream.
    func syncMotionSensors() {
        motion.sense(MotionInput.wanted(
            playerOne: playerOne.device?.id,
            active: phase == .active,
            seats: seats.seatedDevices,
            seatsActive: seats.isActive
        ))
    }

    /// Lights every playing controller.
    func syncLights() {
        lights.show(LightbarController.devices(
            playerOne: playerOne.device,
            seats: seats.seats,
            live: phase != .stopped
        ))
    }

    private func syncDeviceMotion() {
        motion.senseDevice(configuration.deviceMotion && phase != .stopped)
    }

    private func assignLane(pad: UInt8) {
        guard pipelineToken != nil else {
            return
        }
        guard pad == 0 else {
            seats.assignLane(pad: pad, configuration: configuration, surface: overlay.surface)
            return
        }
        environment.pipeline.assign(pad: 0, playerOne.lane(
            configuration: configuration,
            microphone: microphone,
            surface: overlay.surface,
            deviceMotion: motion.deviceMotionAvailable && configuration.deviceMotion
        ), live: phase == .active)
    }

    private func perform(_ action: GameInputLane.Action) {
        overlay.perform(action, phase: phase)
    }

    private func toggleTouchpad() {
        overlay.toggleTouchpad(phase: phase)
    }

    private func submitTouchpad() {
        overlay.submitTouchpad(active: phase == .active)
    }

    #if os(macOS)
        private func consumes(_ event: NSEvent) -> Bool {
            overlay.consumes(event, phase: phase, configuration: configuration)
        }
    #else
        private func type(_ code: GCKeyCode, pressed: Bool) {
            overlay.type(code, pressed: pressed, phase: phase, configuration: configuration)
        }
    #endif
}

/// Whether a stream's input reaches the console.
enum StreamInputPhase: Equatable {
    /// The stream window lost input focus; held input is released and nothing new is sent.
    case suspended
    /// Input reaches the console.
    case active
    /// The stream ended; nothing is sent again.
    case stopped

    /// How a move to this phase reads in the log when the stream window gains or loses input.
    ///
    /// - Parameter held: The buttons held when the move happened, which losing input releases.
    /// - Returns: The log line.
    func focusMessage(releasing held: UInt32) -> String {
        let reason = self == .active
            ? "the stream window has input again"
            : "the stream lost input focus, so held buttons 0x\(String(held, radix: 16)) are released"
        return "Stream input \(self): \(reason)"
    }
}
