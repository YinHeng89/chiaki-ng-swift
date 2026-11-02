import CInput
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation
import Synchronization
import Video

/// Plays the console's rumble and trigger feedback on player one's and every couch seat's controller.
///
/// The driver lives on the main actor and records what the feedback reaches: player one's controller, its
/// preferences and haptic route, and the seated controllers. Mixing and sending happen in ``RumbleEngine`` on
/// the real-time input clock of ``GameInputPipeline``, so a stalled main thread never delays rumble. Every
/// change the driver makes reaches the engine in the order it was made.
@MainActor
final class RumbleDriver {
    private nonisolated let engine: RumbleEngine
    private nonisolated let pipeline: GameInputPipeline
    #if os(iOS)
        private let phoneRumble: PhoneRumble
    #endif
    private var postedPlayerOne = RumbleEngine.PlayerOne()
    private var postedSeats: [UInt8: RumbleEngine.Seat] = [:]
    private var postedSeatsActive = false

    /// Creates the driver and attaches its engine to the real-time input clock.
    ///
    /// - Parameter environment: The player and controllers it drives.
    init(environment: InputEnvironment) {
        #if os(iOS)
            phoneRumble = environment.phoneRumble
            engine = RumbleEngine(
                console: RumbleEngine.Console(player: environment.player),
                backend: environment.backend,
                phoneRumble: environment.phoneRumble
            )
        #else
            engine = RumbleEngine(
                console: RumbleEngine.Console(player: environment.player),
                backend: environment.backend
            )
        #endif
        pipeline = environment.pipeline
        pipeline.attach(feedback: engine)
    }

    deinit {
        pipeline.detach(feedback: engine)
    }

    /// The strength a controller's rumble plays at.
    ///
    /// - Parameters:
    ///   - preferences: The controller's preferences.
    ///   - device: The controller.
    ///   - console: The intensity the console asked for.
    /// - Returns: The rumble strength scaled for the console's intensity.
    nonisolated static func strength(
        for preferences: ControllerPreferences,
        device: ControllerDevice,
        console: ConsoleFeedbackIntensity
    ) -> Double {
        preferences.rumbleStrength * console.softwareScale(for: device)
    }

    /// Silences player one's mix and lets Bluetooth haptics play again.
    func silence() {
        post { engine in
            engine.silence()
        }
    }

    /// Stops the phone's own rumble when the stream ends.
    func stopPhoneRumble() {
        #if os(iOS)
            phoneRumble.stop()
        #endif
    }

    /// Lets Bluetooth haptics play again after the haptic route changed.
    func resetHandoff() {
        post { engine in
            engine.resetHandoff()
        }
    }

    /// Stops the haptic rumble once haptics no longer play over the rumble motors.
    ///
    /// - Parameter device: Player one's controller.
    func hapticsLeftMotors(device: ControllerDevice?) {
        post { engine in
            engine.hapticsLeftMotors(device: device)
        }
    }

    /// Quiets the rumble motors once haptics play over USB audio.
    ///
    /// - Parameters:
    ///   - device: Player one's controller.
    ///   - preferences: Its preferences, whose trigger strength limits the console's trigger intensity.
    func quietForUSBAudio(device: ControllerDevice, preferences: ControllerPreferences) {
        post { engine in
            engine.quietForUSBAudio(device: device, preferences: preferences)
        }
    }

    /// Gives a newly routed seat the silenced mix its pad had, or a fresh one.
    ///
    /// - Parameter pad: The seat's pad.
    func seat(_ pad: UInt8) {
        post { engine in
            engine.seat(pad)
        }
    }

    /// Forgets a pad's mix once no controller sits on it.
    ///
    /// - Parameter pad: The pad.
    func vacate(_ pad: UInt8) {
        post { engine in
            engine.vacate(pad)
        }
    }

    /// Silences a seat's mix.
    ///
    /// - Parameter pad: The seat's pad.
    func silenceSeat(_ pad: UInt8) {
        post { engine in
            engine.silenceSeat(pad)
        }
    }

    /// Records where player one's rumble goes and reports how many rumble updates the engine sent since the
    /// last call.
    ///
    /// The engine sends the rumble itself on every tick of the real-time input clock; this call only passes it
    /// a change of controller, preferences, route or input focus.
    ///
    /// - Parameters:
    ///   - device: Player one's controller.
    ///   - preferences: Its preferences.
    ///   - route: Where its haptics play.
    ///   - active: Whether the stream has input.
    /// - Returns: How many rumble updates reached the controller since the previous call.
    func drain(
        device: ControllerDevice?,
        preferences: ControllerPreferences,
        route: CNHapticRoute,
        active: Bool
    ) -> Int {
        follow(RumbleEngine.PlayerOne(device: device, preferences: preferences, route: route, active: active))
        return engine.sentUpdates.exchange(0, ordering: .relaxed)
    }

    /// Records where the console's trigger and extended feedback for player one goes; the engine forwards it on
    /// every tick of the real-time input clock.
    ///
    /// - Parameters:
    ///   - device: Player one's controller.
    ///   - preferences: Its preferences.
    ///   - active: Whether the stream has input.
    func forwardFeedback(device: ControllerDevice?, preferences: ControllerPreferences, active: Bool) {
        follow(RumbleEngine.PlayerOne(
            device: device,
            preferences: preferences,
            route: postedPlayerOne.route,
            active: active
        ))
    }

    /// Records the couch seats whose rumble and trigger feedback the engine sends on every tick of the
    /// real-time input clock.
    ///
    /// - Parameters:
    ///   - seats: The seats by pad.
    ///   - active: Whether the seats' controllers reach the stream.
    func drainSeats(_ seats: [UInt8: SeatedController], active: Bool) {
        guard active != postedSeatsActive || !matchesPostedSeats(seats) else {
            return
        }
        var next: [UInt8: RumbleEngine.Seat] = [:]
        for (pad, seat) in seats {
            next[pad] = RumbleEngine.Seat(device: seat.device, preferences: seat.preferences)
        }
        postedSeats = next
        postedSeatsActive = active
        let posted = next
        post { engine in
            engine.follow(seats: posted, active: active)
        }
    }

    private func follow(_ next: RumbleEngine.PlayerOne) {
        guard next != postedPlayerOne else {
            return
        }
        postedPlayerOne = next
        post { engine in
            engine.follow(next)
        }
    }

    private func matchesPostedSeats(_ seats: [UInt8: SeatedController]) -> Bool {
        guard seats.count == postedSeats.count else {
            return false
        }
        return seats.allSatisfy { pad, seat in
            postedSeats[pad] == RumbleEngine.Seat(device: seat.device, preferences: seat.preferences)
        }
    }

    private func post(_ change: @escaping @Sendable (isolated RumbleEngine) -> Void) {
        let engine = engine
        GameInputPipeline.realTimeQueue.async {
            engine.assumeIsolated(change)
        }
    }
}

/// Mixes and sends the console's rumble and trigger feedback on the real-time input clock.
///
/// The engine runs on ``GameInputPipeline/realTimeQueue``: ``GameInputPipeline`` calls ``pump()`` on every tick
/// after the lanes' time-driven input, and ``RumbleDriver`` passes it every change of controller, route and
/// seat in order on the same queue. Nothing here waits or touches the interface; the phone's own rumble is
/// handed to the main actor.
actor RumbleEngine {
    /// The console feedback source the engine reads: a stream player whose rumble slots, haptic levels and
    /// feedback reports are atomics or guarded by the player's own lock, so they are safe to drain from the
    /// real-time queue.
    struct Console: @unchecked Sendable {
        /// The stream's player.
        let player: CNLiveVideoPlayer
    }

    /// Where player one's feedback goes.
    struct PlayerOne: Equatable, Sendable {
        /// Player one's controller.
        var device: ControllerDevice?
        /// Its preferences.
        var preferences = ControllerPreferences()
        /// Where its haptics play.
        var route = CNHapticRoute.none
        /// Whether the stream has input.
        var active = false
    }

    /// A couch seat's controller and preferences, as far as its feedback needs them.
    struct Seat: Equatable, Sendable {
        /// The seat's controller.
        let device: ControllerDevice
        /// The controller's preferences.
        let preferences: ControllerPreferences
    }

    /// How many rumble updates reached player one's controller since ``RumbleDriver`` last asked.
    nonisolated let sentUpdates = Atomic<Int>(0)

    private let console: Console
    private let backend: SDLControllerBackend
    #if os(iOS)
        private let phoneRumble: PhoneRumble
    #endif
    private var mix = RumbleMix()
    private var seatMixes: [UInt8: RumbleMix] = [:]
    private var hdPacer = HDRumblePacer()
    private var handoff = WaveformHandoff.haptics
    private var consoleTriggers: [UInt32: [UInt8]] = [:]
    private var playerOne = PlayerOne()
    private var seats: [UInt8: Seat] = [:]
    private var seatsActive = false

    #if os(iOS)
        /// Creates the engine.
        ///
        /// - Parameters:
        ///   - console: The stream's feedback source.
        ///   - backend: The controllers the feedback plays on.
        ///   - phoneRumble: The phone's own rumble, used when no controller is connected.
        init(console: Console, backend: SDLControllerBackend, phoneRumble: PhoneRumble) {
            self.console = console
            self.backend = backend
            self.phoneRumble = phoneRumble
        }
    #else
        /// Creates the engine.
        ///
        /// - Parameters:
        ///   - console: The stream's feedback source.
        ///   - backend: The controllers the feedback plays on.
        init(console: Console, backend: SDLControllerBackend) {
            self.console = console
            self.backend = backend
        }
    #endif

    /// Runs the engine on the real-time input queue.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        GameInputPipeline.realTimeQueue.asUnownedSerialExecutor()
    }

    /// Forwards player one's trigger feedback, sends player one's rumble and then every seat's, for one tick of
    /// the real-time input clock.
    func pump() {
        forwardPlayerOneFeedback()
        sentUpdates.wrappingAdd(drainPlayerOne(), ordering: .relaxed)
        drainSeats()
    }

    /// Takes a change of player one's controller, preferences, route or input focus.
    ///
    /// - Parameter next: Where player one's feedback now goes.
    func follow(_ next: PlayerOne) {
        playerOne = next
    }

    /// Takes a change of the couch seats.
    ///
    /// - Parameters:
    ///   - next: The seats by pad.
    ///   - active: Whether the seats' controllers reach the stream.
    func follow(seats next: [UInt8: Seat], active: Bool) {
        seats = next
        seatsActive = active
    }

    /// Silences player one's mix and lets Bluetooth haptics play again.
    func silence() {
        handoff = .haptics
        mix.silence()
    }

    /// Lets Bluetooth haptics play again after the haptic route changed.
    func resetHandoff() {
        handoff = .haptics
    }

    /// Stops the haptic rumble once haptics no longer play over the rumble motors.
    ///
    /// - Parameter device: Player one's controller.
    func hapticsLeftMotors(device: ControllerDevice?) {
        mix.setHaptics(.off)
        stopHDRumble(device: device)
    }

    /// Quiets the rumble motors once haptics play over USB audio.
    ///
    /// - Parameters:
    ///   - device: Player one's controller.
    ///   - preferences: Its preferences, whose trigger strength limits the console's trigger intensity.
    func quietForUSBAudio(device: ControllerDevice, preferences: ControllerPreferences) {
        mix.silence()
        backend.rumble(
            device,
            level: .off,
            console: consoleIntensity().limited(by: preferences.triggerStrength)
        )
    }

    /// Gives a newly routed seat the silenced mix its pad had, or a fresh one.
    ///
    /// - Parameter pad: The seat's pad.
    func seat(_ pad: UInt8) {
        var latched = seatMixes[pad] ?? RumbleMix()
        latched.silence()
        seatMixes[pad] = latched
    }

    /// Forgets a pad's mix once no controller sits on it.
    ///
    /// - Parameter pad: The pad.
    func vacate(_ pad: UInt8) {
        seatMixes[pad] = nil
    }

    /// Silences a seat's mix.
    ///
    /// - Parameter pad: The seat's pad.
    func silenceSeat(_ pad: UInt8) {
        seatMixes[pad]?.silence()
    }

    private func consoleIntensity() -> ConsoleFeedbackIntensity {
        var haptic: UInt8 = 1
        var trigger: UInt8 = 1
        console.player.consoleFeedbackIntensityHaptic(&haptic, trigger: &trigger)
        return ConsoleFeedbackIntensity(haptic: haptic, trigger: trigger)
    }

    private func forwardPlayerOneFeedback() {
        guard let packet = console.player.controllerFeedback(), playerOne.active,
              let device = playerOne.device else {
            return
        }
        forward(packet, to: device.id, preferences: playerOne.preferences)
    }

    private func drainPlayerOne() -> Int {
        var left: UInt8 = 0
        var right: UInt8 = 0
        let now = ProcessInfo.processInfo.systemUptime
        let consoleChanged = console.player.takeRumbleLeft(&left, right: &right)
        if consoleChanged {
            mix.setConsole(left: left, right: right, at: now)
        }
        let preferences = playerOne.preferences
        let route = playerOne.route
        guard playerOne.active, let device = playerOne.device else {
            #if os(iOS)
                if playerOne.active, consoleChanged {
                    playPhoneRumble(left: left, right: right, strength: preferences.rumbleStrength)
                }
            #endif
            return 0
        }
        var sent = 0
        let intensity = consoleIntensity()
        let scale = intensity.softwareScale(for: device)
        if route == .rumble, device.hdRumble, mix.console(at: now, strength: 1) == .off {
            sent += drainHDRumble(device, preferences: preferences, scale: scale, at: now)
            mix.setHaptics(.off)
        } else if route == .rumble {
            stopHDRumble(device: device)
            var low: Float = 0
            var high: Float = 0
            console.player.takeHapticRumbleLow(&low, high: &high, scale: Float(scale))
            mix.setHaptics(RumbleLevel(hapticLow: low, hapticHigh: high))
        }
        guard let level = mix.next(at: now, strength: RumbleDriver.strength(
            for: preferences,
            device: device,
            console: intensity
        )) else {
            return sent
        }
        guard route == .bluetoothReports else {
            backend.rumble(
                device,
                level: level,
                console: intensity.limited(by: preferences.triggerStrength)
            )
            return sent + 1
        }
        let next = handoff.sending(level)
        if handoff == .haptics, next == .consoleRumble {
            _ = nx_input_waveform_mode(device.id, false)
        }
        backend.rumble(device, level: level, console: intensity)
        if handoff == .consoleRumble, next == .haptics {
            _ = nx_input_waveform_mode(device.id, true)
        }
        handoff = next
        return sent + 1
    }

    #if os(iOS)
        private func playPhoneRumble(left: UInt8, right: UInt8, strength: Double) {
            let phoneRumble = phoneRumble
            Task { @MainActor in
                phoneRumble.play(left: left, right: right, strength: strength)
            }
        }
    #endif

    private func drainSeats() {
        guard !seats.isEmpty else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let intensity = consoleIntensity()
        for (pad, seat) in seats {
            if let packet = console.player.controllerFeedback(forPad: Int(pad)), seatsActive,
               seat.device.adaptiveTriggers {
                forward(packet, to: seat.device.id, preferences: seat.preferences)
            }
            var left: UInt8 = 0
            var right: UInt8 = 0
            if console.player.takeRumble(forPad: Int(pad), left: &left, right: &right) {
                seatMixes[pad]?.setConsole(left: left, right: right, at: now)
            }
            guard seatsActive else {
                continue
            }
            let strength = RumbleDriver.strength(
                for: seat.preferences,
                device: seat.device,
                console: intensity
            )
            if let level = seatMixes[pad]?.next(at: now, strength: strength) {
                backend.rumble(
                    seat.device,
                    level: level,
                    console: intensity.limited(by: seat.preferences.triggerStrength)
                )
            }
        }
    }

    private func forward(_ packet: Data, to id: UInt32, preferences: ControllerPreferences) {
        guard let effects = backend.extendedFeedback(id, packet: packet, preferences: preferences) else {
            return
        }
        let modes = [effects[0], effects[11]]
        guard consoleTriggers[id] != modes else {
            return
        }
        consoleTriggers[id] = modes
        let describe = { (mode: UInt8, parameters: ArraySlice<UInt8>) in
            String(format: "mode 0x%02x ", mode) + parameters.map(String.init).joined(separator: " ")
        }
        let message = "console trigger effects: L2 \(describe(effects[0], effects[1...10])), "
            + "R2 \(describe(effects[11], effects[12...21]))"
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(message))
    }

    private func drainHDRumble(
        _ device: ControllerDevice,
        preferences: ControllerPreferences,
        scale: Double,
        at now: TimeInterval
    ) -> Int {
        var left: Float = 0
        var right: Float = 0
        console.player.takeHapticRumbleLeft(&left, right: &right, scale: Float(scale))
        let tone = HDRumbleTone(left: left, right: right).scaled(by: preferences.rumbleStrength)
        let link: HDRumblePacer.Link = device.transport == "USB"
            ? .usb
            : .bluetooth
        guard let send = hdPacer.next(tone, at: now, over: link) else {
            return 0
        }
        backend.hdRumble(device.id, tone: send)
        return 1
    }

    private func stopHDRumble(device: ControllerDevice?) {
        guard let silent = hdPacer.stop(), let device else {
            return
        }
        backend.hdRumble(device.id, tone: silent)
    }
}

/// Whether a controller playing Bluetooth haptic reports has handed its motors to the console's rumble.
enum WaveformHandoff: Equatable {
    /// The controller plays the haptic waveform.
    case haptics
    /// The controller plays the console's rumble.
    case consoleRumble

    /// The handoff after sending a rumble level.
    ///
    /// - Parameter level: The level sent.
    /// - Returns: ``consoleRumble`` while the console rumbles, otherwise ``haptics``.
    func sending(_ level: RumbleLevel) -> WaveformHandoff {
        level == .off
            ? .haptics
            : .consoleRumble
    }
}
