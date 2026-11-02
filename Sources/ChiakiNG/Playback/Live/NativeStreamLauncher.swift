import ChiakiClients
import ChiakiClientsLive
import ChiakiModels

/// The app's `ChiakiClients/StreamLauncher`: hands each source to the launcher for its kind of stream.
@MainActor
final class NativeStreamLauncher: StreamLauncher {
    private let console: ConsoleStreamLauncher
    private let cloud: CloudStreamLauncher
    private let guest: GuestStreamLauncher

    /// Creates the launcher.
    ///
    /// - Parameters:
    ///   - controls: The player controls each stream's player attaches to.
    ///   - captures: Saves the captures a PS5 cloud console uploads.
    ///   - inputs: The app's controller services each stream's input runs over.
    nonisolated init(controls: StreamPlayerControls, captures: CloudCaptureSaver, inputs: InputServices) {
        console = ConsoleStreamLauncher(controls: controls, inputs: inputs)
        cloud = CloudStreamLauncher(controls: controls, captures: captures, inputs: inputs)
        guest = GuestStreamLauncher(controls: controls, inputs: inputs)
    }

    /// Prepares the player for a source and runs it until it ends.
    ///
    /// - Parameters:
    ///   - source: What to stream.
    ///   - opener: Opens the live session once the player exists.
    /// - Throws: Why the stream failed.
    func launch(_ source: StreamSource, opening opener: StreamSessionOpener) async throws(StreamFailure) {
        switch source {
        case .console(let target, let route):
            try await console.launch(target, route: route, opening: opener)
        case .cloud(let request):
            try await cloud.launch(request, opening: opener)
        case .guest(let configuration):
            try await guest.launch(configuration, opening: opener)
        }
    }
}
