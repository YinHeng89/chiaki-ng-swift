/// Quitting the app, as a finite state machine.
///
/// ```
/// running --requested--> stopping --completed(same id)--> ready
/// ```
public enum Termination: Hashable, Sendable {
    /// The app runs.
    case running

    /// Streams and sessions are being stopped before the app quits; only this shutdown's id completes it.
    case stopping(OperationID)

    /// Everything stopped; the app may quit.
    case ready
}
