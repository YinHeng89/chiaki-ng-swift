import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import Dependencies
import Foundation
import Observation
import Video

/// The `--diagnose-playback` run: streams the one saved console for up to 20 seconds and reports the frames
/// it decoded.
@MainActor
@Observable
final class PlaybackDiagnostic {
    /// The video view while the diagnostic stream plays.
    private(set) var surface: StreamSurface?

    @ObservationIgnored @Dependency(\.streamLeases) private var leases
    @ObservationIgnored @Dependency(\.streamSession) private var client
    @ObservationIgnored @Dependency(\.consoles) private var consoles

    /// Creates the diagnostic over the installed stream session client and its leases.
    init() {}

    /// Runs the diagnostic stream.
    ///
    /// - Returns: The line printed for the run.
    func run() async -> String {
        let saved: [RegistrationFlow.Registration]
        do {
            saved = try await consoles.pairings().get().map(RegistrationFlow.Registration.init)
        } catch {
            return "Playback diagnostic failed before native session startup."
        }
        guard saved.count == 1, let entry = saved.first else {
            return "Playback diagnostic needs exactly one saved pairing."
        }
        let id = StreamSessionID()
        let route: ConsoleRoute = entry.console.remoteDeviceID == nil
            ? .home
            : .internet
        let source = StreamFeature.source(
            account: entry.profileID,
            console: entry.console,
            route: route == .internet
                ? .remote
                : .local
        )
        let timeout = Task {
            try await Task.sleep(for: .seconds(20))
            _ = await client.leave(id, .disconnect)
        }
        defer {
            timeout.cancel()
        }
        var decoded = 0
        do {
            for try await event in client.start(id, source) {
                if case .presented(let surface) = event {
                    self.surface = surface
                }
                if let player = leases.session(id)?.player as? NativeStreamPlayer {
                    decoded = Int(player.native.decodedFrames)
                }
            }
        } catch let failure as StreamFailure {
            return StreamFailureMessage(failure, kind: .console).text.english
        } catch {
            return "Playback diagnostic failed before native session startup."
        }
        surface = nil
        let transport = route == .internet
            ? "PSN"
            : "LAN"
        return "Playback diagnostic decoded \(decoded) frames over \(transport)."
    }
}
