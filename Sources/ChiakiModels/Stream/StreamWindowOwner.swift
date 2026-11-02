/// Which feature controls the window presentation while a stream runs, so only one of them drives full
/// screen.
public enum StreamWindowOwner: Equatable, Sendable {
    /// The stream feature enters and leaves full screen as streaming starts and stops.
    case stream
    /// The launch flow owns the window, so the stream feature leaves it alone.
    case launch
}
