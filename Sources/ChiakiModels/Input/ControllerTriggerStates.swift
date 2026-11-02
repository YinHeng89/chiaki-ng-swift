/// The adaptive trigger effect states a controller reports for L2 and R2.
public struct ControllerTriggerStates: Equatable, Sendable {
    /// The bit that marks a packed report as carrying trigger states.
    public static let reportedFlag: Int32 = 0x10000

    /// The L2 state.
    public var left: UInt8

    /// The R2 state.
    public var right: UInt8

    /// Creates states.
    ///
    /// - Parameters:
    ///   - left: The L2 state.
    ///   - right: The R2 state.
    public init(left: UInt8, right: UInt8) {
        self.left = left
        self.right = right
    }

    /// Unpacks a report: L2 in the low byte, R2 in the next, flagged by ``reportedFlag``.
    ///
    /// - Parameter value: The packed report.
    public init?(reported value: Int32) {
        guard value & Self.reportedFlag != 0 else {
            return nil
        }
        left = UInt8(truncatingIfNeeded: value)
        right = UInt8(truncatingIfNeeded: value >> 8)
    }

    /// The readable name of a state.
    ///
    /// - Parameter state: The state value.
    /// - Returns: The name, or `unknown`.
    public static func name(_ state: UInt8) -> String {
        switch state {
        case 0:
            "off"
        case 1:
            "feedback standby"
        case 2:
            "feedback active"
        case 3:
            "weapon standby"
        case 4:
            "weapon pulling"
        case 5:
            "weapon fired"
        case 6:
            "vibration standby"
        case 7:
            "vibration active"
        default:
            "unknown"
        }
    }

    /// Both states as one log phrase.
    public var description: String {
        "L2 trigger \(Self.name(left)), R2 trigger \(Self.name(right))"
    }

    /// The L2 effect kind, see ``kind(_:)``.
    public var leftKind: Int {
        Self.kind(left)
    }

    /// The R2 effect kind, see ``kind(_:)``.
    public var rightKind: Int {
        Self.kind(right)
    }

    /// Groups a state by effect: 0 off, 1 feedback, 2 weapon, 3 vibration, 4 unknown.
    ///
    /// - Parameter state: The state value.
    /// - Returns: The effect kind.
    public static func kind(_ state: UInt8) -> Int {
        switch state {
        case 0:
            0
        case 1...2:
            1
        case 3...5:
            2
        case 6...7:
            3
        default:
            4
        }
    }
}
