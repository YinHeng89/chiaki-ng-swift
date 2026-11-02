/// Whether any saved account is signed in to PlayStation Network, which decides the settings that apply.
public enum PSNReach: Equatable, Sendable {
    /// Only account id profiles are saved, so only local play is possible.
    case localOnly

    /// At least one saved account is signed in to PlayStation Network.
    case signedIn
}
