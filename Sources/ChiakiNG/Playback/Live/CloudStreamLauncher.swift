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
import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking

/// Prepares and runs the player for a PlayStation cloud stream.
///
/// It applies the saved cloud picture, sound and datacenter settings, reports the launch's datacenter offer
/// and selection as session events, starts the input and runs the native cloud start until it ends. While it
/// runs on PS5 cloud, the PS and Create buttons belong to the cloud console's gestures, and the captures the console
/// uploads are saved to this device as the cloud picture settings ask.
@MainActor
final class CloudStreamLauncher {
    private struct Start {
        let account: Data
        let request: CloudStreamRequest
        let video: CloudVideoRequest
    }

    private let controls: StreamPlayerControls
    private let captures: CloudCaptureSaver
    private let inputs: InputServices

    /// Creates the launcher.
    ///
    /// - Parameters:
    ///   - controls: The player controls each cloud player attaches to.
    ///   - captures: Saves the captures the console uploads.
    ///   - inputs: The app's controller services each cloud player's input runs over.
    nonisolated init(controls: StreamPlayerControls, captures: CloudCaptureSaver, inputs: InputServices) {
        self.controls = controls
        self.captures = captures
        self.inputs = inputs
    }

    /// Runs a cloud stream.
    ///
    /// - Parameters:
    ///   - request: The title and profile.
    ///   - opener: Opens the live session once the player exists.
    /// - Throws: Why the stream failed; nothing once the session was stopped.
    func launch(_ request: CloudStreamRequest,
                opening opener: StreamSessionOpener) async throws(StreamFailure) {
        @Dependency(\.settings) var settingsStore
        @Dependency(\.accountService) var accountService
        let settings = StreamSettingsLoader(settings: settingsStore)
        let account = try await Self.account(request.profile, in: accountService)
        let picture = try await settings.cloudPicture()
        let controls = try await settings.controls()
        let accessibility = await settings.playStationAccessibility()
            .resolved(using: PlayStationAccessibilitySystemDefaults.current)
        let datacenters = await CloudLaunchDatacenters.load()
        guard !opener.isStopped, !Task.isCancelled else {
            return
        }
        let player = try NativeStreamPlayer(inputs: inputs)
        player.request(accessibility)
        let video = CloudVideoRequest(
            picture: picture,
            service: request.title.service,
            displaySupportsHDR: DisplayDynamicRange.supportsHDR
        )
        let session = await open(
            player,
            picture: picture,
            request: request,
            opener: opener,
            settings: settings
        )
        CloudLaunchDatacenters(
            settings: datacenters,
            service: request.title.service,
            measuresBandwidth: video.measuresBandwidth
        )
        .install(on: player, session: session)
        CloudCaptureUploads(saver: captures, picture: picture, title: request.title.name, account: account)
            .install(on: player)
        self.controls.attach(player)
        self.controls.captureCloudButtons(for: request.title.service, platform: request.title.platform)
        defer {
            self.controls.detach(player)
        }
        let input = Self.makeInput(player, controls: controls, request: request, session: session)
        let relay = CoreDiagnosticRelay(.untilFirstFrame)
        observe(session, input: input, launchedAt: .now, diagnostics: relay)
        input.start()
        defer {
            input.stop()
        }
        await video.logLaunch(of: request.title, accessibility: accessibility)
        let health = CloudHealthMonitor.start(player)
        defer {
            health.cancel()
        }
        let launch = Start(account: account.data, request: request, video: video)
        let report = await start(player, session: session, launch: launch, relay: relay)
        guard let report else {
            return
        }
        try await finish(player, report: report, title: request.title, stopped: opener.isStopped)
    }

    private func open(
        _ player: NativeStreamPlayer,
        picture: CloudPictureSettings,
        request: CloudStreamRequest,
        opener: StreamSessionOpener,
        settings: StreamSettingsLoader
    ) async -> LiveStreamSession {
        let service = request.title.service.rawValue
        player.apply(picture.adjustments, reduceBanding: picture.reduceBanding)
        let sound = await settings.sound()
        player.apply(sound, audio3DAvailable: PlayBridge.supportsAudio3D(
            request.title.service == .psCloud
                ? .psCloud
                : .psNow
        ), controllerSpeakerAvailable: request.title.service == .psCloud)
        player.apply(sound.media)
        player.configure(
            output: picture.output(for: service),
            upscaler: picture.upscaler,
            nativeHeight: picture.height(for: service),
            generated120: picture.usesGenerated120(for: service)
        )
        player.native.cloudStableQuality = request.title.service == .psCloud && picture
            .psCloudQuality == .stable
        let session = opener.open(player)
        session.report(.videoDisabled(!sound.media.picture))
        session.report(.videoFit(picture.videoFit))
        return session
    }

    private func start(
        _ player: NativeStreamPlayer,
        session: LiveStreamSession,
        launch: Start,
        relay: CoreDiagnosticRelay
    ) async -> StreamEndReport? {
        let request = launch.request
        let video = launch.video
        let account = launch.account
        let clearance = request.clearance?.owner(as: CloudClearedLaunch.self)
        defer {
            withExtendedLifetime(clearance) {}
        }
        return await NativeStreamDiagnostics.run(player: player.native, relay: relay) {
            await session.run(rest: false) { done in
                player.native.startCloud(
                    forAccount: account,
                    productID: request.title.product.rawValue,
                    psCloud: request.title.service == .psCloud,
                    height: video.height,
                    bitrate: video.bitrateMbps * 1000,
                    hdr: video.hdr,
                    measureBandwidth: video.measuresBandwidth,
                    clearedLaunch: clearance?.handle
                ) { outcome in
                    done(StreamOutcomeReader.report(of: outcome.pointee))
                }
            }
        }
    }

    private func observe(
        _ session: LiveStreamSession,
        input: StreamInputSession,
        launchedAt: ContinuousClock.Instant,
        diagnostics: CoreDiagnosticRelay
    ) {
        var reported: CloudStartStep?
        session.relay.observe { signal in
            switch signal {
            case .event(.firstFrame):
                let milliseconds = LogFormat.milliseconds(launchedAt.duration(to: .now))
                Task { @MainActor in
                    await diagnostics.attemptSucceeded()
                }
                Self.log(.info, "First video frame presented \(milliseconds) ms after launch")
            case .event(.cloudStep(let step)) where step != reported:
                reported = step
                let milliseconds = LogFormat.milliseconds(launchedAt.duration(to: .now))
                Self.log(
                    .info,
                    "\(step.logDescription) (stage \(step.rawValue) of 5) after \(milliseconds) ms"
                )
            case .event(.couch(let couch)):
                input.observe(couch)
            case .gameLight(let pad, let color):
                input.gameLight(pad: pad, color: color)
            case .event:
                break
            }
        }
    }

    private func finish(
        _ player: NativeStreamPlayer,
        report: StreamEndReport,
        title: CloudStreamTitle,
        stopped: Bool
    ) async throws(StreamFailure) {
        let outcome = report.outcome
        let statistics = player.statistics
        let message = report.cloudMessage
        let ended = CloudSessionEnd(
            title: title.name,
            outcome: outcome,
            cancelled: stopped,
            seconds: statistics.streamSeconds,
            decoded: Int(player.native.decodedFrames),
            gpuErrors: statistics.gpuError,
            failureMessage: message,
            diagnostics: player.native.failureDiagnostics
        )
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(.cloud, ended.level, ended.message))
        guard !stopped else {
            return
        }
        if outcome.failed, let message {
            throw .serviceRefused(message)
        }
        guard outcome == .finished else {
            throw message.map(StreamFailure.serviceRefused) ?? .stream(outcome, overInternet: true)
        }
    }

    private static func makeInput(
        _ player: NativeStreamPlayer,
        controls: ControlsConfiguration,
        request: CloudStreamRequest,
        session: LiveStreamSession
    ) -> StreamInputSession {
        player.makeInput(
            configuration: controls,
            touchpadSurface: request.title.service == .psNow
                ? .ps4
                : .ps5,
            microphone: true
        ) { [weak session] event in
            await MainActor.run {
                session?.report(event)
            }
        }
    }

    private static func account(
        _ profile: ProfileID,
        in accountService: AccountService
    ) async throws(StreamFailure) -> AccountID {
        let accounts = try? await accountService.storage().accounts.list()
        guard let account = accounts?.first(where: { $0.id == profile.uuid }) else {
            throw .signInRequired
        }
        return account.accountID
    }

    private static func log(_ level: LogLevel, _ message: String) {
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.cloud, level, message))
    }

    /// Logs a cloud stream's health every ten seconds while the stream runs.
    private enum CloudHealthMonitor {
        /// Starts logging a player's health until the returned task is cancelled or the player goes away.
        ///
        /// - Parameter player: The cloud stream's player.
        /// - Returns: The task that samples and logs the health.
        @MainActor
        static func start(_ player: NativeStreamPlayer) -> Task<Void, Never> {
            Task { @MainActor [weak player] in
                var health = CloudHealth()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(10))
                    } catch {
                        return
                    }
                    guard let player else {
                        return
                    }
                    let line = health.sample(player.statistics, decoded: Int(player.native.decodedFrames))
                    @Dependency(\.logger) var logger
                    await logger.log(.diagnostic(.cloud, line.level, line.message))
                }
            }
        }
    }

    /// The picture a cloud launch asks the service for, from the saved cloud picture settings.
    private struct CloudVideoRequest {
        /// The picture height.
        let height: Int

        /// The bitrate in megabits per second.
        let bitrateMbps: Int

        /// Whether HDR is asked for.
        let hdr: Bool

        /// Whether the launch measures the connection's bandwidth first.
        let measuresBandwidth: Bool

        /// Reads the request for a service from the saved settings.
        ///
        /// - Parameters:
        ///   - picture: The saved cloud picture settings.
        ///   - service: The cloud service.
        ///   - displaySupportsHDR: Whether the display can show HDR.
        init(picture: CloudPictureSettings, service: CloudService, displaySupportsHDR: Bool) {
            height = picture.height(for: service.rawValue)
            bitrateMbps = picture.bitrateMbps(for: service.rawValue)
            hdr = picture.requestsHDR(for: service.rawValue, displaySupportsHDR: displaySupportsHDR)
            measuresBandwidth = picture.measuresBandwidth(for: service.rawValue)
        }

        /// Logs the launch of a title with this request.
        ///
        /// - Parameters:
        ///   - title: The title being launched.
        ///   - accessibility: The PlayStation accessibility settings the console is asked to use.
        func logLaunch(
            of title: CloudStreamTitle,
            accessibility: PlayStationAccessibilitySettings.Resolved
        ) async {
            let route: PlaybackLogRoute = title.service == .psNow
                ? .psNowCore
                : .psCloudCore
            let codec = title.service != .psCloud
                ? "H.264"
                : hdr
                    ? "HEVC HDR"
                    : "HEVC"
            let measuring = measuresBandwidth
                ? " until measured"
                : ""
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .cloud, .info,
                "\(route.rawValue): launching \"\(title.name)\" product \(title.product.rawValue), platform "
                    + "\(title.platform), owned \(LogFormat.yesNo(title.isOwned)), PS Plus catalog "
                    + "\(LogFormat.yesNo(title.plusCatalog)); requested \(height)p 60 fps "
                    + "\(bitrateMbps) Mbps\(measuring) \(codec); console screen reader "
                    + "\(LogFormat.yesNo(accessibility.screenReader)), "
                    + "speech speed \(accessibility.screenReaderSpeed), "
                    + "voice volume \(accessibility.screenReaderVolume), "
                    + "text size \(accessibility.textSize), bold text "
                    + "\(LogFormat.yesNo(accessibility.boldText)), higher contrast "
                    + "\(LogFormat.yesNo(accessibility.higherContrast))"
            ))
        }
    }

    /// The captures a cloud console uploads during one stream, saved to this device as the cloud picture settings
    /// ask.
    private struct CloudCaptureUploads {
        private let saver: CloudCaptureSaver
        private let picture: CloudPictureSettings
        private let title: String
        private let account: AccountID

        /// Creates the capture handling for one stream.
        ///
        /// - Parameters:
        ///   - saver: Saves each capture.
        ///   - picture: The cloud picture settings, which say whether and where captures are saved.
        ///   - title: The streamed title's name.
        ///   - account: The account that streams.
        init(saver: CloudCaptureSaver, picture: CloudPictureSettings, title: String, account: AccountID) {
            self.saver = saver
            self.picture = picture
            self.title = title
            self.account = account
        }

        /// Saves every capture the player reports as uploaded, unless captures are never saved.
        ///
        /// - Parameter player: The cloud stream's player.
        @MainActor
        func install(on player: NativeStreamPlayer) {
            guard picture.captureSaving != .never else {
                return
            }
            let saver = saver
            let account = account
            let title = title
            let followsPlayStation = picture.captureSaving == .followPlayStation
            FolderAccess.open(picture.captureFolder, bookmark: picture.captureFolderBookmark)
            let folder = picture.captureDirectory
            player.native
                .captureUploadedHandler = { identifier, gallery, fileExtension, size, video, created in
                    let upload = CloudCaptureUpload(
                        id: identifier,
                        galleryID: gallery,
                        fileExtension: fileExtension,
                        size: size,
                        video: video,
                        created: ISO8601DateFormatter().date(from: created)
                    )
                    let capture = PendingCloudCapture(
                        upload: upload,
                        account: account,
                        title: title,
                        folder: folder
                    )
                    Task.detached(priority: .utility) {
                        await saver.save(capture, followsPlayStation: followsPlayStation)
                    }
                }
        }
    }

    /// The datacenter part of a cloud launch: the saved choice, the offer at launch and the selection the core
    /// reports, each reported to the live session and the connection remembered.
    private struct CloudLaunchDatacenters {
        private let settings: CloudDatacenterSettings
        private let service: CloudDatacenterService
        private let measuresBandwidth: Bool

        /// Creates the datacenter handling for one launch.
        ///
        /// - Parameters:
        ///   - settings: The saved datacenter settings.
        ///   - service: The cloud service.
        ///   - measuresBandwidth: Whether the launch measures bandwidth, so offers carry the last measurement.
        init(settings: CloudDatacenterSettings, service: CloudService, measuresBandwidth: Bool) {
            self.settings = settings
            self.service = CloudDatacenterService(streamServiceType: service.rawValue) ?? .psCloud
            self.measuresBandwidth = measuresBandwidth
        }

        /// Reads the saved datacenter settings, falling back to Automatic when they cannot be read.
        ///
        /// - Returns: The settings.
        static func load() async -> CloudDatacenterSettings {
            @Dependency(\.cloud) var cloud
            do {
                return try await cloud.loadDatacenters()
            } catch {
                @Dependency(\.logger) var logger
                await logger.log(.diagnostic(
                    .cloud, .warning,
                    "Cloud datacenter preferences could not be read; using Automatic without prior measurements"
                ))
                return CloudDatacenterSettings()
            }
        }

        /// Sets the player's datacenter choice and reports its offer and selection to the session.
        ///
        /// - Parameters:
        ///   - player: The player.
        ///   - session: The live session.
        @MainActor
        func install(on player: NativeStreamPlayer, session: LiveStreamSession) {
            let pickAtLaunch = settings.selectsAtLaunch
            player.native.cloudForcedDatacenter = pickAtLaunch
                ? nil
                : settings.choice(for: service)
            player.native.cloudSelectDatacenterAtLaunch = pickAtLaunch
            player.native.cloudDatacenterSelectTimeoutMilliseconds = CloudDatacenterLaunchOffer
                .defaultTimeoutSeconds * 1000
            player.native.cloudDatacentersHandler = { [weak session] offers, wait in
                guard pickAtLaunch else {
                    return
                }
                let offer = offer(offers, wait: wait)
                MainActor.assumeIsolated {
                    session?.report(.datacenterOffered(offer))
                }
            }
            player.native.cloudDatacenterSelectedHandler = { [weak session] name, rtt, how in
                let selection = CloudDatacenterSelection.reported(
                    name: name,
                    rttMs: rtt,
                    forced: Self.chosenByPlayer(how),
                    settings: settings,
                    service: service,
                    atLaunch: pickAtLaunch
                )
                MainActor.assumeIsolated {
                    session?.report(.datacenterSelected(selection))
                }
                record(selection, rtt: rtt)
            }
        }

        private func offer(_ offers: [CNDatacenterOffer], wait: Int) -> CloudDatacenterLaunchOffer {
            CloudDatacenterLaunchOffer(
                entries: offers.map {
                    .init(
                        name: $0.name,
                        rttMs: $0.roundTripMilliseconds > 0
                            ? $0.roundTripMilliseconds
                            : nil,
                        bandwidthKbps: measuresBandwidth
                            ? settings.measurement(named: $0.name, for: service)?.bandwidthKbps
                            : nil
                    )
                },
                timeoutSeconds: wait > 0
                    ? (wait + 999) / 1000
                    : CloudDatacenterLaunchOffer.defaultTimeoutSeconds
            )
        }

        private func record(_ selection: CloudDatacenterSelection, rtt: Int) {
            let service = service
            Task {
                @Dependency(\.cloud) var cloud
                do {
                    _ = try await cloud.recordConnection(selection.name, rtt, service)
                } catch {
                    @Dependency(\.logger) var logger
                    await logger.log(.diagnostic(
                        .cloud,
                        .warning,
                        "Cloud datacenter connection could not be saved"
                    ))
                }
            }
        }

        /// Whether the player chose the datacenter, ahead of time or when the launch asked, rather than the core.
        ///
        /// - Parameter how: How the core says the datacenter was chosen.
        /// - Returns: `true` for a saved preference or a pick at launch.
        private static func chosenByPlayer(_ how: libchiaking.play.DatacenterChoice.How) -> Bool {
            switch how {
            case .preferred, .picked_at_launch:
                true
            case .automatic, .lowest_at_launch, .lowest_after_waiting:
                false
            }
        }
    }
}
