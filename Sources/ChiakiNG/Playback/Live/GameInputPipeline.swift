import CInput
import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation
import Video
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Receives raw controller events from the native input listener on its own thread, folds them into per-pad
/// input lanes and forwards each changed controller state to the bound stream player under a lock.
///
/// While a stream's input runs, the pipeline also drives the real-time input clock on ``realTimeQueue``: each
/// tick advances the lanes' time-driven behaviour and then pumps the attached ``RumbleEngine``, independent of
/// the main thread.
final class GameInputPipeline: @unchecked Sendable {
    /// The serial queue, at user-interactive priority, that the real-time input clock, the lanes' time-driven
    /// behaviour and the stream's feedback run on.
    static let realTimeQueue = DispatchSerialQueue(
        label: "io.github.chiaki-ng.input-clock",
        qos: .userInteractive
    )

    /// How often the real-time input clock ticks.
    static let clockInterval = DispatchTimeInterval.milliseconds(4)

    /// How many input-to-submit latency samples are kept until ``takeDelays()`` collects them.
    static let delayCapacity = 256

    /// The main-actor callback that receives in-game actions, such as toggling the touchpad or microphone,
    /// raised by player one's controller.
    typealias Handler = @MainActor @Sendable (GameInputLane.Action) -> Void

    /// The stream player and action handler currently receiving input, tagged with the token returned by
    /// ``GameInputPipeline/bind(player:handler:)``.
    struct Binding {
        /// Identifies this binding so a stale unbind or action delivery is ignored.
        let token: UUID
        /// The live player that receives controller state.
        let player: CNLiveVideoPlayer
        /// The callback for actions raised by player one's controller.
        let handler: Handler
    }

    /// A controller state that was accepted by the player, used to log the first input to reach the stream.
    struct Delivery {
        /// The zero-based pad index the state was sent to.
        let pad: UInt8
        /// The controller state that was sent.
        let state: ControllerState
        /// Whether this is the first state forwarded from the lane's physical device.
        let first: Bool
        /// The display name of the controller assigned to the pad.
        let name: String
    }

    private let lock = NSLock()
    private var binding: Binding?
    private var lanes: [UInt8: GameInputLane] = [:]
    private var motionProcessing = ControllerMotionProcessing.standard
    private var loggedTriggerKinds: [UInt8: [Int]] = [:]
    private var delays: [UInt64] = []
    private var installed = false
    private var routes: [(device: UInt32, pad: UInt8)] = []
    private var pads: [UInt8] = []
    private var dirtyPads: [UInt8] = []
    private var batchActions: [GameInputLane.Action] = []
    private var batchTriggerChanges: [(pad: UInt8, value: Int32)] = []
    private var clock: DispatchSourceTimer?
    private var clockLeases: Set<UUID> = []
    private var feedback: RumbleEngine?

    /// Creates the pipeline with its per-batch buffers reserved, so handling events allocates nothing.
    init() {
        routes.reserveCapacity(8)
        pads.reserveCapacity(8)
        dirtyPads.reserveCapacity(8)
        batchActions.reserveCapacity(8)
        batchTriggerChanges.reserveCapacity(8)
        delays.reserveCapacity(Self.delayCapacity)
    }

    /// Starts the real-time input clock unless it already runs, and holds it running until the returned lease
    /// is passed to ``stopClock(_:)``.
    /// - Returns: The lease that keeps the clock running.
    func startClock() -> UUID {
        lock.lock()
        defer {
            lock.unlock()
        }
        let lease = UUID()
        clockLeases.insert(lease)
        guard clock == nil else {
            return lease
        }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: Self.realTimeQueue)
        timer.schedule(deadline: .now(), repeating: Self.clockInterval, leeway: .microseconds(50))
        timer.setEventHandler { [weak self] in
            self?.realTimeTick()
        }
        timer.activate()
        clock = timer
        return lease
    }

    /// Releases a lease on the real-time input clock and stops the clock once no lease holds it.
    /// - Parameter lease: A lease returned by ``startClock()``; unknown leases are ignored.
    func stopClock(_ lease: UUID) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard clockLeases.remove(lease) != nil, clockLeases.isEmpty else {
            return
        }
        clock?.cancel()
        clock = nil
    }

    /// Makes an engine the one the real-time input clock pumps after each tick, replacing any earlier one.
    /// - Parameter engine: The stream's feedback engine.
    func attach(feedback engine: RumbleEngine) {
        lock.lock()
        feedback = engine
        lock.unlock()
    }

    /// Stops pumping an engine, provided it is still the attached one.
    /// - Parameter engine: The engine passed to ``attach(feedback:)``.
    func detach(feedback engine: RumbleEngine) {
        lock.lock()
        if feedback === engine {
            feedback = nil
        }
        lock.unlock()
    }

    /// Registers the pipeline as the native input event listener, doing nothing after the first call.
    func install() {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !installed else {
            return
        }
        installed = true
        nx_input_set_listener({ events, count, context in
            guard let events, let context, count > 0 else {
                return
            }
            let pipeline = Unmanaged<GameInputPipeline>.fromOpaque(context).takeUnretainedValue()
            pipeline.handle(UnsafeBufferPointer(start: events, count: Int(count)))
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Binds a stream player and action handler, clearing all lanes, latency samples and motion settings from
    /// any previous binding.
    /// - Parameters:
    ///   - player: The player that receives controller state.
    ///   - handler: The callback for actions raised by player one.
    /// - Returns: A token that must be passed to ``GameInputPipeline/unbind(_:)``.
    func bind(player: CNLiveVideoPlayer, handler: @escaping Handler) -> UUID {
        let token = UUID()
        lock.lock()
        binding = Binding(token: token, player: player, handler: handler)
        lanes = [:]
        rebuildRoutes()
        delays.removeAll(keepingCapacity: true)
        motionProcessing = .standard
        loggedTriggerKinds = [:]
        lock.unlock()
        return token
    }

    /// Sends a neutral state to every pad and drops the binding, provided the token still matches the current
    /// binding.
    /// - Parameter token: The token returned by ``GameInputPipeline/bind(player:handler:)``.
    func unbind(_ token: UUID) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard binding?.token == token else {
            return
        }
        for pad in pads {
            neutral(pad)
        }
        lanes = [:]
        rebuildRoutes()
        binding = nil
    }

    /// Assigns a controller or virtual source to a pad, keeping the lane's state when the device is unchanged
    /// and otherwise neutralising the pad and starting a fresh lane.
    /// - Parameters:
    ///   - pad: The zero-based pad index.
    ///   - assignment: The device and settings that drive the pad.
    ///   - live: Whether the lane should forward its state to the stream immediately.
    func assign(pad: UInt8, _ assignment: GameInputLane.Assignment, live: Bool) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard binding != nil else {
            return
        }
        if var lane = lanes[pad], lane.assignment.device == assignment.device {
            lane.update(assignment)
            _ = lane.setLive(live)
            lanes[pad] = lane
            rebuildRoutes()
            submit(pad)
            return
        }
        neutral(pad)
        var lane = GameInputLane(assignment)
        lane.motion.configure(motionProcessing)
        if let previous = lanes[pad] {
            lane.last = previous.last
        }
        _ = lane.setLive(live)
        lanes[pad] = lane
        rebuildRoutes()
        submit(pad)
    }

    /// Neutralises a pad and removes its lane.
    /// - Parameter pad: The zero-based pad index to release.
    func release(pad: UInt8) {
        lock.lock()
        defer {
            lock.unlock()
        }
        neutral(pad)
        lanes[pad] = nil
        rebuildRoutes()
    }

    /// Pauses or resumes forwarding for a pad, sending its current state on resume and a neutral state on
    /// pause.
    /// - Parameters:
    ///   - pad: The zero-based pad index.
    ///   - live: Whether the pad should forward input.
    func setLive(pad: UInt8, _ live: Bool) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard lanes[pad]?.setLive(live) == true else {
            return
        }
        if live {
            submit(pad)
        } else {
            neutral(pad)
        }
    }

    /// Advances time-driven lane behaviour, such as touch gestures, stick gyro taps and right-stick turning,
    /// and resubmits any pad whose state changed.
    func tick() {
        lock.lock()
        defer {
            lock.unlock()
        }
        let now = nx_input_now_us()
        for pad in pads where lanes[pad]?.tick(at: now) == true {
            submit(pad)
        }
    }

    /// Replaces the on-screen overlay input mixed into a pad's state and resubmits it when it changed.
    /// - Parameters:
    ///   - pad: The zero-based pad index.
    ///   - overlay: The overlay input to merge with the physical controller.
    func setOverlay(pad: UInt8, _ overlay: GameInputLane.Overlay) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard lanes[pad]?.overlay != overlay else {
            return
        }
        lanes[pad]?.overlay = overlay
        submit(pad)
    }

    /// Returns the last controller state the player accepted for a pad.
    /// - Parameter pad: The zero-based pad index.
    /// - Returns: The last sent state, or a neutral state when the pad has no lane.
    func lastSent(pad: UInt8) -> ControllerState {
        lock.lock()
        defer {
            lock.unlock()
        }
        return lanes[pad]?.last ?? ControllerState()
    }

    /// Clears a pad's accumulated input and resubmits its resulting state.
    /// - Parameter pad: The zero-based pad index.
    func resetInput(pad: UInt8) {
        lock.lock()
        defer {
            lock.unlock()
        }
        lanes[pad]?.reset()
        submit(pad)
    }

    /// Returns and clears the input-to-submit latency samples gathered for player one.
    /// - Returns: The delays in microseconds since the last call.
    func takeDelays() -> [UInt64] {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !delays.isEmpty else {
            return []
        }
        let taken = delays
        delays.removeAll(keepingCapacity: true)
        return taken
    }

    private func handle(_ events: UnsafeBufferPointer<nx_input_event>) {
        lock.lock()
        guard let binding, !lanes.isEmpty else {
            lock.unlock()
            return
        }
        dirtyPads.removeAll(keepingCapacity: true)
        batchActions.removeAll(keepingCapacity: true)
        batchTriggerChanges.removeAll(keepingCapacity: true)
        var earliest: UInt64?
        for event in events {
            guard let pad = pad(for: event.instance) else {
                continue
            }
            if event.kind == ControllerInputEvent.triggerState {
                noteTriggerState(event, pad: pad)
            }
            guard let outcome = lanes[pad]?.apply(event) else {
                continue
            }
            if outcome.changed, !dirtyPads.contains(pad) {
                dirtyPads.append(pad)
            }
            if pad == 0 {
                batchActions.append(contentsOf: outcome.actions)
                if outcome.changed, event.kind != ControllerInputEvent.sensor, event.timestamp_us > 0 {
                    earliest = min(earliest ?? event.timestamp_us, event.timestamp_us)
                }
            }
        }
        dirtyPads.sort()
        var firstDeliveries: [Delivery] = []
        for pad in dirtyPads {
            guard let delivery = submit(pad) else {
                continue
            }
            if delivery.first {
                firstDeliveries.append(delivery)
            }
            if pad == 0, let earliest, delays.count < Self.delayCapacity {
                delays.append(nx_input_now_us() &- earliest)
            }
        }
        let actions = batchActions.isEmpty
            ? []
            : batchActions
        let triggerChanges = batchTriggerChanges.isEmpty
            ? []
            : batchTriggerChanges
        lock.unlock()
        report(firstDeliveries, actions: actions, binding: binding)
        logTriggerChanges(triggerChanges)
    }

    private func realTimeTick() {
        dispatchPrecondition(condition: .onQueue(Self.realTimeQueue))
        tick()
        lock.lock()
        let engine = feedback
        lock.unlock()
        engine?.assumeIsolated { engine in
            engine.pump()
        }
    }

    private func rebuildRoutes() {
        routes.removeAll(keepingCapacity: true)
        pads.removeAll(keepingCapacity: true)
        for (pad, lane) in lanes {
            pads.append(pad)
            if let device = lane.assignment.device {
                routes.append((device: device, pad: pad))
            }
        }
        pads.sort()
        routes.sort { $0.pad < $1.pad }
    }

    private func pad(for device: UInt32) -> UInt8? {
        for route in routes where route.device == device {
            return route.pad
        }
        return nil
    }

    @discardableResult
    private func submit(_ pad: UInt8) -> Delivery? {
        guard let lane = lanes[pad], lane.live, let player = binding?.player else {
            return nil
        }
        let state = lane.state()
        guard state.differsForConsole(from: lane.last) else {
            return nil
        }
        guard player.send(ControllerSampleWriter.sample(of: state), pad: Int(pad)) else {
            return nil
        }
        lanes[pad]?.last = state
        let first = lane.assignment.device != nil && !lane.forwarded
        if first {
            lanes[pad]?.forwarded = true
        }
        return Delivery(pad: pad, state: state, first: first, name: lane.assignment.name)
    }

    private func neutral(_ pad: UInt8) {
        guard let lane = lanes[pad], let player = binding?.player else {
            return
        }
        let state = ControllerState()
        guard state.differsForConsole(from: lane.last) else {
            return
        }
        if player.send(ControllerSampleWriter.sample(of: state), pad: Int(pad)) {
            lanes[pad]?.last = state
        }
    }
}

extension GameInputPipeline {
    /// Logs the first state forwarded from each controller and dispatches player one's actions to the
    /// binding's handler on the main queue, dropping them if the binding has since changed.
    /// - Parameters:
    ///   - deliveries: The states the player accepted in this batch.
    ///   - actions: The in-game actions raised by player one.
    ///   - binding: The binding that was current when the batch was processed.
    func report(_ deliveries: [Delivery], actions: [GameInputLane.Action], binding: Binding) {
        for delivery in deliveries where delivery.first {
            let event = LogEvent.controllerInputReachedStream(
                player: Int(delivery.pad) + 1,
                controller: delivery.name
            )
            @Dependency(\.logger) var logger
            logger.enqueue(event)
        }
        guard !actions.isEmpty else {
            return
        }
        let token = binding.token
        let handler = binding.handler
        DispatchQueue.main.async { [weak self] in
            guard self?.isBound(token) == true else {
                return
            }
            MainActor.assumeIsolated {
                for action in actions {
                    handler(action)
                }
            }
        }
    }

    /// Reports whether the given token belongs to the current binding.
    /// - Parameter token: A token returned by ``GameInputPipeline/bind(player:handler:)``.
    /// - Returns: `true` when that binding is still active.
    func isBound(_ token: UUID) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return binding?.token == token
    }

    /// Records an adaptive trigger state report for logging when its trigger kinds differ from the last ones
    /// logged for its pad; callers must hold the lock.
    /// - Parameters:
    ///   - event: A trigger state event from the native listener.
    ///   - pad: The pad the event's controller drives.
    func noteTriggerState(_ event: nx_input_event, pad: UInt8) {
        let kinds = ControllerTriggerStates(reported: event.value).map {
            [$0.leftKind, $0.rightKind]
        } ?? []
        guard loggedTriggerKinds[pad] != kinds else {
            return
        }
        loggedTriggerKinds[pad] = kinds
        batchTriggerChanges.append((pad: pad, value: event.value))
    }

    /// Writes a controller diagnostic describing each changed adaptive trigger state.
    /// - Parameter changes: The pad and raw trigger value for each change.
    func logTriggerChanges(_ changes: [(pad: UInt8, value: Int32)]) {
        for change in changes {
            let message = "player \(Int(change.pad) + 1) "
                + (ControllerTriggerStates(reported: change.value)?.description
                    ?? "trigger states are left to the console")
            @Dependency(\.logger) var logger
            logger.enqueue(.controllerDiagnostic(message))
        }
    }

    /// Resets motion tracking and recentres stick gyro on every lane.
    func resetMotion() {
        lock.lock()
        defer {
            lock.unlock()
        }
        for pad in pads {
            lanes[pad]?.motion.reset()
            lanes[pad]?.recentreStickGyro()
        }
    }

    /// Replaces the motion tracker of every lane driven by a device, using the current motion processing
    /// settings.
    /// - Parameter device: The SDL instance id of the controller whose motion restarted.
    func restartMotion(device: UInt32) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for pad in pads where lanes[pad]?.assignment.device == device {
            let tracker = ControllerMotionTracker()
            tracker.configure(motionProcessing)
            lanes[pad]?.motion = tracker
        }
    }

    /// Feeds the host device's own motion sensors into player one when that lane accepts device motion, then
    /// resubmits it.
    /// - Parameters:
    ///   - gyro: Angular velocity in controller axes.
    ///   - accel: Acceleration in controller axes.
    ///   - timestamp: The sample time in microseconds.
    func deviceMotion(gyro: SIMD3<Float>, accel: SIMD3<Float>, at timestamp: UInt64) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard lanes[0]?.acceptsDeviceMotion == true else {
            return
        }
        lanes[0]?.feedDeviceMotion(gyro: gyro, accel: accel, at: timestamp)
        submit(0)
    }

    /// Applies new motion processing settings to every current lane and to lanes created later.
    /// - Parameter processing: The motion filtering and calibration settings.
    func process(motion processing: ControllerMotionProcessing) {
        lock.lock()
        defer {
            lock.unlock()
        }
        motionProcessing = processing
        for lane in lanes.values {
            lane.motion.configure(processing)
        }
    }
}
