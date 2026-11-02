/// How strongly a controller plays adaptive trigger effects, never above the intensity set on the PS5.
public enum TriggerStrength: String, Codable, CaseIterable, Equatable, Sendable {
    /// The PS5's own intensity.
    case strong

    /// Medium, or the PS5's intensity when that is weaker.
    case medium

    /// Weak, or the PS5's intensity when that is weaker.
    case weak

    /// The trigger intensity to apply: the weaker of the PS5's and this choice.
    ///
    /// The console's levels run from 1 for strong to 3 for weak; 0 means off and stays off.
    ///
    /// - Parameter level: The console's trigger intensity level; only the low two bits are read.
    /// - Returns: The level to send to the controller.
    public func applied(toConsoleLevel level: UInt8) -> UInt8 {
        let console = level & 3
        guard console != 0 else {
            return 0
        }
        return max(console, self.level)
    }

    private var level: UInt8 {
        switch self {
        case .strong:
            1
        case .medium:
            2
        case .weak:
            3
        }
    }
}
