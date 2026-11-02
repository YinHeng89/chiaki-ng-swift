/// Why a controls configuration or an input operation was refused.
public enum InputFailure: Error, Equatable {
    /// A value in the configuration is out of range or inconsistent.
    case invalidConfiguration

    /// Two bindings in a preset share an input or a target.
    case duplicateBinding

    /// The input system is unavailable.
    case unavailable
}
