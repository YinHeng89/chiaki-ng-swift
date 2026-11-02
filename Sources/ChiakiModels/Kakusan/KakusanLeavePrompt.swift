/// Whether the guest is being asked to confirm leaving a session.
public enum KakusanLeavePrompt: Equatable, Sendable {
    /// No prompt is shown.
    case hidden
    /// The prompt asks whether to leave.
    case confirming
}
