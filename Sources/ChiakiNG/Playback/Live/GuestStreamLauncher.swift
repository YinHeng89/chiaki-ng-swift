import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiClientsLive
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation
import Video

/// Prepares and runs the player for joining another player's console as a Kakusan guest.
///
/// The Kakusan guest events the native session reports become `ChiakiModels/StreamSessionEvent/guest(_:)`
/// events in the same ordered stream as the player's own.
@MainActor
final class GuestStreamLauncher {
    private let controls: StreamPlayerControls
    private let inputs: InputServices

    /// Creates the launcher.
    ///
    /// - Parameters:
    ///   - controls: The player controls each guest player attaches to.
    ///   - inputs: The app's controller services each guest player's input runs over.
    nonisolated init(controls: StreamPlayerControls, inputs: InputServices) {
        self.controls = controls
        self.inputs = inputs
    }

    /// Joins a shared game.
    ///
    /// - Parameters:
    ///   - configuration: The invitation.
    ///   - opener: Opens the live session once the player exists.
    /// - Throws: `ChiakiModels/StreamFailure/kakusan(_:)` with why the shared game failed.
    func launch(
        _ configuration: KakusanGuestConfiguration,
        opening opener: StreamSessionOpener
    ) async throws(StreamFailure) {
        @Dependency(\.settings) var settingsStore
        let settings = StreamSettingsLoader(settings: settingsStore)
        let inputConfiguration: ControlsConfiguration
        do {
            inputConfiguration = try await settings.controls()
        } catch {
            throw .kakusan(.internal)
        }
        guard !opener.isStopped, !Task.isCancelled else {
            return
        }
        let player: NativeStreamPlayer
        do {
            player = try NativeStreamPlayer(inputs: inputs)
        } catch {
            throw .kakusan(.internal)
        }
        Self.log(.info, "Joining a shared game")
        let session = opener.open(player)
        let input = player.makeInput(
            configuration: inputConfiguration,
            touchpadSurface: .ps5,
            consoleHaptics: false
        )
        follow(session, player: player, input: input)
        player.apply(await settings.sound(), audio3DAvailable: false)
        @Dependency(\.kakusanGuestDesk) var desk
        desk.open(session.id.uuid, player: player.native)
        controls.attach(player)
        defer {
            input.stop()
            desk.close(player.native)
            controls.detach(player)
        }
        await settings.configureInternetConnection(player.native)
        let end: KakusanGuestEnd? = await NativeStreamDiagnostics.run(player: player.native) {
            await session.run(rest: false) { done in
                player.native.startKakusanGuest(withInvitation: configuration.invitation.text) { outcome in
                    done(KakusanGuestEnd(outcome.pointee))
                }
            }
        }
        guard let end, !opener.isStopped else {
            return
        }
        try finish(end, diagnostics: player.native.failureDiagnostics)
    }

    private func follow(_ session: LiveStreamSession, player: NativeStreamPlayer, input: StreamInputSession) {
        session.relay.observe { [weak session] signal in
            guard case .event(.firstFrame) = signal else {
                return
            }
            input.start()
            session?.report(.guest(.firstFrame))
            Self.log(.info, "First shared video frame presented")
        }
        player.native.kakusanEventHandler = { [weak session] native, text in
            let read = KakusanEventReader.event(of: native.pointee, text: text)
            MainActor.assumeIsolated {
                guard let event = read.guestEvent else {
                    return
                }
                session?.report(.guest(event))
            }
        }
    }

    private func finish(_ end: KakusanGuestEnd, diagnostics: String?) throws(StreamFailure) {
        switch end {
        case .failed(let error):
            Self.log(.error, "The shared game failed: \(error.rawValue). \(diagnostics ?? "")")
            throw .kakusan(error)
        case .finished:
            Self.log(.info, "The shared game ended")
        case .cancelled:
            Self.log(.info, "The shared game was cancelled")
        }
    }

    private static func log(_ level: LogLevel, _ message: String) {
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.playback, level, message))
    }
}
