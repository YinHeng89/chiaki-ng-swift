/// A control on a PlayStation controller that an input can be bound to.
///
/// The declaration order of the first sixteen cases is the console's button bit order; ``bit`` depends on it.
/// The raw values are the persisted binding targets.
public enum PlayStationControl: String, Codable, CaseIterable, Sendable {
    /// Cross.
    case cross

    /// Circle.
    case circle

    /// Square.
    case square

    /// Triangle.
    case triangle

    /// D-pad left.
    case left

    /// D-pad right.
    case right

    /// D-pad up.
    case dpadUp = "up"

    /// D-pad down.
    case down

    /// L1.
    case leftShoulder = "l1"

    /// R1.
    case rightShoulder = "r1"

    /// L3, the left stick press.
    case leftStickButton = "l3"

    /// R3, the right stick press.
    case rightStickButton = "r3"

    /// Options.
    case options

    /// Share or Create.
    case share

    /// The touchpad click.
    case touchpad

    /// The PS button.
    case system = "ps"

    /// L2, fully pressed.
    case leftTrigger = "l2"

    /// R2, fully pressed.
    case rightTrigger = "r2"

    /// Left stick pushed left.
    case leftStickLeft

    /// Left stick pushed right.
    case leftStickRight

    /// Left stick pushed up.
    case leftStickUp

    /// Left stick pushed down.
    case leftStickDown

    /// Right stick pushed left.
    case rightStickLeft

    /// Right stick pushed right.
    case rightStickRight

    /// Right stick pushed up.
    case rightStickUp

    /// Right stick pushed down.
    case rightStickDown

    /// A touch on the left half of the touchpad.
    case touchpadLeft

    /// A touch on the right half of the touchpad.
    case touchpadRight

    /// Hold to steer with gyro.
    case gyroHold

    /// The label shown for the control.
    public var label: String {
        switch self {
        case .touchpadLeft:
            "Touchpad left"
        case .touchpadRight:
            "Touchpad right"
        case .gyroHold:
            "Gyro (hold)"
        case .left, .right, .dpadUp, .down:
            "D-pad " + rawValue
        case .leftStickLeft:
            "Left stick left"
        case .leftStickRight:
            "Left stick right"
        case .leftStickUp:
            "Left stick up"
        case .leftStickDown:
            "Left stick down"
        case .rightStickLeft:
            "Right stick left"
        case .rightStickRight:
            "Right stick right"
        case .rightStickUp:
            "Right stick up"
        case .rightStickDown:
            "Right stick down"
        case .leftShoulder, .leftTrigger, .leftStickButton, .rightShoulder, .rightTrigger, .rightStickButton,
             .system:
            rawValue.uppercased()
        default:
            rawValue.capitalized
        }
    }

    /// The console button bit, for the sixteen controls that are buttons.
    public var bit: UInt32? {
        guard let index = Self.allCases.firstIndex(of: self), index < 16 else {
            return nil
        }
        return 1 << index
    }

    /// The touchpad half a touch control presses.
    public var touchpadRegion: TouchpadRegion? {
        switch self {
        case .touchpadLeft:
            .left
        case .touchpadRight:
            .right
        default:
            nil
        }
    }
}
