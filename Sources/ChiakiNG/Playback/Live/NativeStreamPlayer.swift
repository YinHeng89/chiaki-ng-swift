import ChiakiAssets
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
import MenuFocus
import PlatformUI
import Video
#if os(iOS)
    import UIKit
#endif

/// The native `CNLiveVideoPlayer` as the `ChiakiClients/StreamPlayer` one live session drives.
///
/// The player's handlers fire on the main queue; each is turned straight into a
/// `ChiakiClients/PlayerSignal` on the main actor, with no task per handler, so the session sees them in the
/// order they fired. The player also owns the sound rendering that follows the audio output device.
@MainActor
final class NativeStreamPlayer: StreamPlayer {
    /// The native player.
    let native: CNLiveVideoPlayer

    private let inputs: InputServices

    private var spatialAudio = SpatialAudio()
    private var audio3DAvailable = false
    private var outputRoute: AudioOutputWatcher?
    #if os(iOS)
        private var backgroundPause: BackgroundVideoPause?
    #endif
    private weak var input: StreamInputSession?

    /// The input of the stream holding the lease, while that input receives controllers.
    ///
    /// - Parameter leases: The stream lease.
    /// - Returns: The input, or `nil` when no stream holds an active lease or its input is not attached.
    static func attachedInput(in leases: StreamLeases) -> StreamInputSession? {
        guard let input = (leases.current?.player as? NativeStreamPlayer)?.input, input.isAttached else {
            return nil
        }
        return input
    }

    /// Creates the player with the bundled colour shader and upscaler weights.
    ///
    /// - Parameter inputs: The app's controller services the player's stream input runs over.
    /// - Throws: `ChiakiModels/StreamFailure/renderer` when the assets or the Metal surface are missing.
    init(inputs: InputServices) throws(StreamFailure) {
        self.inputs = inputs
        guard let shaderURL = ChiakiAssets.url(forResource: "VideoColour", withExtension: "txt"),
              let weightsURL = ChiakiAssets.url(forResource: "FSRCNNX16", withExtension: "bin"),
              let shader = try? String(contentsOf: shaderURL, encoding: .utf8),
              let weights = try? Data(contentsOf: weightsURL),
              let native = CNLiveVideoPlayer(shader: shader, fsrcnnWeights: weights) else {
            throw .renderer
        }
        self.native = native
        native.extendedFeedbackEnabled = true
    }

    /// Creates the input for this player's stream; the player keeps a weak reference so couch commands reach it.
    ///
    /// - Parameters:
    ///   - configuration: The controls configuration.
    ///   - touchpadSurface: The console's touchpad surface.
    ///   - rawKeyboard: Whether the keyboard can type on the console.
    ///   - microphone: Whether the stream offers a microphone.
    ///   - consoleHaptics: Whether the console's haptics should play.
    ///   - report: Where the input's couch and light events go.
    /// - Returns: The input, not yet started.
    func makeInput(
        configuration: ControlsConfiguration,
        touchpadSurface: TouchpadSurface,
        rawKeyboard: Bool = false,
        microphone: Bool = false,
        consoleHaptics: Bool = true,
        report: @escaping @Sendable (StreamSessionEvent) async -> Void = { _ in
        }
    ) -> StreamInputSession {
        let input = StreamInputSession(
            environment: InputEnvironment(player: native, services: inputs, report: report),
            configuration: configuration,
            options: StreamInputOptions(
                touchpadSurface: touchpadSurface,
                rawKeyboard: rawKeyboard,
                microphone: microphone,
                consoleHaptics: consoleHaptics
            )
        )
        self.input = input
        return input
    }

    /// The view the player renders into.
    var surface: StreamSurface {
        StreamSurface(native.view)
    }

    /// Whether the console refused the last rest mode request.
    var restRefused: Bool {
        native.restRefused
    }

    /// The stream's statistics: the core's, the renderer's and the stream the player asked for.
    var statistics: RenderStatistics {
        Self.statistics(of: native)
    }

    /// A native player's statistics: the core's, the renderer's and the stream it asked for.
    ///
    /// - Parameter native: The player.
    /// - Returns: The statistics.
    static func statistics(of native: CNLiveVideoPlayer) -> RenderStatistics {
        var statistics = StreamStatisticsReader.statistics(of: native.streamStatistics())
        read(native.surfaceStatistics(), into: &statistics)
        read(native.requestedStream(), into: &statistics)
        statistics.frameGenerationGenerated = native.generatedFrames?.intValue
        return statistics
    }

    /// Delivers every session handler to `receive`, in the order the player fires them.
    ///
    /// - Parameter receive: Called on the main actor for each signal.
    func connect(_ receive: @escaping @MainActor (PlayerSignal) -> Void) {
        let deliver: (PlayerSignal?) -> Void = { signal in
            guard let signal else {
                return
            }
            MainActor.assumeIsolated {
                receive(signal)
            }
        }
        connectSession(deliver)
        connectCloud(deliver)
        outputRoute?.stop()
        outputRoute = AudioOutputWatcher { [weak self] in
            self?.applySoundRendering()
        }
        #if os(iOS)
            backgroundPause?.stop()
            backgroundPause = BackgroundVideoPause(native: native)
        #endif
    }

    private func connectSession(_ deliver: @escaping (PlayerSignal?) -> Void) {
        native.firstFramePresentedHandler = {
            deliver(.event(.firstFrame))
        }
        native.displayProhibitedHandler = { prohibited in
            deliver(.event(.displayProhibited(prohibited)))
        }
        native.connectionWaitingHandler = { waiting in
            deliver(.event(.connectionWaiting(waiting)))
        }
        native.loginPINRequestHandler = { retry in
            deliver(.event(.accessRequested(.loginPIN(retry: retry))))
        }
        native.controllerPasscodeRequestHandler = { pad, retry in
            deliver(UInt8(exactly: pad).map { .event(.accessRequested(.controllerPasscode(
                pad: $0,
                retry: retry
            ))) })
        }
        native.couchEventHandler = { kind, pad, detail in
            deliver(CouchSessionEvent(kind, pad: pad, detail: detail).map { .event(.couch($0)) })
        }
        native.seatRefusedHandler = { refusal in
            let pad = SeatRefusalReader.pad(of: refusal.pointee).map { Int($0) } ?? -1
            let failure = SeatRefusalReader.failure(of: refusal.pointee)
            deliver(CouchSessionEvent(seat: pad, refused: failure).map { .event(.couch($0)) })
        }
        native.lightColorHandler = { pad, rgb in
            deliver(UInt8(exactly: pad).map { .gameLight(pad: $0, color: UInt32(truncatingIfNeeded: rgb)) })
        }
        native.keyboardEventHandler = { kind, text in
            deliver(Self.keyboard(kind, text: text).map { .event(.keyboard($0)) })
        }
        native.startAttemptHandler = { attempt in
            deliver(attempt > 1
                ? .event(.startRetried(attempt: attempt - 1))
                : nil)
        }
        native.reconnectingHandler = { attempt in
            deliver(.event(.reconnecting(attempt: attempt)))
        }
        native.reconnectedHandler = {
            deliver(.event(.reconnected))
        }
        native.connectProgressHandler = { progress in
            deliver(.event(.progress(Self.progress(OperationProgressReader.progress(of: progress.pointee)))))
        }
    }

    private func connectCloud(_ deliver: @escaping (PlayerSignal?) -> Void) {
        native.launchProgressHandler = { progress, playing in
            let step = OperationProgressReader.step(of: progress.pointee, playing: playing)
            let reported = OperationProgressReader.progress(of: progress.pointee)
            deliver(reported.map { .event(.progress(Self.progress($0))) })
            deliver(step.map { .event(.cloudStep($0)) })
        }
        native.playTimeLeftHandler = { minutes, limit in
            deliver(.event(.closing(CloudNoticeReader.closing(minutes: minutes, limit: limit))))
        }
        native.cloudNoticeHandler = { notice in
            deliver(.event(.cloudNotice(CloudNoticeReader.notice(of: notice.pointee))))
        }
        native.recordingBannerHandler = { recording, elapsed in
            deliver(.event(.recording(recording
                    ? CloudRecordingBanner(elapsed: elapsed)
                    : nil)))
        }
        native.captureThumbnailHandler = { identifier, video, jpeg in
            deliver(.event(.captureThumbnail(CloudCaptureThumbnail(
                id: identifier,
                video: video,
                jpeg: jpeg
            ))))
        }
    }

    /// Drops every handler, stops following the audio output device and, on iOS, stops pausing video in the
    /// background.
    func disconnect() {
        native.firstFramePresentedHandler = nil
        native.displayProhibitedHandler = nil
        native.connectionWaitingHandler = nil
        native.loginPINRequestHandler = nil
        native.controllerPasscodeRequestHandler = nil
        native.couchEventHandler = nil
        native.seatRefusedHandler = nil
        native.lightColorHandler = nil
        native.keyboardEventHandler = nil
        native.startAttemptHandler = nil
        native.reconnectingHandler = nil
        native.reconnectedHandler = nil
        native.connectProgressHandler = nil
        native.launchProgressHandler = nil
        native.playTimeLeftHandler = nil
        native.cloudNoticeHandler = nil
        native.recordingBannerHandler = nil
        native.captureThumbnailHandler = nil
        native.captureUploadedHandler = nil
        native.cloudDatacentersHandler = nil
        native.cloudDatacenterSelectedHandler = nil
        native.kakusanEventHandler = nil
        native.setupProgressHandler = nil
        outputRoute?.stop()
        outputRoute = nil
        #if os(iOS)
            backgroundPause?.stop()
            backgroundPause = nil
        #endif
    }

    /// Ends the stream.
    func stop() {
        native.stop()
    }

    /// Ends the stream and asks the console to enter rest mode.
    func stopWithRest() {
        native.stopWithRest()
    }

    /// Ends the stream for sleep.
    func stopForSleep() {
        native.stopForSleep()
    }

    /// Ends the stream for sleep and asks the console to enter rest mode.
    func stopForSleepWithRest() {
        native.stopForSleepWithRest()
    }

    /// Sends the console's login PIN.
    ///
    /// - Parameter code: The PIN.
    /// - Returns: Whether the console accepted it.
    func submitLoginPIN(_ code: StreamAccessCode) async -> Bool {
        await withCheckedContinuation { continuation in
            native.submitLoginPIN(code.digits) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }

    /// Sends a couch pad's passcode.
    ///
    /// - Parameters:
    ///   - code: The passcode.
    ///   - pad: The pad.
    /// - Returns: Whether it was sent.
    func submitControllerPasscode(_ code: StreamAccessCode, pad: UInt8) -> Bool {
        native.submitControllerPasscode(code.digits, pad: Int(pad))
    }

    /// Asks the console to show its home screen.
    ///
    /// - Returns: Whether the request was sent.
    func goHome() -> Bool {
        native.goHome()
    }

    /// Sends a change to the console's on-screen keyboard.
    ///
    /// - Parameter command: The change.
    /// - Returns: Whether it was sent.
    func send(_ command: ConsoleKeyboardCommand) -> Bool {
        switch command {
        case .setText(let text):
            native.setKeyboardText(text)
        case .accept(let text):
            native.acceptKeyboardText(text)
        case .reject:
            native.rejectKeyboard()
        }
    }

    /// Chooses an offered cloud datacenter.
    ///
    /// - Parameter name: The datacenter's name.
    /// - Returns: Whether the core took it.
    func selectDatacenter(_ name: String) -> Bool {
        native.selectCloudDatacenter(name)
    }

    #if os(iOS)
        /// Drops a stream's video while the app is in the background and resumes it, with a fresh keyframe, when the
        /// app returns to the foreground. Audio, input and the connection keep running throughout.
        ///
        /// Watching stops on ``stop()`` or when the pause is released, and the video is resumed on ``stop()``.
        @MainActor
        private final class BackgroundVideoPause {
            private let native: CNLiveVideoPlayer
            private var observers: [NSObjectProtocol] = []

            /// Starts following the app's background and foreground changes for one player.
            ///
            /// - Parameter native: The player whose video is dropped while the app is in the background.
            init(native: CNLiveVideoPlayer) {
                self.native = native
                let center = NotificationCenter.default
                observers = [
                    center.addObserver(
                        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.native.videoSuspended = true
                        }
                    },
                    center.addObserver(
                        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.native.videoSuspended = false
                        }
                    }
                ]
                native.videoSuspended = UIApplication.shared.applicationState == .background
            }

            /// Stops following the app and resumes the video.
            func stop() {
                removeObservers()
                native.videoSuspended = false
            }

            private func removeObservers() {
                for observer in observers {
                    NotificationCenter.default.removeObserver(observer)
                }
                observers = []
            }

            isolated deinit {
                removeObservers()
            }
        }
    #endif
}

extension NativeStreamPlayer {
    /// Applies picture and sound settings the stream menu changed.
    ///
    /// - Parameter tuning: The settings.
    func apply(_ tuning: StreamTuningConfiguration) {
        apply(tuning.adjustments, reduceBanding: tuning.reduceBanding)
        native.audioVolume = tuning.volume
        if let chatVolume = tuning.chatVolume {
            native.chatVolume = chatVolume
        }
        spatialAudio = tuning.spatialAudio
        applySoundRendering()
        configure(
            output: tuning.upscaledOutput,
            upscaler: tuning.upscaler,
            nativeHeight: tuning.nativeHeight,
            sourceFPS: tuning.sourceFPS,
            generated120: tuning.presentationFrameRate == .generated120 && tuning.frameGenerationAvailable
        )
    }

    /// Applies the saved console picture settings for the route and reports the stream it asks for.
    ///
    /// - Parameters:
    ///   - picture: The saved picture settings.
    ///   - ps5: Whether the console is a PS5.
    ///   - route: The picture route the stream uses.
    /// - Returns: The resolution, frame rate and bitrate to ask the console for.
    func configure(for picture: PictureSettings, ps5: Bool,
                   route: PictureSettings.Route) async -> StreamProfile {
        let profile = picture.profile(for: route, ps5: ps5)
        let codec = picture.launchCodec(
            forPS5: ps5,
            route: route,
            displaySupportsHDR: DisplayDynamicRange.supportsHDR
        )
        apply(picture.adjustments, reduceBanding: picture.reduceBanding)
        configure(
            output: profile.upscaledOutput,
            upscaler: picture.upscaler,
            nativeHeight: profile.height,
            sourceFPS: profile.fps,
            generated120: picture.presentationFrameRate == .generated120 && codec != .hevcHDR
        )
        @Dependency(\.logger) var logger
        await logger.log(.videoConfigured(
            height: profile.height,
            framesPerSecond: profile.fps,
            megabitsPerSecond: profile.effectiveBitrateMbps,
            codec: codec.title,
            dynamicRange: VideoDynamicRange(ps5: ps5, hdrCodec: codec == .hevcHDR)
        ))
        return profile
    }

    /// Sets the picture's output size, upscaler and frame generation.
    ///
    /// - Parameters:
    ///   - output: The upscaled size.
    ///   - upscaler: The upscaler.
    ///   - nativeHeight: The stream's picture height.
    ///   - sourceFPS: The stream's frame rate.
    ///   - generated120: Whether in-between frames are generated.
    func configure(
        output: UpscaledOutput,
        upscaler: VideoUpscaler,
        nativeHeight: Int,
        sourceFPS: Int = 60,
        generated120: Bool
    ) {
        let effectiveOutput = output.compatible(with: nativeHeight)
        native.targetOutputHeight = effectiveOutput.height(source: nativeHeight)
        native.sourceFrameRate = sourceFPS
        native.frameGenerationEnabled = generated120
            && PlaybackWindowControl.displayMaximumFramesPerSecond >= sourceFPS * 2
        guard effectiveOutput != .disabled else {
            native.videoUpscaler = .disabled
            return
        }
        switch upscaler {
        case .metalFX:
            native.videoUpscaler = .metalFX
        case .advancedSpatial:
            native.videoUpscaler = .advancedSpatial
        }
    }

    /// Sets brightness, contrast, saturation, gamma and banding reduction.
    ///
    /// - Parameters:
    ///   - adjustments: The adjustments.
    ///   - reduceBanding: Whether banding is smoothed.
    func apply(_ adjustments: PictureAdjustments, reduceBanding: Bool) {
        native.setPictureBrightness(
            Float(adjustments.brightness),
            contrast: Float(adjustments.contrast),
            saturation: Float(adjustments.saturation),
            gamma: Float(adjustments.gamma),
            deband: reduceBanding
        )
    }

    /// Applies the saved sound settings.
    ///
    /// - Parameters:
    ///   - sound: The settings.
    ///   - audio3DAvailable: Whether the stream can carry the console's 3D audio.
    ///   - controllerSpeakerAvailable: Whether the stream can carry controller speaker sounds.
    func apply(_ sound: SoundSettings, audio3DAvailable: Bool, controllerSpeakerAvailable: Bool = false) {
        native.audioOutputDevice = sound.outputDevice
        native.audioVolume = sound.volume
        native.chatVolume = sound.chatVolume
        native.audioBufferMilliseconds = sound.bufferMilliseconds
        native.requestedAudioChannels = 2
        native.controllerSpeakerEnabled = sound.controllerSpeaker && controllerSpeakerAvailable
        spatialAudio = sound.spatialAudio
        self.audio3DAvailable = audio3DAvailable
        applySoundRendering()
    }

    /// Switches the stream's sound or picture off.
    ///
    /// - Parameter media: Which media play.
    func apply(_ media: StreamMedia) {
        native.streamAudioDisabled = !media.sound
        native.streamVideoDisabled = !media.picture
    }

    /// Shows a diagnostic overlay on the picture.
    ///
    /// - Parameter mode: The overlay.
    func applyVideoAnalysis(_ mode: StreamVideoAnalysisMode) {
        switch mode {
        case .off:
            native.videoDiagnosticMode = .off
        case .hdrHeatmap:
            native.videoDiagnosticMode = .hdrHeatmap
        case .highlightClipping:
            native.videoDiagnosticMode = .highlightClipping
        }
    }

    private func applySoundRendering() {
        let rendering = spatialAudio.rendering(
            for: AudioOutputs.kind(device: native.audioOutputDevice),
            audio3DAvailable: audio3DAvailable
        )
        native.audio3DEnabled = rendering == .audio3D
        native.audioSpatialEnabled = rendering == .spatial
    }

    private static func keyboard(_ kind: CNKeyboardEvent, text: String) -> ConsoleKeyboardSignal? {
        switch kind {
        case .opened:
            .opened(text)
        case .textChanged:
            .textChanged(text)
        case .remoteClosed:
            .closed
        @unknown default:
            nil
        }
    }

    private static func read(_ surface: CNSurfaceStatistics, into statistics: inout RenderStatistics) {
        statistics.submitted = Int(surface.submitted)
        statistics.completed = Int(surface.completed)
        statistics.rejected = Int(surface.rejected)
        statistics.noDrawable = Int(surface.noDrawable)
        statistics.generatedDrops = Int(surface.generatedDrops)
        statistics.replacedFrames = Int(surface.replacedFrames)
        statistics.idleTicks = Int(surface.idleTicks)
        statistics.deadlineMisses = Int(surface.deadlineMisses)
        statistics.gpuError = surface.gpuError
        statistics.spatialUpscaling = surface.spatialUpscaling.boolValue
        statistics.advancedSpatial = surface.advancedSpatial.boolValue
        statistics.advancedBudgetFallback = surface.advancedBudgetFallback.boolValue
        statistics.sourceWidth = Int(surface.sourceWidth)
        statistics.sourceHeight = Int(surface.sourceHeight)
        statistics.outputWidth = Int(surface.outputWidth)
        statistics.outputHeight = Int(surface.outputHeight)
        statistics.tenBit = surface.tenBit.boolValue
        statistics.perceptualQuantizer = surface.pq.boolValue
        statistics.bt2020 = surface.bt2020.boolValue
        statistics.layerHDR = surface.layerHDR.boolValue
        statistics.toneMapSource = surface.toneMapSource.rawValue
        statistics.contentPeakNits = surface.contentPeakNits
        statistics.gpuMilliseconds = surface.gpuMilliseconds
        statistics.presentationFrameRate = surface.presentationFrameRate
        statistics.displayMaximumFPS = surface.displayMaximumFPS
        statistics.displayMaximumEDR = surface.displayMaximumEDR
        statistics.displayPotentialEDR = surface.displayPotentialEDR
        statistics.light.measurements = Int(surface.lightMeasurements)
        statistics.light.seconds = surface.lightSeconds
        statistics.light.peakNits = surface.lightPeakNits
        statistics.light.averageNits = surface.lightAverageNits
        statistics.light.abovePercent = surface.lightAbovePercent
        statistics.light.maxCLL = surface.maxCLL
        statistics.light.maxFALL = surface.maxFALL
        statistics.light.sessionAbovePercent = surface.sessionAbovePercent
        statistics.light.sessionNearWhitePercent = surface.sessionNearWhitePercent
        statistics.light.markerNits = surface.markerNits
        statistics.light.markerFollowsPointer = surface.markerFollowsPointer.boolValue
        statistics.light.markerVisible = surface.markerVisible.boolValue
    }

    private static func read(_ requested: CNRequestedStream, into statistics: inout RenderStatistics) {
        statistics.requestedHeight = requested.height
        statistics.requestedFPS = requested.fps
        statistics.requestedBitrate = requested.bitrate
        statistics.requestedHEVC = requested.hevc.boolValue
        statistics.requestedHDR = requested.hdr.boolValue
        statistics.route = requested.route.rawValue
        statistics.routeConsole = requested.console.rawValue
        statistics.streamSeconds = requested.streamSeconds
    }

    private static func progress(_ progress: OperationProgress) -> StreamProgress {
        StreamProgress(
            queuePosition: progress.queuePosition,
            bandwidth: progress.bandwidth,
            reconnecting: progress.reconnecting,
            detail: progress
        )
    }
}

extension NativeStreamPlayer {
    /// Asks the cloud console to use these PlayStation accessibility settings when the stream starts.
    ///
    /// - Parameter accessibility: The settings with every device default filled in.
    func request(_ accessibility: PlayStationAccessibilitySettings.Resolved) {
        native.cloudScreenReader = accessibility.screenReader
        native.cloudScreenReaderSpeed = accessibility.screenReaderSpeed
        native.cloudScreenReaderVolume = accessibility.screenReaderVolume
        native.cloudTextSize = accessibility.textSize
        native.cloudBoldText = accessibility.boldText
        native.cloudHigherContrast = accessibility.higherContrast
    }
}
