import AVFoundation
import AudioToolbox
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
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Thread-safe gate that forwards encoded microphone frames to the stream player until it is closed.
final class MicrophoneFrameSink: @unchecked Sendable {
    private let player: CNLiveVideoPlayer
    private let lock = NSLock()
    private var open = true

    /// Creates an open sink for the given player.
    /// - Parameter player: The player that sends frames to the console.
    init(player: CNLiveVideoPlayer) {
        self.player = player
    }

    /// Sends one encoded frame to the console unless the sink has been closed.
    /// - Parameters:
    ///   - frame: The encoded Opus frame bytes.
    ///   - length: The number of bytes in the frame.
    func send(_ frame: UnsafePointer<UInt8>, length: Int) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard open else {
            return
        }
        _ = player.sendMicrophoneFrame(frame, length: UInt(length))
    }

    /// Stops all further frames from reaching the player.
    func close() {
        lock.lock()
        open = false
        lock.unlock()
    }
}

/// Takes the microphone from the audio input thread, converts it to 48 kHz 16-bit PCM, splits it into fixed-size
/// frames, encodes each as Opus and hands it to a sink.
///
/// The input thread only copies the channels it keeps, as 16-bit samples, into a `ChiakiCoreBridge/MicrophoneQueue`,
/// so it never waits, locks or allocates. Conversion, framing, encoding and sending run on the pipeline's own
/// encoding queue, which drains the queue every few milliseconds until the pipeline is released.
final class MicrophoneEncoderPipeline: @unchecked Sendable {
    private static let frameSamples = MicrophoneOpusEncoder.samplesPerFrame
    private static let channels = MicrophoneOpusEncoder.channels
    private static let queueTargetMilliseconds = 40
    private static let drainInterval = DispatchTimeInterval.milliseconds(5)
    private static let largestCopy = 4096
    private let encoder: MicrophoneOpusEncoder
    private let converter: AVAudioConverter
    private let sink: MicrophoneFrameSink
    private let width: Int
    private let queue: MicrophoneQueue
    private let scratch: UnsafeMutableBufferPointer<Int16>
    private let drained: AVAudioPCMBuffer
    private let chunkFrames: Int
    private let encoding = DispatchQueue(label: "dev.chiaki-ng.microphone-encode", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var pending = [Int16]()
    private var converted: AVAudioPCMBuffer?
    private var stereo: [Int16]
    private var frame: [UInt8]

    /// Creates a pipeline for the given input format and starts draining it, or returns `nil` when no queue,
    /// converter or encoder can be created.
    /// - Parameters:
    ///   - input: The format the audio engine's input node produces.
    ///   - processing: Whether the input is voice processed, which forces mono capture.
    ///   - sink: The destination for encoded frames.
    init?(input: AVAudioFormat, processing: MicrophoneProcessing, sink: MicrophoneFrameSink) {
        let width = Self.keptChannels(of: input, processing: processing)
        let chunkFrames = max(1, Int(input.sampleRate) / 100)
        guard let captured = Self.capturedFormat(of: input, channels: width),
              let converter = Self.converter(from: captured),
              let encoder = MicrophoneOpusEncoder(),
              let queue = MicrophoneQueue(
                  channels: width,
                  sampleRate: Int(input.sampleRate),
                  targetMilliseconds: Self.queueTargetMilliseconds
              ),
              let drained = AVAudioPCMBuffer(
                  pcmFormat: captured,
                  frameCapacity: AVAudioFrameCount(chunkFrames)
              )
        else {
            return nil
        }
        self.converter = converter
        self.width = width
        self.encoder = encoder
        self.sink = sink
        self.queue = queue
        self.drained = drained
        self.chunkFrames = chunkFrames
        scratch = .allocate(capacity: Self.largestCopy * width)
        stereo = [Int16](repeating: 0, count: Self.frameSamples * Self.channels)
        frame = [UInt8](repeating: 0, count: MicrophoneOpusEncoder.frameSize)
        pending.reserveCapacity(Self.frameSamples * 4)
        startDraining()
    }

    deinit {
        timer?.cancel()
        scratch.deallocate()
    }

    /// How many channels capture keeps: both for raw, non-discrete two-channel input, otherwise the first.
    /// - Parameters:
    ///   - input: The captured audio format.
    ///   - processing: Whether voice processing is active.
    /// - Returns: 2 or 1.
    static func keptChannels(of input: AVAudioFormat, processing: MicrophoneProcessing) -> Int {
        processing == .raw && input.channelCount == 2 && !isDiscrete(input)
            ? 2
            : 1
    }

    /// The format the input thread queues: interleaved 16-bit samples of the kept channels at the input's rate.
    /// - Parameters:
    ///   - input: The captured audio format.
    ///   - channels: How many channels are kept.
    /// - Returns: The format, or `nil` when it cannot be described.
    static func capturedFormat(of input: AVAudioFormat, channels: Int) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: input.sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        )
    }

    /// Builds a converter from the queued format to the console's microphone sample rate.
    /// - Parameter captured: The queued format.
    /// - Returns: The converter, or `nil` when the formats cannot be converted.
    static func converter(from captured: AVAudioFormat) -> AVAudioConverter? {
        guard let output = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(MicrophoneOpusEncoder.sampleRate),
            channels: captured.channelCount,
            interleaved: true
        ) else {
            return nil
        }
        return AVAudioConverter(from: captured, to: output)
    }

    /// Reports whether the format's channel layout is a discrete in-order layout rather than a speaker
    /// arrangement.
    /// - Parameter format: The format to inspect.
    /// - Returns: `true` for discrete channel layouts.
    static func isDiscrete(_ format: AVAudioFormat) -> Bool {
        guard let tag = format.channelLayout?.layoutTag else {
            return false
        }
        return tag & 0xffff0000 == kAudioChannelLayoutTag_DiscreteInOrder
    }

    /// Copies the first `channels` channels of 32-bit float input into interleaved 16-bit samples, clamping to
    /// full scale. Never allocates.
    /// - Parameters:
    ///   - list: The input buffers, one per channel or one interleaved buffer.
    ///   - format: Their format.
    ///   - frames: The frames to copy.
    ///   - channels: How many channels to keep.
    ///   - output: Receives the frames' count times `channels` samples.
    static func copy(
        _ list: UnsafeMutableAudioBufferListPointer,
        format: AVAudioFormat,
        frames: Range<Int>,
        channels: Int,
        into output: UnsafeMutableBufferPointer<Int16>
    ) {
        let stride = format.isInterleaved
            ? Int(format.channelCount)
            : 1
        for channel in 0..<channels {
            let buffer = format.isInterleaved
                ? list[0]
                : list[min(channel, list.count - 1)]
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }
            let offset = format.isInterleaved
                ? channel
                : 0
            for index in 0..<frames.count {
                let value = data[(frames.lowerBound + index) * stride + offset]
                let scaled = (max(-1, min(1, value)) * Float(Int16.max)).rounded()
                output[index * channels + channel] = Int16(scaled)
            }
        }
    }

    /// Queues audio the sink node received on the input thread, keeping only the channels capture needs.
    /// - Parameters:
    ///   - list: The audio, in the input node's format.
    ///   - format: The input node's format.
    /// - Returns: `noErr`, or `kAudio_ParamError` when the audio is not 32-bit float.
    func process(_ list: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> OSStatus {
        guard format.commonFormat == .pcmFormatFloat32 else {
            return kAudio_ParamError
        }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let firstBuffer = buffers.first else {
            return kAudio_ParamError
        }
        let bytesPerFrame = MemoryLayout<Float>.size * (format.isInterleaved
            ? Int(format.channelCount)
            : 1)
        let frames = Int(firstBuffer.mDataByteSize) / bytesPerFrame
        var first = 0
        while first < frames {
            let count = min(Self.largestCopy, frames - first)
            Self.copy(buffers, format: format, frames: first..<first + count, channels: width, into: scratch)
            queue.push(UnsafeBufferPointer(rebasing: scratch[0..<count * width]))
            first += count
        }
        return noErr
    }

    private func startDraining() {
        let timer = DispatchSource.makeTimerSource(queue: encoding)
        timer.schedule(deadline: .now(), repeating: Self.drainInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.drain()
        }
        timer.resume()
        self.timer = timer
    }

    private func drain() {
        guard let samples = drained.int16ChannelData?[0] else {
            return
        }
        while queue.bufferedFrames >= chunkFrames {
            _ = queue.pull(into: UnsafeMutableBufferPointer(start: samples, count: chunkFrames * width))
            drained.frameLength = AVAudioFrameCount(chunkFrames)
            process(drained)
        }
    }

    /// Converts a queued buffer, appends its samples and encodes every complete frame now available.
    /// - Parameter buffer: Queued audio in the captured format.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else {
            return
        }
        guard let converted = output(for: buffer.frameLength) else {
            return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, state in
            if supplied {
                state.pointee = .noDataNow
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, let samples = converted.int16ChannelData?[0] else {
            return
        }
        pending.append(contentsOf: UnsafeBufferPointer(
            start: samples,
            count: Int(converted.frameLength) * width
        ))
        encodeReadyFrames()
    }

    private func output(for frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        if let converted, converted.frameCapacity >= capacity {
            converted.frameLength = 0
            return converted
        }
        converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        return converted
    }

    private func encodeReadyFrames() {
        var offset = 0
        let span = Self.frameSamples * width
        while pending.count - offset >= span {
            for index in 0..<Self.frameSamples {
                for channel in 0..<Self.channels {
                    stereo[index * Self.channels + channel] = pending[offset + index * width + min(
                        channel,
                        width - 1
                    )]
                }
            }
            offset += span
            let result = stereo.withUnsafeBufferPointer { pcm in
                frame.withUnsafeMutableBufferPointer { output in
                    encoder.encode(pcm, into: output)
                }
            }
            guard result else {
                continue
            }
            frame.withUnsafeBufferPointer { output in
                if let base = output.baseAddress {
                    sink.send(base, length: output.count)
                }
            }
        }
        if offset > 0 {
            pending.removeFirst(offset)
        }
    }
}

/// Owns the audio engine that captures the microphone for the live stream, handling the console's connection
/// handshake, mute and unmute, device changes and teardown for one operation at a time.
@MainActor final class MicrophoneCapture {
    /// How long to wait for the console to accept a microphone connection request.
    static let connectionTimeout = Duration.seconds(5)

    private enum CaptureState {
        case running
        case resuming
        case paused
    }

    private struct Capture {
        let engine: AVAudioEngine
        let sink: AVAudioSinkNode
        let format: AVAudioFormat
        let observer: NSObjectProtocol
        var state = CaptureState.running
    }

    private struct OpenedEngine: @unchecked Sendable {
        let engine: AVAudioEngine
        let sink: AVAudioSinkNode
        let format: AVAudioFormat
    }

    private enum Opening: @unchecked Sendable {
        case opened(OpenedEngine)
        case failed(MicrophoneFailure)
    }

    private nonisolated static let audioQueue = DispatchQueue(label: "io.streetpea.chiaki.microphone-audio")

    private struct Session {
        let operation: UUID
        let player: CNLiveVideoPlayer
        let sink: MicrophoneFrameSink
        let inputDevice: String?
        let interrupted: @Sendable (MicrophoneFailure) -> Void
        var capture: Capture?
    }

    private var session: Session?
    private var request: UInt32 = 0

    /// Creates an idle capture; the microphone client owns the one the app uses.
    nonisolated init() {}

    /// Returns whether the app may record audio, asking the user when permission has not been decided yet.
    /// - Returns: `true` when microphone access is authorised.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Stops any previous capture, asks the console to accept the microphone, unmutes it and opens the audio
    /// engine, abandoning the attempt if it is cancelled or superseded.
    /// - Parameters:
    ///   - operation: Identifies this capture so later calls and stale completions can be matched to it.
    ///   - player: The live player, or `nil` when no stream is running.
    ///   - inputDevice: The name of the preferred input, or `nil` for the system default.
    ///   - interrupted: Called when the input changes, disappears or stops after capture started.
    /// - Returns: `nil` on success, or the reason capture could not start.
    func start(
        _ operation: UUID,
        player: CNLiveVideoPlayer?,
        inputDevice: String?,
        interrupted: @escaping @Sendable (MicrophoneFailure) -> Void
    ) async -> MicrophoneFailure? {
        stop(nil)
        guard let player else {
            return .streamUnavailable
        }
        request &+= 1
        let current = request
        guard player.connectMicrophoneRequest(current) else {
            return .streamUnavailable
        }
        if let failure = await connection(current, player: player) {
            return failure
        }
        guard !Task.isCancelled, session == nil, request == current else {
            return .streamUnavailable
        }
        guard player.setMicrophoneMuted(false) else {
            return .consoleRejected
        }
        let sink = MicrophoneFrameSink(player: player)
        let opening = await Self.onAudioQueue {
            Self.open(inputDevice: inputDevice, sink: sink)
        }
        guard !Task.isCancelled, session == nil, request == current else {
            if case let .opened(opened) = opening {
                Self.stopEngine(opened)
            }
            _ = player.setMicrophoneMuted(true)
            sink.close()
            return .streamUnavailable
        }
        switch opening {
        case .failed(let failure):
            _ = player.setMicrophoneMuted(true)
            sink.close()
            return failure
        case .opened(let opened):
            let capture = install(opened, operation: operation)
            session = Session(
                operation: operation,
                player: player,
                sink: sink,
                inputDevice: inputDevice,
                interrupted: interrupted,
                capture: capture
            )
            return nil
        }
    }

    /// Mutes or unmutes the console microphone for the given operation, pausing the engine when muted and
    /// restarting or reopening it when unmuted.
    /// - Parameters:
    ///   - operation: The operation that started the capture.
    ///   - muted: Whether the microphone should be muted.
    /// - Returns: `nil` on success, or the reason the change failed.
    func setMuted(_ operation: UUID, muted: Bool) async -> MicrophoneFailure? {
        guard let current = session, current.operation == operation else {
            return .streamUnavailable
        }
        guard current.player.setMicrophoneMuted(muted) else {
            return .consoleRejected
        }
        if muted {
            current.capture?.engine.pause()
            session?.capture?.state = .paused
            return nil
        }
        if let capture = current.capture {
            guard capture.state == .paused else {
                return nil
            }
            session?.capture?.state = .resuming
            let opened = OpenedEngine(engine: capture.engine, sink: capture.sink, format: capture.format)
            let restarted = await Self.onAudioQueue {
                Self.restart(opened)
            }
            guard let live = session, live.operation == operation, let resumed = live.capture,
                  resumed.engine === capture.engine else {
                return .streamUnavailable
            }
            if restarted {
                guard resumed.state == .resuming else {
                    resumed.engine.pause()
                    return nil
                }
                session?.capture?.state = .running
                return nil
            }
            close(resumed)
            session?.capture = nil
        }
        let inputDevice = current.inputDevice
        let sink = current.sink
        let opening = await Self.onAudioQueue {
            Self.open(inputDevice: inputDevice, sink: sink)
        }
        guard let live = session, live.operation == operation, live.capture == nil else {
            if case let .opened(opened) = opening {
                Self.stopEngine(opened)
            }
            return .streamUnavailable
        }
        switch opening {
        case .failed(let failure):
            _ = current.player.setMicrophoneMuted(true)
            return failure
        case .opened(let opened):
            session?.capture = install(opened, operation: operation)
            return nil
        }
    }

    private nonisolated static func restart(_ opened: OpenedEngine) -> Bool {
        do {
            try opened.engine.start()
            return true
        } catch {
            return false
        }
    }

    /// Ends the capture, closing the sink and engine, muting the console microphone and logging the stream's
    /// microphone totals.
    /// - Parameter operation: The operation to stop, or `nil` to stop whatever capture is running.
    func stop(_ operation: UUID?) {
        guard let current = session, operation == nil || current.operation == operation else {
            return
        }
        session = nil
        current.sink.close()
        close(current.capture)
        _ = current.player.setMicrophoneMuted(true)
        let statistics = current.player.microphoneStatistics()
        log(
            .info,
            "Microphone capture stopped; stream totals so far: queued \(statistics["queued"] ?? 0), sent "
                + "\(statistics["sent"] ?? 0), dropped \(statistics["dropped"] ?? 0), failures "
                + "\(statistics["failures"] ?? 0)"
        )
    }

    private func connection(_ request: UInt32, player: CNLiveVideoPlayer) async -> MicrophoneFailure? {
        let deadline = ContinuousClock.now + Self.connectionTimeout
        while ContinuousClock.now < deadline {
            switch player.microphoneConnectState(request) {
            case .accepted:
                log(.info, "The console accepted microphone connection request \(request)")
                return nil
            case .rejected:
                log(.warning, "The console rejected microphone connection request \(request)")
                return .consoleRejected
            case .pending:
                break
            }
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return .streamUnavailable
            }
        }
        log(.warning, "Microphone connection request \(request) was not answered in time")
        return .noAnswer
    }

    private nonisolated static func receiver(
        _ pipeline: MicrophoneEncoderPipeline,
        format: AVAudioFormat
    ) -> AVAudioSinkNodeReceiverBlock {
        { _, _, list in
            pipeline.process(list, format: format)
        }
    }

    private func close(_ capture: Capture?) {
        guard let capture else {
            return
        }
        NotificationCenter.default.removeObserver(capture.observer)
        Self.stopEngine(OpenedEngine(engine: capture.engine, sink: capture.sink, format: capture.format))
    }

    private func configurationChanged(_ operation: UUID) {
        guard let current = session, current.operation == operation, let capture = current.capture else {
            return
        }
        let format = capture.engine.inputNode.outputFormat(forBus: 0)
        let selectedMissing = current.inputDevice.map {
            MicrophoneInputDevices.device(named: $0) == nil
        } ?? false
        let lost = format.sampleRate <= 0 || format.channelCount == 0 || selectedMissing
        guard !lost, format == capture.format else {
            current.interrupted(.inputChanged)
            return
        }
        guard capture.state == .running, !capture.engine.isRunning else {
            return
        }
        do {
            try capture.engine.start()
        } catch {
            current.interrupted(.stopped(LogFormat.error(error)))
        }
    }

    /// Writes a playback diagnostic about the microphone.
    /// - Parameters:
    ///   - level: The log level.
    ///   - message: The text to log.
    func log(_ level: LogLevel, _ message: String) {
        Self.report(level, message)
    }

    /// Writes a playback diagnostic from any thread.
    /// - Parameters:
    ///   - level: The log level.
    ///   - message: The text to log.
    nonisolated static func report(_ level: LogLevel, _ message: String) {
        @Dependency(\.logger) var logger
        logger.enqueue(.diagnostic(.playback, level, message))
    }
}

extension MicrophoneCapture {
    private nonisolated static func onAudioQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async
        -> T {
        await withCheckedContinuation { continuation in
            audioQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private nonisolated static func open(inputDevice: String?, sink: MicrophoneFrameSink) -> Opening {
        let engine = AVAudioEngine()
        let processing = prepare(engine.inputNode, inputDevice: inputDevice)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return .failed(.noInput)
        }
        guard let pipeline = MicrophoneEncoderPipeline(input: format, processing: processing, sink: sink)
        else {
            return .failed(.encoderFailed)
        }
        let sink = AVAudioSinkNode(receiverBlock: receiver(pipeline, format: format))
        engine.attach(sink)
        engine.connect(engine.inputNode, to: sink, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.disconnectNodeInput(sink)
            engine.detach(sink)
            return .failed(.startFailed(LogFormat.error(error)))
        }
        report(.info, "Microphone capture opened at \(Int(format.sampleRate)) Hz with \(format.channelCount) "
            + "channel(s) through a sink node, sending 48 kHz Opus to the console")
        return .opened(OpenedEngine(engine: engine, sink: sink, format: format))
    }

    private nonisolated static func stopEngine(_ opened: OpenedEngine) {
        audioQueue.async {
            opened.engine.stop()
            opened.engine.disconnectNodeInput(opened.sink)
            opened.engine.detach(opened.sink)
        }
    }

    private func install(_ opened: OpenedEngine, operation: UUID) -> Capture {
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: opened.engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configurationChanged(operation)
            }
        }
        return Capture(engine: opened.engine, sink: opened.sink, format: opened.format, observer: observer)
    }
}

extension MicrophoneCapture {
    /// Selects the preferred input, enables voice processing and makes sure the selection survives it.
    /// - Parameters:
    ///   - input: The engine's input node.
    ///   - inputDevice: The name of the preferred input, or `nil` for the system default.
    /// - Returns: `voice` when voice processing ended up enabled, otherwise `raw`.
    nonisolated static func prepare(_ input: AVAudioInputNode, inputDevice: String?) -> MicrophoneProcessing {
        let selected = select(inputDevice, on: input)
        enableVoiceProcessing(on: input)
        keep(selected, named: inputDevice, on: input)
        return input.isVoiceProcessingEnabled
            ? .voice
            : .raw
    }

    /// Turns on voice processing with minimal ducking of other audio, logging a warning if it cannot be
    /// enabled.
    /// - Parameter input: The engine's input node.
    nonisolated static func enableVoiceProcessing(on input: AVAudioInputNode) {
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            report(
                .warning,
                "Voice processing could not be enabled (\(LogFormat.error(error))); the microphone is "
                    + "captured without noise and echo suppression"
            )
            return
        }
        input
            .voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
    }

    /// Points the input node at the named input, logging a warning and using the system default when it is
    /// not connected.
    /// - Parameters:
    ///   - name: The name of the preferred input, or `nil` for the system default.
    ///   - input: The engine's input node.
    /// - Returns: The selected device, or `nil` when the default is used.
    nonisolated static func select(_ name: String?, on input: AVAudioInputNode) -> MicrophoneInputDevices
        .DeviceID? {
        guard let name else {
            return nil
        }
        guard let device = MicrophoneInputDevices.device(named: name) else {
            report(.warning, "Microphone \"\(name)\" is not connected; the system default input is used")
            return nil
        }
        MicrophoneInputDevices.assign(device, on: input)
        return device
    }

    /// Reapplies the selected input after voice processing may have switched it, giving up voice processing
    /// if that is the only way to keep it and falling back to the default otherwise.
    /// - Parameters:
    ///   - selected: The device chosen by ``MicrophoneCapture/select(_:on:)``.
    ///   - name: The preferred input's name, used in warnings.
    ///   - input: The engine's input node.
    nonisolated static func keep(_ selected: MicrophoneInputDevices.DeviceID?, named name: String?,
                                 on input: AVAudioInputNode) {
        guard let selected, let name else {
            return
        }
        if MicrophoneInputDevices.current(input) != selected {
            MicrophoneInputDevices.assign(selected, on: input)
        }
        guard MicrophoneInputDevices.current(input) != selected else {
            return
        }
        try? input.setVoiceProcessingEnabled(false)
        MicrophoneInputDevices.assign(selected, on: input)
        guard MicrophoneInputDevices.current(input) == selected else {
            report(.warning, "Microphone \"\(name)\" could not be kept; the system default input is used")
            enableVoiceProcessing(on: input)
            return
        }
        report(
            .warning,
            "Microphone \"\(name)\" could not be kept with voice processing on; it is captured without "
                + "noise and echo suppression"
        )
    }
}

/// Drives the mute light on the controller that owns the microphone so it shows whether the microphone is
/// live.
@MainActor final class MicrophoneLight {
    private let backend: SDLControllerBackend
    private var device: UInt32?
    private var lit = false

    /// Creates the light over the app's controller backend.
    ///
    /// - Parameter backend: The backend that lights the controllers.
    init(backend: SDLControllerBackend) {
        self.backend = backend
    }

    /// Moves the light to a different controller, turning it off on the previous one.
    /// - Parameter device: The SDL instance id of the controller, or `nil` for none.
    func attach(_ device: UInt32?) {
        let timing = SlowStep("updating the microphone light")
        defer {
            timing.finish()
        }
        guard device != self.device else {
            return
        }
        if let previous = self.device, lit {
            backend.microphoneLight(previous, lit: false)
        }
        self.device = device
        apply()
    }

    /// Turns the light on or off on the attached controller.
    /// - Parameter lit: Whether the light should be on.
    func indicate(_ lit: Bool) {
        guard lit != self.lit else {
            return
        }
        self.lit = lit
        apply()
    }

    private func apply() {
        guard let device else {
            return
        }
        backend.microphoneLight(device, lit: lit)
    }
}

extension StreamSessionClient {
    /// Returns this client with the microphone operations the app runs with, over one capture engine.
    ///
    /// - Parameter light: The microphone light on the controller that owns the microphone button.
    /// - Returns: A copy whose microphone operations capture into the live stream.
    func capturingMicrophone(light: MicrophoneLight) -> Self {
        capturing(MicrophoneCapture(), light: light)
    }

    private func capturing(_ microphone: MicrophoneCapture, light: MicrophoneLight) -> Self {
        var client = self
        client.microphoneStartPreference = {
            @Dependency(\.settings) var settingsStore
            return await StreamSettingsLoader(settings: settingsStore).sound().startWithMicrophone
        }
        client.requestMicrophonePermission = {
            await MicrophoneCapture.requestPermission()
        }
        client.captureMicrophone = { operation in
            AsyncStream { continuation in
                @Dependency(\.streamLeases) var streamLeases
                @Dependency(\.settings) var settingsStore
                let leases = streamLeases
                let settings = StreamSettingsLoader(settings: settingsStore)
                let task = Task { @MainActor in
                    let inputDevice = await settings.sound().inputDevice
                    guard !Task.isCancelled else {
                        return
                    }
                    let player = (leases.current?.player as? NativeStreamPlayer)?.native
                    let failure = await microphone.start(
                        operation,
                        player: player,
                        inputDevice: inputDevice
                    ) {
                        continuation.yield(.failed($0))
                    }
                    guard !Task.isCancelled else {
                        return
                    }
                    continuation.yield(failure.map(MicrophoneCaptureEvent.failed) ?? .started)
                }
                continuation.onTermination = { _ in
                    task.cancel()
                    Task { @MainActor in
                        microphone.stop(operation)
                    }
                }
            }
        }
        client.setMicrophoneMuted = { operation, muted in
            await microphone.setMuted(operation, muted: muted)
        }
        client.indicateMicrophone = { lit in
            await light.indicate(lit)
        }
        return client
    }
}
