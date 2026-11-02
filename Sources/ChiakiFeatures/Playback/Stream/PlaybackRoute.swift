/// The route the user asked a console stream to take.
public enum PlaybackRoute: Equatable, Sendable {
    /// On the local network.
    case local

    /// Over the internet.
    case remote
}
