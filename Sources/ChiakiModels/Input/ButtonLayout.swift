/// Whether face buttons are matched by position or by printed label.
public enum ButtonLayout: String, Codable, CaseIterable, Sendable {
    /// By position: the bottom button is always Cross.
    case position

    /// By label: on a Nintendo controller, A and B and X and Y swap.
    case label

    /// The gamepad button code to look bindings up with.
    ///
    /// - Parameters:
    ///   - code: The button code the controller reported.
    ///   - family: The controller's family.
    /// - Returns: The code, with the face buttons swapped for a Nintendo controller in ``label`` layout.
    public func code(_ code: Int, family: ControllerFamily) -> Int {
        guard self == .label, family == .nintendo else {
            return code
        }
        switch code {
        case 0:
            return 1
        case 1:
            return 0
        case 2:
            return 3
        case 3:
            return 2
        default:
            return code
        }
    }
}
