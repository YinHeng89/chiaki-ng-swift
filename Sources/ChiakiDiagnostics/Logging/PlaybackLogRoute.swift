/// How a stream reaches its console or cloud host, as written in playback attempt logs.
public enum PlaybackLogRoute: String, Sendable {
    /// A console on the local network.
    case localCore = "Local console, new core"

    /// A console reached over the internet.
    case remoteCore = "Remote console, new core"

    /// A PS Cloud session.
    case psCloudCore = "PS Cloud, new core"

    /// A PS Now session.
    case psNowCore = "PSNow, new core"
}
