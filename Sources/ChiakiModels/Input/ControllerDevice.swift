/// A connected controller, or the keyboard and mouse, and what it can do.
public struct ControllerDevice: Equatable, Sendable, Identifiable {
    /// The id reserved for the keyboard and mouse.
    public static let keyboardID = UInt32.max

    /// The keyboard and mouse as a device.
    public static let keyboard = ControllerDevice(
        id: keyboardID, preferenceKey: "keyboard", name: "Keyboard and mouse", transport: "Built in",
        individual: true, rumble: false, lights: false, motion: false, touchpad: false, family: .generic
    )

    /// The input layer's id for the connection.
    public let id: UInt32

    /// The key the device's saved preferences are stored under.
    public let preferenceKey: String

    /// The device's name.
    public let name: String

    /// How it is connected, such as USB or Bluetooth.
    public let transport: String

    /// Whether the device can be told apart from other devices of the same model.
    public let individual: Bool

    /// Whether it has rumble motors.
    public let rumble: Bool

    /// Whether it has a light bar.
    public let lights: Bool

    /// Whether it reports motion.
    public let motion: Bool

    /// Whether it has a touchpad.
    public let touchpad: Bool

    /// Whether it plays waveform haptics.
    public let waveform: Bool

    /// Whether it has adaptive triggers.
    public let adaptiveTriggers: Bool

    /// The maker family.
    public let family: ControllerFamily

    /// Whether it plays HD rumble.
    public let hdRumble: Bool

    /// Creates a device.
    ///
    /// - Parameters:
    ///   - id: The connection id.
    ///   - preferenceKey: The preference key.
    ///   - name: The name.
    ///   - transport: The connection kind.
    ///   - individual: Whether the device is individually identifiable.
    ///   - rumble: Whether it has rumble.
    ///   - lights: Whether it has a light bar.
    ///   - motion: Whether it reports motion.
    ///   - touchpad: Whether it has a touchpad.
    ///   - waveform: Whether it plays waveform haptics.
    ///   - adaptiveTriggers: Whether it has adaptive triggers.
    ///   - family: The maker family.
    ///   - hdRumble: Whether it plays HD rumble.
    public init(id: UInt32, preferenceKey: String, name: String, transport: String,
                individual: Bool, rumble: Bool, lights: Bool, motion: Bool, touchpad: Bool,
                waveform: Bool = false, adaptiveTriggers: Bool = false,
                family: ControllerFamily = .playStation, hdRumble: Bool = false) {
        self.id = id
        self.preferenceKey = preferenceKey
        self.name = name
        self.transport = transport
        self.individual = individual
        self.rumble = rumble
        self.lights = lights
        self.motion = motion
        self.touchpad = touchpad
        self.waveform = waveform
        self.adaptiveTriggers = adaptiveTriggers
        self.family = family
        self.hdRumble = hdRumble
    }

    /// Whether this is the keyboard and mouse.
    public var isKeyboard: Bool {
        id == Self.keyboardID
    }

    /// Whether the console's haptics play natively on the device rather than as rumble.
    public var nativeHaptics: Bool {
        adaptiveTriggers
    }
}

/// The maker family of a controller, which decides its button glyphs.
public enum ControllerFamily: Int, Codable, Equatable, Sendable {
    /// Unknown or generic.
    case generic = 0

    /// A PlayStation controller.
    case playStation = 1

    /// An Xbox controller.
    case xbox = 2

    /// A Nintendo controller.
    case nintendo = 3
}
