import ChiakiModels
import CInput

/// Turns one physical controller's raw input into the PlayStation controller state sent for one console pad,
/// handling remapping, shortcuts, touchpad emulation and stick gyro.
struct GameInputLane {
    /// A stream-level action triggered by a controller shortcut rather than sent to the console.
    enum Action: Equatable {
        /// Toggle touchpad mode, fired by the touchpad shortcut chord.
        case toggleTouchpad
        /// Toggle the microphone, fired by the controller's mute button when this lane owns the microphone.
        case toggleMicrophone
    }

    /// Input from sources other than the physical controller, such as the keyboard and on-screen touch,
    /// merged into the lane's state.
    struct Overlay: Equatable {
        /// Buttons, triggers and sticks pressed by overlay input; each axis takes whichever of the controller
        /// and overlay is deflected further.
        var keys = ControllerState()
        /// Touchpad touches from overlay input, which take precedence over touches from the controller.
        var touches = ControllerTouchSlots.empty
        /// Whether to hide the controller's own touchpad click while overlay input is using the touchpad.
        var suppressTouchpadClick = false
    }

    /// How a lane is configured: which device it reads, how its input maps to the console and which shortcuts
    /// and gyro features it has.
    struct Assignment {
        /// The input instance id of the controller feeding this lane, or `nil` for a keyboard-only lane.
        let device: UInt32?
        /// The display name of the device feeding this lane, shown when its first input reaches the console.
        let name: String
        /// The mapping from controller and keyboard input to console controls.
        var preset: InputPreset
        /// Per-controller preferences such as dead zone, stick swap, inversion and adaptive triggers.
        var preferences: ControllerPreferences
        /// The button codes that, pressed together, toggle touchpad mode, or `nil` when this lane has no
        /// touchpad shortcut.
        var chord: [Int]?
        /// Whether the mute button toggles the stream microphone instead of being sent to the console.
        var ownsMicrophone: Bool
        /// Whether holding the stream menu chord is swallowed instead of being sent to the console.
        var blocksStreamMenuChord: Bool
        /// Whether the PS button is swallowed instead of being sent to the console, because it opens the
        /// stream menu.
        var blocksSystemButton = false
        /// The controller family, used to translate button layout.
        var family = ControllerFamily.playStation
        /// Whether buttons are matched by position or by printed label.
        var buttonLayout = ButtonLayout.position
        /// The button codes that open the stream menu, released to the console and blocked once they are all
        /// held.
        var streamMenuChord = Set(StreamMenuShortcut.standard.buttons.map(Int32.init))
        /// The button that toggles touchpad emulation on the right stick, or `nil` when none is assigned.
        var touchButton: Int32?
        /// The shape of the touchpad being emulated.
        var touchSurface = TouchpadSurface.ps5
        /// Where motion data comes from: the controller's own sensors or the Mac's device motion.
        var motionSource = MotionSource.controller
        /// The button that engages stick gyro while held, or `nil` when none is assigned.
        var gyroButton: Int32?
        /// The console control pressed while stick gyro is tapping, or `nil` for none.
        var gyroTapTarget: PlayStationControl?
        /// Whether and when the stick drives synthetic gyro motion.
        var stickGyroMode = StickGyroMode.off
    }

    /// What applying an input event produced.
    struct Outcome: Equatable {
        /// Whether the lane's console state may have changed and should be resubmitted.
        var changed = false
        /// Stream-level actions the event triggered.
        var actions: [Action] = []
    }

    /// The button code of the PlayStation mute button, which toggles the stream microphone when the lane owns
    /// it.
    static let microphoneButton: Int32 = 15
    /// The button code of the PS button.
    static let systemButton: Int32 = 5
    /// The absolute axis value past which a stick counts as deflected.
    static let stickThreshold = 8000
    /// The axis indices of the right stick.
    static let rightStick: Set<Int> = [2, 3]

    /// The lane's current configuration; replace it with `update(_:)`.
    private(set) var assignment: Assignment
    /// Whether the lane's input is forwarded to the console; change it with `setLive(_:)`.
    private(set) var live = false
    /// Input from the keyboard and other overlay sources merged into this lane's state.
    var overlay = Overlay()
    /// The controller state most recently sent to the console, used to skip unchanged submissions.
    var last = ControllerState()
    /// Whether this lane has already delivered input from its device to the console.
    var forwarded = false
    /// Accumulates motion samples from the controller or the Mac for the console's gyro and accelerometer.
    var motion = ControllerMotionTracker()
    private var triggerStates: ControllerTriggerStates?
    private var mapper: InputMapper
    private var axes = [Int](repeating: 0, count: 6)
    private var held = Set<Int32>()
    private var blockedButtons = Set<Int32>()
    private var blockedAxes = Set<Int>()
    private var chord: ButtonChordDetector?
    private var touch: TouchButton
    private var stickGyro: StickGyroControl
    private var stickPose = StickGyroPose()
    private var sensorClock: (sensor: UInt64, host: UInt64)?

    /// Creates a lane that is not yet live, configured for an assignment.
    init(_ assignment: Assignment) {
        self.assignment = assignment
        chord = assignment.chord.map(ButtonChordDetector.init(buttons:))
        touch = TouchButton(surface: assignment.touchSurface)
        stickGyro = StickGyroControl(mode: assignment.stickGyroMode)
        mapper = InputMapper(touchSurface: assignment.touchSurface)
    }

    /// Applies a new configuration, resetting mapped input and rebuilding touchpad, chord and stick gyro
    /// state where the relevant settings changed.
    mutating func update(_ next: Assignment) {
        if next.touchButton != assignment.touchButton || next.touchSurface != assignment.touchSurface {
            touch = TouchButton(surface: next.touchSurface)
        }
        if next.buttonLayout != assignment.buttonLayout || next.family != assignment.family {
            held.removeAll()
            blockedButtons.removeAll()
            chord?.reset()
        }
        let gyroButtonChanged = next.gyroButton != assignment.gyroButton
        assignment = next
        settleStickGyro {
            $0.configure(next.stickGyroMode)
            if gyroButtonChanged {
                $0.release()
            }
        }
        mapper.reset()
        mapper.touchSurface = next.touchSurface
        if let buttons = next.chord {
            if chord == nil {
                chord = ButtonChordDetector(buttons: buttons)
            } else {
                chord?.configure(buttons: buttons)
            }
        } else {
            chord = nil
        }
    }

    /// Starts or stops forwarding the lane's input to the console.
    ///
    /// Going live blocks every button and deflected axis that is already held, so input from menus does not
    /// leak into the game until it is released.
    /// - Parameter next: Whether the lane should be live.
    /// - Returns: `true` when the live state changed.
    mutating func setLive(_ next: Bool) -> Bool {
        guard next != live else {
            return false
        }
        live = next
        mapper.reset()
        chord?.reset()
        touch.reset()
        settleStickGyro {
            $0.release()
        }
        if next {
            blockedButtons = held
            blockedAxes = Set(axes.indices.filter { abs(axes[$0]) > Self.stickThreshold })
        } else {
            blockedButtons = []
            blockedAxes = []
        }
        return true
    }

    /// Releases every mapped button, the touchpad chord, emulated touch and stick gyro hold.
    mutating func reset() {
        mapper.reset()
        chord?.reset()
        touch.reset()
        settleStickGyro {
            $0.release()
        }
    }

    /// Advances time-driven behaviour: emulated touchpad gestures, stick gyro taps and stick turning.
    /// - Parameter now: The current time in microseconds.
    /// - Returns: `true` when the lane is live and its state changed.
    mutating func tick(at now: UInt64) -> Bool {
        let touched = touch.tick(at: now)
        let tapped = stickGyro.tick(at: now)
        let turned = turnWithRightStick(at: now)
        return (touched || tapped || turned) && live
    }

    /// Applies one raw controller event to the lane.
    /// - Parameter event: A button, axis, sensor or trigger-state event from the controller.
    /// - Returns: Whether the console state changed and which stream actions were triggered.
    mutating func apply(_ event: nx_input_event) -> Outcome {
        switch event.kind {
        case ControllerInputEvent.button:
            let code = assignment.buttonLayout.code(Int(event.control), family: assignment.family)
            return applyButton(Int32(code), down: event.value != 0, at: event.timestamp_us)
        case ControllerInputEvent.axis:
            return applyAxis(Int(event.control), value: Int(event.value))
        case ControllerInputEvent.sensor:
            guard assignment.motionSource == .controller, !stickGyro.turning else {
                return Outcome()
            }
            motion.accept(event)
            sensorClock = (event.timestamp_us, nx_input_now_us())
            return Outcome(changed: live)
        case ControllerInputEvent.triggerState:
            triggerStates = ControllerTriggerStates(reported: event.value)
            return Outcome(changed: live)
        default:
            return Outcome()
        }
    }

    private mutating func applyButton(_ code: Int32, down: Bool, at now: UInt64) -> Outcome {
        if down {
            held.insert(code)
        } else {
            held.remove(code)
        }
        guard live else {
            return Outcome()
        }
        if blockedButtons.contains(code) {
            if !down {
                blockedButtons.remove(code)
            }
            return Outcome()
        }
        if let shortcut = shortcut(code, down: down) {
            return shortcut
        }
        if let held = pressHoldButton(code, down: down, at: now) {
            return held
        }
        if var detector = chord {
            let fired = detector.button(Int(code), down: down)
            chord = detector
            if fired {
                for button in detector.chord {
                    mapper.press(source: .gamepadButton, code: button, down: false, preset: assignment.preset)
                }
                return Outcome(changed: true, actions: [.toggleTouchpad])
            }
            if down, detector.suppresses(Int(code)) {
                return Outcome()
            }
        }
        mapper.press(source: .gamepadButton, code: Int(code), down: down, preset: assignment.preset)
        return Outcome(changed: true)
    }

    private mutating func applyAxis(_ axis: Int, value: Int) -> Outcome {
        guard axes.indices.contains(axis) else {
            return Outcome()
        }
        axes[axis] = value
        guard live else {
            return Outcome()
        }
        if blockedAxes.contains(axis) {
            if abs(value) < Self.stickThreshold {
                blockedAxes.remove(axis)
            }
            return Outcome()
        }
        if stickGyro.capturesRightStick, gyroAxes.contains(axis) {
            stickGyro.stick(magnitude: gyroStickMagnitude())
        }
        if touch.capturesRightStick, Self.rightStick.contains(axis) {
            touch.stick(x: Double(axes[2]) / 32767, y: Double(axes[3]) / 32767)
        }
        return Outcome(changed: true)
    }

    /// Builds the PlayStation controller state to send to the console, merging mapped controller input,
    /// overlay input, emulated touchpad, stick gyro taps, motion and adaptive trigger state.
    func state() -> ControllerState {
        let effective = axes.indices.map {
            blockedAxes.contains($0) || (touch.capturesRightStick && Self.rightStick.contains($0))
                ? 0
                : axes[$0]
        }
        var state = mapper.state
        state.addRawAxes(effective, preferences: assignment.preferences)
        if stickGyro.capturesRightStick {
            state.rightX = 0
            state.rightY = 0
        }
        if stickGyro.tapping, let tap = assignment.gyroTapTarget {
            Self.press(tap, into: &state)
        }
        let pressed = state.touches
        if overlay.suppressTouchpadClick {
            state.buttons &= ~(PlayStationControl.touchpad.bit ?? 0)
        }
        state.merge(overlay.keys)
        state.touches = overlay.touches
        if state.touches.isEmpty, !pressed.isEmpty {
            state.touches = pressed
            state.buttons |= PlayStationControl.touchpad.bit ?? 0
        }
        if touch.clicking {
            state.buttons |= PlayStationControl.touchpad.bit ?? 0
        }
        if let finger = touch.touch {
            state.touches = ControllerTouchSlots(first: finger)
        }
        state.motion = motion.motion
        if assignment.preferences.adaptiveTriggersEnabled {
            state.triggerStates = triggerStates
        }
        return state
    }
}

extension GameInputLane.Assignment {
    /// The lane for player one: the stream's own controller, or the keyboard when none is chosen.
    ///
    /// - Parameters:
    ///   - device: Player one's controller, or `nil` for the keyboard.
    ///   - preferences: Player one's preferences.
    ///   - configuration: The controls configuration.
    ///   - ownsMicrophone: Whether the controller's microphone button toggles the microphone.
    ///   - opensMenuWithSystemButton: Whether the PS button opens the stream menu instead of reaching the
    ///     console.
    ///   - touchSurface: The console's touchpad surface.
    ///   - deviceMotion: Whether the device's own motion can drive the gyro.
    init(
        playerOne device: ControllerDevice?,
        preferences: ControllerPreferences,
        configuration: ControlsConfiguration,
        ownsMicrophone: Bool,
        opensMenuWithSystemButton: Bool = false,
        touchSurface: TouchpadSurface,
        deviceMotion: Bool
    ) {
        let preset = configuration.preset(
            forPlayer: 0,
            preferences: preferences,
            touchpad: device?.touchpad ?? true,
            gyro: device?.motion ?? true
        )
        self.init(
            device: device?.id,
            name: device?.name ?? "keyboard",
            preset: preset,
            preferences: preferences,
            chord: configuration.touchpadShortcut.buttons,
            ownsMicrophone: ownsMicrophone,
            blocksStreamMenuChord: true,
            blocksSystemButton: opensMenuWithSystemButton,
            family: device?.family ?? .playStation,
            buttonLayout: preferences.buttonLayout,
            streamMenuChord: Set(configuration.streamMenuShortcut.buttons.map(Int32.init)),
            touchButton: Self.touchButton(for: device, preset: preset),
            touchSurface: touchSurface,
            motionSource: MotionSource(
                sensors: device?.motion ?? false,
                deviceMotion: deviceMotion
            ),
            gyroButton: Self.gyroBinding(for: device, preset: preset).map { Int32($0.code) },
            gyroTapTarget: Self.gyroTapTarget(for: device, preset: preset),
            stickGyroMode: preferences.stickGyro.resolved(sensors: device?.motion ?? true)
        )
    }

    /// The lane for a couch seat's controller, using the seated player's own preset when they have one.
    ///
    /// - Parameters:
    ///   - seat: The seat.
    ///   - player: The seated player's index, 0 for player 1.
    ///   - configuration: The controls configuration.
    ///   - touchSurface: The console's touchpad surface.
    init(
        seat: SeatedController,
        player: Int,
        configuration: ControlsConfiguration,
        touchSurface: TouchpadSurface
    ) {
        let device = seat.device
        let preferences = seat.preferences
        let preset = configuration.preset(
            forPlayer: player, preferences: preferences, touchpad: device.touchpad, gyro: device.motion
        )
        self.init(
            device: device.id,
            name: device.name,
            preset: preset,
            preferences: preferences,
            chord: nil,
            ownsMicrophone: false,
            blocksStreamMenuChord: false,
            family: device.family,
            buttonLayout: preferences.buttonLayout,
            touchButton: Self.touchButton(for: device, preset: preset),
            touchSurface: touchSurface,
            motionSource: MotionSource(sensors: device.motion, deviceMotion: false),
            gyroButton: Self.gyroBinding(for: device, preset: preset).map { Int32($0.code) },
            gyroTapTarget: Self.gyroTapTarget(for: device, preset: preset),
            stickGyroMode: preferences.stickGyro.resolved(sensors: device.motion)
        )
    }

    private static func touchButton(for device: ControllerDevice?, preset: InputPreset) -> Int32? {
        guard let device, !device.touchpad else {
            return nil
        }
        return preset.bindings.first {
            $0.source == .gamepadButton && $0.target == .touchpad
        }.map { Int32($0.code) }
    }

    private static func gyroTapTarget(for device: ControllerDevice?,
                                      preset: InputPreset) -> PlayStationControl? {
        guard let hold = gyroBinding(for: device, preset: preset) else {
            return nil
        }
        return preset.bindings.first {
            $0.source == .gamepadButton && $0.code == hold.code && $0.target != .gyroHold
        }?.target
    }

    private static func gyroBinding(for device: ControllerDevice?, preset: InputPreset) -> InputBinding? {
        guard device != nil else {
            return nil
        }
        return preset.bindings.first {
            $0.source == .gamepadButton && $0.target == .gyroHold
        }
    }
}

extension GameInputLane {
    /// Whether the lane takes motion from the Mac rather than the controller, and is not currently
    /// synthesizing it from the stick.
    var acceptsDeviceMotion: Bool {
        assignment.motionSource == .device && !stickGyro.turning
    }

    /// Feeds a motion sample from the Mac's device motion into the lane.
    /// - Parameters:
    ///   - gyro: Angular velocity.
    ///   - accel: Acceleration.
    ///   - timestamp: The sample time in microseconds.
    mutating func feedDeviceMotion(gyro: SIMD3<Float>, accel: SIMD3<Float>, at timestamp: UInt64) {
        motion.feed(gyro: gyro, accel: accel, at: timestamp)
        sensorClock = (timestamp, nx_input_now_us())
    }

    private mutating func settleStickGyro(
        at now: UInt64 = nx_input_now_us(),
        _ change: (inout StickGyroControl) -> Void
    ) {
        let wasTurning = stickGyro.turning
        change(&stickGyro)
        if wasTurning, !stickGyro.turning {
            stickPose.pause()
            motion.feed(gyro: SIMD3<Float>(), accel: stickPose.gravity, at: sensorTime(now))
        }
    }

    private mutating func turnWithRightStick(at now: UInt64) -> Bool {
        guard stickGyro.turning else {
            return false
        }
        let stick = gyroStick()
        let rates = touch.capturesRightStick
            ? SIMD3<Float>()
            : StickGyro.rates(x: stick.x, y: stick.y, inverted: assignment.preferences.invertRightY)
        let sample = stickPose.turn(rates, at: now)
        motion.feed(gyro: sample.gyro, accel: sample.gravity, at: sensorTime(now))
        return true
    }

    private func sensorTime(_ now: UInt64) -> UInt64 {
        guard let sensorClock else {
            return now
        }
        return sensorClock.sensor &+ (now &- sensorClock.host)
    }

    /// Resets the stick gyro pose so the current orientation becomes centred.
    mutating func recentreStickGyro() {
        stickPose.recentre()
    }

    private var gyroAxes: ClosedRange<Int> {
        assignment.preferences.swapSticks
            ? 0...1
            : 2...3
    }

    private func gyroStickMagnitude() -> Double {
        let stick = gyroStick()
        let x = Double(stick.x) / 32767
        let y = Double(stick.y) / 32767
        return (x * x + y * y).squareRoot()
    }

    private func gyroStick() -> (x: Int16, y: Int16) {
        let first = gyroAxes.lowerBound
        let value = { (axis: Int) in
            blockedAxes.contains(axis)
                ? 0
                : InputMapper.calibrated(axes[axis], deadZone: assignment.preferences.deadZone)
        }
        return (value(first), value(first + 1))
    }

    private mutating func pressHoldButton(_ code: Int32, down: Bool, at now: UInt64) -> Outcome? {
        if code == assignment.gyroButton, stickGyro.mode == .whileHeld {
            let magnitude = gyroStickMagnitude()
            settleStickGyro(at: now) {
                $0.hold(down: down, at: now)
                $0.stick(magnitude: magnitude)
            }
            return Outcome(changed: true)
        }
        if code == assignment.touchButton {
            return pressTouchButton(down: down, at: now)
        }
        return nil
    }

    private static func press(_ control: PlayStationControl, into state: inout ControllerState) {
        switch control {
        case .leftTrigger:
            state.leftTrigger = .max
        case .rightTrigger:
            state.rightTrigger = .max
        default:
            state.buttons |= control.bit ?? 0
        }
    }

    private mutating func shortcut(_ code: Int32, down: Bool) -> Outcome? {
        let chord = assignment.streamMenuChord
        if down, assignment.blocksStreamMenuChord, chord.contains(code), held.isSuperset(of: chord) {
            for button in chord {
                blockedButtons.insert(button)
                mapper.press(
                    source: .gamepadButton,
                    code: Int(button),
                    down: false,
                    preset: assignment.preset
                )
            }
            return Outcome(changed: true)
        }
        if code == Self.systemButton, assignment.blocksSystemButton {
            return Outcome()
        }
        guard code == Self.microphoneButton, assignment.ownsMicrophone else {
            return nil
        }
        return Outcome(actions: down
            ? [.toggleMicrophone]
            : [])
    }

    private mutating func pressTouchButton(down: Bool, at now: UInt64) -> Outcome {
        let captured = touch.capturesRightStick
        touch.press(down: down, at: now)
        if captured, !touch.capturesRightStick {
            blockedAxes.formUnion(Self.rightStick.filter { abs(axes[$0]) > Self.stickThreshold })
        }
        if down, touch.capturesRightStick {
            touch.stick(x: Double(axes[2]) / 32767, y: Double(axes[3]) / 32767)
        }
        return Outcome(changed: true)
    }
}
