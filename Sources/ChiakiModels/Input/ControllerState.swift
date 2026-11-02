/// One snapshot of a controller's buttons, triggers, sticks, touches and motion, in console units.
public struct ControllerState: Equatable, Sendable {
    /// The pressed buttons as console button bits.
    public var buttons: UInt32 = 0

    /// The left trigger, 0 to 255.
    public var leftTrigger: UInt8 = 0

    /// The right trigger, 0 to 255.
    public var rightTrigger: UInt8 = 0

    /// The left stick's horizontal position.
    public var leftX: Int16 = 0

    /// The left stick's vertical position, positive downwards.
    public var leftY: Int16 = 0

    /// The right stick's horizontal position.
    public var rightX: Int16 = 0

    /// The right stick's vertical position, positive downwards.
    public var rightY: Int16 = 0

    /// The touchpad contacts.
    public var touches = ControllerTouchSlots.empty

    /// The motion reading, when the device reports one.
    public var motion: ControllerMotion?

    /// The adaptive trigger states the device reported, when it reports them.
    public var triggerStates: ControllerTriggerStates?

    /// Creates an idle state.
    public init() {
    }

    /// Adds another source's buttons, triggers and sticks: the buttons combine, and each trigger and stick
    /// keeps whichever value is stronger.
    ///
    /// - Parameter extra: The other source.
    public mutating func merge(_ extra: ControllerState) {
        buttons |= extra.buttons
        leftTrigger = max(leftTrigger, extra.leftTrigger)
        rightTrigger = max(rightTrigger, extra.rightTrigger)
        leftX = Self.stronger(leftX, extra.leftX)
        leftY = Self.stronger(leftY, extra.leftY)
        rightX = Self.stronger(rightX, extra.rightX)
        rightY = Self.stronger(rightY, extra.rightY)
    }

    /// Adds a controller's raw sticks and triggers to the state its bindings produced.
    ///
    /// - Parameters:
    ///   - axes: The six raw axes: left stick, right stick, left trigger and right trigger.
    ///   - preferences: The controller's dead zone, stick swap and inversion.
    public mutating func addRawAxes(_ axes: [Int], preferences: ControllerPreferences) {
        let raw = axes.map { InputMapper.calibrated($0, deadZone: preferences.deadZone) }
        let left = preferences.swapSticks
            ? 2
            : 0
        let right = preferences.swapSticks
            ? 0
            : 2
        leftX = Self.stronger(leftX, raw[left])
        leftY = Self.stronger(leftY, raw[left + 1])
        rightX = Self.stronger(rightX, raw[right])
        rightY = Self.stronger(rightY, preferences.invertRightY
            ? -raw[right + 1]
            : raw[right + 1])
        leftTrigger = max(leftTrigger, UInt8(max(0, min(255, axes[4] * 255 / 32767))))
        rightTrigger = max(rightTrigger, UInt8(max(0, min(255, axes[5] * 255 / 32767))))
    }

    /// Whether this state is worth sending to the console after `other`.
    ///
    /// Everything but motion must match exactly; motion counts as unchanged inside the deadband.
    ///
    /// - Parameters:
    ///   - other: The state last sent.
    ///   - deadband: How far motion may drift before it counts as a change.
    /// - Returns: `true` when the console should receive this state.
    public func differsForConsole(
        from other: ControllerState,
        deadband: ControllerMotion.Deadband = .standard
    ) -> Bool {
        var withoutMotion = self
        var otherWithoutMotion = other
        withoutMotion.motion = nil
        otherWithoutMotion.motion = nil
        guard withoutMotion == otherWithoutMotion else {
            return true
        }
        switch (motion, other.motion) {
        case (nil, nil):
            return false
        case (let current?, let previous?):
            return !current.isWithin(deadband, of: previous)
        default:
            return true
        }
    }

    private static func stronger(_ first: Int16, _ second: Int16) -> Int16 {
        abs(Int(first)) >= abs(Int(second))
            ? first
            : second
    }
}

/// One motion reading: angular velocity, acceleration and orientation.
public struct ControllerMotion: Equatable, Sendable {
    /// How far each motion component may drift before a reading counts as changed.
    public struct Deadband: Equatable, Sendable {
        /// The deadband used unless a caller chooses another.
        public static let standard = Deadband(gyro: 0.01, accel: 0.01, orientation: 0.003)

        /// The largest ignored change in angular velocity.
        public var gyro: Float

        /// The largest ignored change in acceleration.
        public var accel: Float

        /// The largest ignored change in an orientation component.
        public var orientation: Float

        /// Creates a deadband.
        ///
        /// - Parameters:
        ///   - gyro: The ignored angular velocity change.
        ///   - accel: The ignored acceleration change.
        ///   - orientation: The ignored orientation change.
        public init(gyro: Float, accel: Float, orientation: Float) {
            self.gyro = gyro
            self.accel = accel
            self.orientation = orientation
        }
    }

    /// The angular velocity.
    public var gyro: SIMD3<Float>

    /// The acceleration.
    public var accel: SIMD3<Float>

    /// The orientation quaternion.
    public var orientation: SIMD4<Float>

    /// Creates a reading.
    ///
    /// - Parameters:
    ///   - gyro: The angular velocity.
    ///   - accel: The acceleration.
    ///   - orientation: The orientation quaternion.
    public init(gyro: SIMD3<Float>, accel: SIMD3<Float>, orientation: SIMD4<Float>) {
        self.gyro = gyro
        self.accel = accel
        self.orientation = orientation
    }

    /// Whether every component is within the deadband of another reading.
    ///
    /// - Parameters:
    ///   - deadband: The allowed drift.
    ///   - other: The reading to compare with.
    /// - Returns: `true` when nothing moved beyond the deadband.
    public func isWithin(_ deadband: Deadband, of other: ControllerMotion) -> Bool {
        let gyroDelta = Self.largest(gyro - other.gyro)
        let accelDelta = Self.largest(accel - other.accel)
        let orientationDelta = Self.largest(orientation - other.orientation)
        return gyroDelta <= deadband.gyro && accelDelta <= deadband.accel
            && orientationDelta <= deadband.orientation
    }

    private static func largest<Vector: SIMD>(_ delta: Vector) -> Float where Vector.Scalar == Float {
        max(delta.max(), (-delta).max())
    }
}

/// Where the console's motion data comes from.
public enum MotionSource: Equatable, Sendable {
    /// The controller's own sensors.
    case controller

    /// The device's sensors, for a controller without them.
    case device

    /// Chooses the source.
    ///
    /// - Parameters:
    ///   - sensors: Whether the controller has motion sensors.
    ///   - deviceMotion: Whether device motion is turned on.
    public init(sensors: Bool, deviceMotion: Bool) {
        self = sensors || !deviceMotion
            ? .controller
            : .device
    }
}

/// One touchpad contact in console touchpad units.
public struct ControllerTouch: Equatable, Sendable {
    /// The 7-bit contact id; it stays the same while the finger is down.
    public var id: UInt8

    /// The horizontal position.
    public var x: UInt16

    /// The vertical position.
    public var y: UInt16

    /// Creates a contact.
    ///
    /// - Parameters:
    ///   - id: The contact id.
    ///   - x: The horizontal position.
    ///   - y: The vertical position.
    public init(id: UInt8, x: UInt16, y: UInt16) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// The console touchpad's two contact slots.
public struct ControllerTouchSlots: Equatable, Sendable {
    /// No contacts.
    public static let empty = ControllerTouchSlots()

    /// The first contact.
    public var first: ControllerTouch?

    /// The second contact.
    public var second: ControllerTouch?

    /// Creates the slots.
    ///
    /// - Parameters:
    ///   - first: The first contact.
    ///   - second: The second contact.
    public init(first: ControllerTouch? = nil, second: ControllerTouch? = nil) {
        self.first = first
        self.second = second
    }

    /// Whether neither slot holds a contact.
    public var isEmpty: Bool {
        first == nil && second == nil
    }

    /// The ids of the held contacts.
    public var ids: Set<UInt8> {
        Set([first?.id, second?.id].compactMap(\.self))
    }
}
