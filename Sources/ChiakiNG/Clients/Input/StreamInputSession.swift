import CInput
import ChiakiFeatures
import ChiakiModels
import Foundation
import PlatformUI
import Video

/// One stream's controller, keyboard, touchpad and feedback input, from the first frame until the stream ends.
///
/// The session attaches the stream to the app's controller routing, the system gestures and the shared
/// lights, and takes the player's commands. ``StreamPlayers`` decides who plays where and keeps every output
/// in step, and `StreamInputPoller` applies each poll of the controllers on the main actor. While the session
/// is attached it also holds the real-time input clock of ``GameInputPipeline`` running, which advances the
/// lanes' time-driven input and sends the feedback off the main thread.
@MainActor
final class StreamInputSession {
    /// How long a newly connected controller waits before it is offered a seat.
    static let newControllerDelay = Duration.seconds(1)

    private let environment: InputEnvironment
    private let players: StreamPlayers
    private let poller: StreamInputPoller
    private var systemGestureHold: ControllerSystemGestureHold?
    private var inputLease: UUID?
    private var clockLease: UUID?

    /// Creates the input for a stream.
    ///
    /// - Parameters:
    ///   - environment: The player, controllers and services the input reaches.
    ///   - configuration: The controls configuration.
    ///   - options: What the stream offers its input.
    init(environment: InputEnvironment, configuration: ControlsConfiguration, options: StreamInputOptions) {
        self.environment = environment
        let players = StreamPlayers(environment: environment, configuration: configuration, options: options)
        self.players = players
        poller = StreamInputPoller(environment: environment, players: players)
    }

    /// Whether the session receives input, from ``start()`` until ``stop()``.
    var isAttached: Bool {
        inputLease != nil
    }

    /// The lights shared with couch guests.
    var couchLights: CouchLights {
        players.lights.couchLights
    }

    /// Starts receiving controller, keyboard and touchpad input.
    func start() {
        guard players.phase != .stopped, inputLease == nil else {
            return
        }
        systemGestureHold = environment.systemGestures.acquire()
        players.begin()
        inputLease = environment.coordinator.attachStream(
            preferredKey: players.playerOne.preferredKey,
            window: { [weak self] in self?.environment.player.view.window },
            receive: { [weak self] events, active in
                self?.poller.poll(events: events, focused: active)
            },
            secondary: { [weak self] events, active in
                self?.poller.pollSeats(events: events, active: active)
            },
            seated: { [weak self] in
                self?.players.seats.seatedDevices ?? []
            }
        )
        clockLease = environment.pipeline.startClock()
        environment.lights.streamStarted(self)
        players.attachTouchpad()
    }

    /// Stops receiving input, releases every controller and restores their lights.
    func stop() {
        guard players.phase != .stopped else {
            return
        }
        systemGestureHold = nil
        players.stop()
        if let inputLease {
            environment.coordinator.detachStream(inputLease)
        }
        inputLease = nil
        if let clockLease {
            environment.pipeline.stopClock(clockLease)
        }
        clockLease = nil
        players.release()
        environment.lights.streamEnded(self)
    }

    /// Applies a changed controls configuration to every player.
    ///
    /// - Parameter next: The configuration.
    func reload(configuration next: ControlsConfiguration) {
        players.reload(configuration: next)
    }

    /// Puts a controller, the keyboard or nothing on a couch seat.
    ///
    /// - Parameters:
    ///   - pad: The seat's pad.
    ///   - device: The controller or keyboard, or `nil` to empty the seat.
    func route(pad: UInt8, device: ControllerDevice?) {
        players.route(pad: pad, device: device)
    }

    /// Makes a controller or the keyboard player one.
    ///
    /// - Parameter chosen: The controller or keyboard.
    func assignPlayerOne(_ chosen: ControllerDevice) {
        players.assignPlayerOne(chosen)
    }

    /// The connected controllers and player one, for the couch menu.
    ///
    /// - Returns: The inventory.
    func inventory() -> CouchInventory {
        CouchInventory(
            controllers: environment.connectedDevices().filter { !$0.isKeyboard },
            playerOne: players.playerOne.device
        )
    }

    /// Records the colour the game set for a pad's lightbar.
    ///
    /// - Parameters:
    ///   - pad: The pad.
    ///   - color: The colour as `0xRRGGBB`.
    func gameLight(pad: UInt8, color: UInt32) {
        players.gameLight(pad: pad, color: color)
    }

    /// Follows the couch events that change the controllers' lights.
    ///
    /// - Parameter couch: The event.
    func observe(_ couch: CouchSessionEvent) {
        if case let .confirmed(pad, color) = couch {
            players.gameLight(pad: pad, color: color)
        }
    }

    /// Takes the lightbar choices the app currently shows.
    func reloadLights() {
        players.reloadLights()
    }

    /// Handles each poll of a stream's controllers: player one's events, the couch seats' events, and the
    /// overlays sent once the events are applied.
    ///
    /// A poll first follows a change of input focus, then lets player one and the seats react to their events,
    /// and only then tells the feedback where it goes and publishes the overlays. The lanes' time-driven input
    /// and the feedback itself run on the real-time input clock of ``GameInputPipeline``, not here.
    @MainActor
    private final class StreamInputPoller {
        private let environment: InputEnvironment
        private let players: StreamPlayers

        /// Creates the poller of a stream's players.
        ///
        /// - Parameters:
        ///   - environment: The pipeline and controllers the polls reach.
        ///   - players: The stream's players.
        init(environment: InputEnvironment, players: StreamPlayers) {
            self.environment = environment
            self.players = players
        }

        /// Applies one poll of player one's controller.
        ///
        /// - Parameters:
        ///   - events: Player one's events since the last poll.
        ///   - focused: Whether the stream window has input.
        func poll(events: [nx_input_event], focused: Bool) {
            guard players.phase != .stopped else {
                return
            }
            let next: StreamInputPhase = focused
                ? .active
                : .suspended
            if next != players.phase {
                players.change(to: next)
            }
            if players.playerOne.checkHealth(phase: players.phase) {
                players.refreshDevice()
                players.playerOne.logFeedbackCounters()
            }
            players.motion.applyConsoleRequests()
            for event in events {
                process(event)
            }
            players.playerOne.pumpFeedback(active: players.phase == .active)
            players.overlay.frame()
            if players.phase == .active {
                players.overlay.publish(active: true)
                players.overlay.submitSeat(active: true)
            }
            players.playerOne.recordInputDelays()
        }

        /// Applies one poll of the controllers that are not player one's.
        ///
        /// - Parameters:
        ///   - events: Their events since the last poll.
        ///   - active: Whether the stream window has input.
        func pollSeats(events: [nx_input_event], active: Bool) {
            guard players.phase != .stopped else {
                return
            }
            let seats = players.seats
            seats.announcePending(playerOne: players.playerOne.device?.id)
            if seats.setActive(active) {
                players.syncMotionSensors()
                if active {
                    seats.seedTouchpads()
                }
            }
            for instance in seats.process(events, playerOne: players.playerOne.device?.id) {
                announceLater(instance)
            }
            seats.releaseClaims(playerOne: players.playerOne.device?.id)
            seats.publish()
        }

        private func process(_ event: nx_input_event) {
            if event.kind == ControllerInputEvent.added {
                players.refreshDevice()
                return
            }
            guard event.instance == players.playerOne.device?.id,
                  !ControllerInputEvent.isSensor(event)
            else {
                return
            }
            players.seats.notePlayerOne(event)
            if ControllerInputEvent.isTouch(event) {
                if players.phase == .active {
                    players.overlay.touch(event)
                }
                return
            }
            if event.kind == ControllerInputEvent.removed {
                players.playerOne.disconnect()
                environment.microphoneLight.attach(nil)
                players.clear()
                players.configureFeedback()
                players.refreshDevice()
                players.syncLights()
            }
        }

        private func announceLater(_ instance: UInt32) {
            Task { [weak self] in
                try? await Task.sleep(for: StreamInputSession.newControllerDelay)
                guard let self, players.phase != .stopped else {
                    return
                }
                players.seats.announce(instance, playerOne: players.playerOne.device?.id)
            }
        }
    }
}

/// What a stream offers its input: the console's touchpad, typing, a microphone and console haptics.
struct StreamInputOptions: Equatable {
    /// The console's touchpad surface.
    var touchpadSurface = TouchpadSurface.ps5

    /// Whether the keyboard can type on the console.
    var rawKeyboard = false

    /// Whether the stream offers a microphone.
    var microphone = false

    /// Whether the console's haptics should play.
    var consoleHaptics = true
}
