/// Whether a playing stream hears from the console.
///
/// ```
/// receiving --five seconds pass with nothing from the console--> waiting
/// waiting --anything arrives, a reconnection starts or the session resets--> receiving
/// ```
public enum StreamConnection: Equatable, Sendable {
    /// The console's traffic arrives.
    case receiving

    /// Nothing has arrived for five seconds; the session waits up to its silence limit before it reconnects or
    /// ends.
    case waiting
}
