import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import Foundation
import MenuFocus
import Video

/// Player one's controller in a stream and the feedback it plays.
///
/// ``PlayerOneController`` decides which controller is player one; this logs and reports each change, routes
/// the controller's haptics through ``HapticRouter``, drains its rumble each poll and watches the input's
/// health.
@MainActor
final class PlayerOneInput {
    private let environment: InputEnvironment
    private var controller: PlayerOneController
    private let rumble: RumbleDriver
    private let haptics: HapticRouter
    private let health: InputHealthMonitor

    /// Creates player one from the saved preference.
    ///
    /// - Parameters:
    ///   - environment: The player and controllers the input reaches.
    ///   - configuration: The controls configuration, which names the saved player one.
    ///   - rumble: The rumble driver shared with the couch seats.
    ///   - consoleHaptics: Whether the console's haptics should play.
    init(
        environment: InputEnvironment,
        configuration: ControlsConfiguration,
        rumble: RumbleDriver,
        consoleHaptics: Bool
    ) {
        self.environment = environment
        self.rumble = rumble
        controller = PlayerOneController(
            primaryKey: configuration.selectedControllerKey,
            reserved: configuration.controllerKeys(takenFromPlayer: 0)
        )
        haptics = HapticRouter(environment: environment, rumble: rumble, consoleHaptics: consoleHaptics)
        health = InputHealthMonitor(environment: environment)
    }

    /// Player one's controller, or `nil` when only the keyboard plays.
    var device: ControllerDevice? {
        controller.device
    }

    /// The preference key the app-wide controller routing should treat as the stream's.
    var preferredKey: String {
        controller.preferredKey
    }

    /// Stops adopting the first controller that connects as player one.
    func resolve() {
        controller.resolve()
    }

    /// Makes a controller or the keyboard player one.
    ///
    /// - Parameters:
    ///   - chosen: The controller or keyboard.
    ///   - seated: Whether it sits on a couch seat.
    /// - Returns: `true` when player one changes.
    func prefer(_ chosen: ControllerDevice, seated: Bool) -> Bool {
        controller.prefer(chosen, seated: seated)
    }

    /// Forgets player one's controller after it disconnected.
    func disconnect() {
        controller.disconnect()
    }

    /// Applies a changed controls configuration, adjusting the haptics when their preferences changed.
    ///
    /// - Parameter configuration: The configuration.
    /// - Returns: `true` when the haptics must be configured again.
    func reload(_ configuration: ControlsConfiguration) -> Bool {
        let previous = controller.reload(configuration)
        if previous.hapticFeedback != controller.preferences.hapticFeedback {
            return true
        }
        if previous.hapticStrength != controller.preferences.hapticStrength {
            haptics.setGain(controller.preferences.hapticStrength)
        }
        return false
    }

    /// Looks at the free controllers and moves player one when it should.
    ///
    /// - Parameters:
    ///   - devices: The connected controllers that sit on no couch seat.
    ///   - chosen: A controller to adopt, if one was chosen.
    /// - Returns: What changed.
    func choose(from devices: [ControllerDevice], adopting chosen: UInt32?) -> PlayerOneController.Choice {
        controller.choose(from: devices, adopting: chosen)
    }

    /// Makes a controller, or none, player one, and logs and reports the change.
    ///
    /// - Parameters:
    ///   - next: The controller, or `nil` for the keyboard alone.
    ///   - configuration: The controls configuration.
    func adopt(_ next: ControllerDevice?, configuration: ControlsConfiguration) {
        controller.adopt(next, configuration: configuration)
        let message = next.map {
            "selected \"\($0.name)\" over \($0.transport), native waveform haptics "
                + "\(LogFormat.yesNo($0.waveform)), rumble \(LogFormat.yesNo($0.rumble))"
        } ?? "no controller selected; only the keyboard drives the stream"
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(message))
        let current = next?.id
        let report = environment.report
        Task {
            await report(.couch(.playerOneChanged(current)))
        }
    }

    /// Player one's lane: its controller, preferences and the stream's options, keeping the PS button from the
    /// console while it opens the stream menu.
    ///
    /// - Parameters:
    ///   - configuration: The controls configuration.
    ///   - microphone: Whether the stream offers a microphone.
    ///   - surface: The console's touchpad surface.
    ///   - deviceMotion: Whether the device's own motion steers.
    /// - Returns: The lane assignment of pad `0`.
    func lane(
        configuration: ControlsConfiguration,
        microphone: Bool,
        surface: TouchpadSurface,
        deviceMotion: Bool
    ) -> GameInputLane.Assignment {
        GameInputLane.Assignment(
            playerOne: controller.device,
            preferences: controller.preferences,
            configuration: configuration,
            ownsMicrophone: controller.ownsMicrophoneButton(in: configuration, microphone: microphone),
            opensMenuWithSystemButton: environment.coordinator.systemButtonOpensStreamMenu,
            touchSurface: surface,
            deviceMotion: deviceMotion
        )
    }

    /// Routes player one's haptics.
    ///
    /// - Parameters:
    ///   - hasInput: Whether the stream has input.
    ///   - reconfigure: Configures again when a pending route retries.
    func configureFeedback(hasInput: Bool, reconfigure: @escaping @MainActor () -> Void) {
        haptics.configure(
            device: controller.device,
            preferences: controller.preferences,
            hasInput: hasInput,
            isCurrent: { [weak self] id in
                self?.controller.device?.id == id
            },
            reconfigure: reconfigure
        )
    }

    /// Silences player one's haptics.
    func clearFeedback() {
        haptics.clear(device: controller.device, preferences: controller.preferences)
    }

    /// Takes the controller out of waveform mode when the stream ends.
    func endFeedback() {
        haptics.releaseWaveform()
    }

    /// Stops the phone's own rumble.
    func stopPhoneRumble() {
        #if os(iOS)
            rumble.stopPhoneRumble()
        #endif
    }

    /// Checks the input's health once a poll.
    ///
    /// - Parameter phase: The stream input's phase, for the description.
    /// - Returns: `true` when the controllers should be looked at again.
    func checkHealth(phase: StreamInputPhase) -> Bool {
        health.poll(controller: self.describe(phase: phase))
    }

    /// Logs the feedback counters after the controllers were looked at again.
    func logFeedbackCounters() {
        health.logFeedbackCounters()
    }

    /// Forwards the console's feedback and drains the rumble queued for player one.
    ///
    /// - Parameter active: Whether the stream has input.
    func pumpFeedback(active: Bool) {
        rumble.forwardFeedback(device: controller.device, preferences: controller.preferences, active: active)
        let sent = rumble.drain(
            device: controller.device,
            preferences: controller.preferences,
            route: haptics.route,
            active: active
        )
        health.rumbleSent(sent)
    }

    /// Records how late this poll's input was.
    func recordInputDelays() {
        health.recordInputDelays()
    }

    private func describe(phase: StreamInputPhase) -> String {
        controller.device.map {
            "\"\($0.name)\" over \($0.transport), haptics over \(HapticRouter.describe(haptics.route)), "
                + "input \(phase)"
        } ?? "no controller, input \(phase)"
    }

    /// Logs how well a stream's input and feedback keep up: a health report every few seconds, and the native
    /// feedback counters whenever they change.
    @MainActor
    private final class InputHealthMonitor {
        /// How many polls pass between rechecks of the connected controllers.
        static let recheckInterval = 250

        private let environment: InputEnvironment
        private var window = StreamHealthWindow()
        private var polls = 0
        private var lastFeedback = ""

        /// Creates the monitor.
        ///
        /// - Parameter environment: The player whose statistics it reads.
        init(environment: InputEnvironment) {
            self.environment = environment
        }

        /// Counts one input poll and logs a health report when one is due.
        ///
        /// - Parameter controller: Describes player one's controller for the report.
        /// - Returns: `true` on every ``recheckInterval``th poll.
        func poll(controller: @autoclosure () -> String) -> Bool {
            polls += 1
            sample(controller: controller)
            return polls % Self.recheckInterval == 0
        }

        /// Counts rumble updates sent to the controllers.
        ///
        /// - Parameter count: How many were sent.
        func rumbleSent(_ count: Int) {
            for _ in 0 ..< count {
                window.rumbleSent()
            }
        }

        /// Records how long the latest controller input took to reach the stream.
        func recordInputDelays() {
            for delay in environment.pipeline.takeDelays() {
                window.inputSent(delayMicroseconds: delay)
            }
        }

        /// Logs the native feedback counters when they changed since the last log.
        func logFeedbackCounters() {
            let values = environment.player.controllerFeedbackDiagnostics()
            let message = "device=\(values["device"] ?? 0), enabled=\(values["waveformEnabled"] ?? 0), "
                + "rumbleHaptics=\(values["rumbleHaptics"] ?? 0), "
                + "PCM=\(values["buffersReceived"] ?? 0), queued=\(values["reportsQueued"] ?? 0), "
                + "written=\(values["reportsWritten"] ?? 0), failed=\(values["reportsWriteFailed"] ?? 0), "
                + "rumbleCalls=\(values["sourceRumbleCallbacks"] ?? 0), "
                + "sourceCalls=\(values["sourceCallbacks"] ?? 0), "
                + "sourceBytes=\(values["sourceBytes"] ?? 0), "
                + "sourceMalformed=\(values["sourceMalformed"] ?? 0), "
                + "sourceBuffered=\(values["sourceBufferedBytes"] ?? 0), "
                + "sourcePackets=\(values["sourcePacketsTaken"] ?? 0)"
            guard message != lastFeedback else {
                return
            }
            lastFeedback = message
            @Dependency(\.logger) var logger
            logger.enqueue(.diagnostic(.controller, .debug, "Feedback counters: \(message)"))
        }

        private func sample(controller: () -> String) {
            let now = ProcessInfo.processInfo.systemUptime
            guard PlaybackWindowControl.isApplicationActive else {
                window.pause()
                return
            }
            guard window.poll(at: now) else {
                return
            }
            let report = window.report(
                NativeStreamPlayer.statistics(of: environment.player),
                controller: controller(),
                at: now
            )
            @Dependency(\.logger) var logger
            logger.enqueue(.diagnostic(.controller, report.level, report.message))
        }
    }
}
