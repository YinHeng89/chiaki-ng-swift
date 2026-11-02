import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiClientsLive
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import Foundation
import PlatformUI
import Video

/// Prepares and runs the player for a stream from a paired console.
///
/// It loads the pairing, picks the route, applies the saved picture, sound and connection settings, starts
/// the session's input and Kakusan hosting, and runs the native console start until it ends.
@MainActor
final class ConsoleStreamLauncher {
    private let controls: StreamPlayerControls
    private let inputs: InputServices
    private let recent = RecentConsoleSessions()

    /// Creates the launcher.
    ///
    /// - Parameters:
    ///   - controls: The player controls each console player attaches to.
    ///   - inputs: The app's controller services each console player's input runs over.
    nonisolated init(controls: StreamPlayerControls, inputs: InputServices) {
        self.controls = controls
        self.inputs = inputs
    }

    private struct Connection {
        let target: PlayTarget
        let overInternet: Bool
        let remotePicture: Bool
    }

    private struct Video {
        let profile: StreamProfile
        let codec: PictureSettings.Codec
    }

    /// Runs a console stream.
    ///
    /// - Parameters:
    ///   - console: The paired console.
    ///   - route: The route the user asked for.
    ///   - opener: Opens the live session once the player exists.
    /// - Throws: Why the stream failed; nothing once the session was stopped.
    func launch(
        _ console: ConsoleStreamTarget,
        route: ConsoleRoute,
        opening opener: StreamSessionOpener
    ) async throws(StreamFailure) {
        @Dependency(\.kakusanHostDesk) var hosting
        @Dependency(\.settings) var settingsStore
        @Dependency(\.accountService) var accountService
        let target: PlayTarget
        do {
            target = try await accountService.storage().consoles.playTarget(
                profile: console.profile.uuid,
                address: console.address,
                remoteDeviceID: console.remoteDeviceID
            )
        } catch {
            throw .credentials
        }
        guard !opener.isStopped, !Task.isCancelled else {
            return
        }
        let overInternet = await Self.startRoute(asked: route, target: target).overInternet
        guard !opener.isStopped, !Task.isCancelled else {
            return
        }
        @Dependency(\.logger) var logger
        let attempts = PlaybackAttempts(target: target, overInternet: overInternet, logger: logger)
        await attempts.logRoute()
        let player = try NativeStreamPlayer(inputs: inputs)
        let started = ContinuousClock.now
        do {
            try await run(
                player,
                connection: Connection(
                    target: target,
                    overInternet: overInternet,
                    remotePicture: overInternet || route == .internet
                ),
                hosting: hosting,
                opener: opener,
                settings: StreamSettingsLoader(settings: settingsStore)
            )
        } catch {
            guard let outcome = error.outcome, !opener.isStopped else {
                throw error
            }
            await attempts.failed(
                PlaybackAttemptLog.Report(
                    outcome: outcome,
                    message: StreamFailureMessage(error, kind: .console).text,
                    diagnostics: player.native.failureDiagnostics
                ),
                milliseconds: LogFormat.milliseconds(started.duration(to: .now))
            )
            throw error
        }
    }

    private func run(
        _ player: NativeStreamPlayer,
        connection: Connection,
        hosting: KakusanHostDesk?,
        opener: StreamSessionOpener,
        settings: StreamSettingsLoader
    ) async throws(StreamFailure) {
        let ps5 = connection.target.ps5
        let picture = try await settings.picture()
        let route = PictureSettings.Route(remote: await Self.isRemote(
            host: connection.target.address,
            overInternet: connection.remotePicture
        ))
        let session = opener.open(player)
        let console = connection.target.hardwareID
        player.native.consoleJustLeft = recent.justLeft(console)
        player.native.reconnectAfterDrop = await settings.reconnectsAfterDrop()
        controls.attach(player)
        defer {
            recent.finished(console)
            controls.detach(player)
        }
        session.report(.route(connection.overInternet
                ? .internet
                : .home))
        session.report(.pictureRoute(route))
        @Dependency(\.launchPresentation) var launchPresentation
        session.report(.videoFit(launchPresentation.videoFit ?? picture.videoFit))
        let profile = await player.configure(for: picture, ps5: ps5, route: route)
        let sound = await settings.sound()
        player.apply(sound, audio3DAvailable: PlayBridge.supportsAudio3D(
            ps5
                ? .ps5
                : .ps4
        ))
        player.apply(sound.media)
        session.report(.videoDisabled(!sound.media.picture))
        await settings.configureInternetConnection(player.native)
        let input = try await Self.input(for: player, session: session, ps5: ps5, settings: settings)
        let diagnostics = CoreDiagnosticRelay(connection.overInternet
            ? .live
            : .untilFirstFrame)
        observe(session, input: input, console: console, diagnostics: diagnostics)
        hosting?.attach(player.native) { [weak session] in
            session?.isLive ?? false
        }
        defer {
            hosting?.detach(player.native)
            input.stop()
        }
        let video = Self.video(for: picture, profile: profile, ps5: ps5, route: route)
        let report = await start(
            player,
            session: session,
            connection: connection,
            video: video,
            diagnostics: diagnostics
        )
        guard let report, !opener.isStopped else {
            return
        }
        let outcome = report.outcome
        guard outcome == .finished else {
            throw .stream(outcome, overInternet: connection.overInternet)
        }
    }

    private func start(
        _ player: NativeStreamPlayer,
        session: LiveStreamSession,
        connection: Connection,
        video: Video,
        diagnostics: CoreDiagnosticRelay
    ) async -> StreamEndReport? {
        let target = connection.target
        let profile = video.profile
        player.native.setupProgressHandler = { step, elapsed in
            let stage = Int(step.rawValue)
            @Dependency(\.logger) var logger
            logger.enqueue(.remoteSetupProgress(stage: stage, elapsedMilliseconds: elapsed))
        }
        return await NativeStreamDiagnostics.run(player: player.native, relay: diagnostics) {
            await session.run(rest: true) { done in
                player.native.startConsole(
                    forAccount: target.accountID.data,
                    hardwareID: target.hardwareID.data,
                    overInternet: connection.overInternet,
                    ps5: target.ps5,
                    height: profile.height,
                    fps: profile.fps,
                    bitrate: profile.effectiveBitrateMbps * 1000,
                    codec: Self.streamCodec(of: video.codec)
                ) { outcome in
                    done(StreamOutcomeReader.report(of: outcome.pointee))
                }
            }
        }
    }

    private static func video(
        for picture: PictureSettings,
        profile: StreamProfile,
        ps5: Bool,
        route: PictureSettings.Route
    ) -> Video {
        Video(
            profile: profile,
            codec: picture.launchCodec(
                forPS5: ps5,
                route: route,
                displaySupportsHDR: DisplayDynamicRange.supportsHDR
            )
        )
    }

    private static func input(
        for player: NativeStreamPlayer,
        session: LiveStreamSession,
        ps5: Bool,
        settings: StreamSettingsLoader
    ) async throws(StreamFailure) -> StreamInputSession {
        let controls = try await settings.controls()
        player.native.consoleTextEntryEnabled = usesTextEntry(ps5: ps5)
        return player.makeInput(
            configuration: controls,
            touchpadSurface: ps5
                ? .ps5
                : .ps4,
            rawKeyboard: ps5,
            microphone: true
        ) { [weak session] event in
            await MainActor.run {
                session?.report(event)
            }
        }
    }

    private func observe(
        _ session: LiveStreamSession,
        input: StreamInputSession,
        console: HardwareID,
        diagnostics: CoreDiagnosticRelay
    ) {
        let started = ContinuousClock.now
        var attempt = 1
        session.relay.observe { [recent] signal in
            switch signal {
            case .event(.firstFrame):
                recent.began(console)
                input.start()
                let milliseconds = LogFormat.milliseconds(started.duration(to: .now))
                let current = attempt
                Task { @MainActor in
                    await diagnostics.attemptSucceeded()
                    @Dependency(\.logger) var logger
                    await logger.log(.diagnostic(
                        .playback, .info,
                        "First video frame presented \(milliseconds) ms into start attempt \(current)"
                    ))
                }
            case .event(.startRetried(let retry)):
                attempt = retry + 1
                Self.log(.warning, "The core is retrying the start, attempt \(retry + 1)")
            case .event(.reconnecting(let reconnect)):
                Self.log(.warning, "The connection dropped; the core is reconnecting, attempt \(reconnect)")
            case .event(.reconnected):
                Self.log(.info, "The core reconnected the session")
            case .event(.couch(let couch)):
                input.observe(couch)
            case .gameLight(let pad, let color):
                input.gameLight(pad: pad, color: color)
            case .event:
                break
            }
        }
    }

    private static func log(_ level: LogLevel, _ message: String) {
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.playback, level, message))
    }
}

extension ConsoleStreamLauncher {
    /// Whether the console's keyboard is typed through the app's text field rather than sent as keys.
    ///
    /// - Parameter ps5: Whether the console is a PS5.
    /// - Returns: Whether text entry is used.
    static func usesTextEntry(ps5: Bool) -> Bool {
        #if os(iOS)
            true
        #else
            !ps5
        #endif
    }

    private static func startRoute(asked route: ConsoleRoute, target: PlayTarget) async -> ConsoleRoute {
        guard route != .homeOnly else {
            return .home
        }
        return await ConsoleRoute.resolve(internetAsked: route == .internet && target.remoteDeviceID != nil) {
            await ConsoleBridge().route(for: target.accountID, to: target.hardwareID)
        }
    }

    private static func streamCodec(of codec: PictureSettings.Codec) -> CNStreamCodec {
        switch codec {
        case .h264:
            .H264
        case .hevc:
            .HEVC
        case .hevcHDR:
            .HEVCHDR
        }
    }

    private static func isRemote(host: String?, overInternet: Bool) async -> Bool {
        guard !overInternet else {
            return true
        }
        guard let host, await !ConsoleNetworkLocality.isLocal(host) else {
            return false
        }
        log(.info, "\(host) is outside the local network, so the Internet stream settings apply")
        return true
    }
}
