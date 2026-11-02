import ChiakiClients
import ChiakiClientsLive
import ChiakiModels
@testable import ChiakiNG

/// The test process's one composition over its scratch location, so the process-wide core opens once.
@MainActor
enum TestComposition {
    /// The composition over `UserData.current`, with the real database client.
    static let scratch = AppComposition(userData: .current, database: .liveValue)

    /// A stream launcher over the scratch composition's player controls, capture saver and input services.
    ///
    /// - Returns: The launcher.
    static func launcher() -> NativeStreamLauncher {
        NativeStreamLauncher(
            controls: scratch.playerControls,
            captures: scratch.cloudCaptures,
            inputs: scratch.input
        )
    }
}
