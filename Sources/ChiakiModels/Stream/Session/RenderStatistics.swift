import Foundation

/// The renderer's, decoder's, transport's and audio's statistics for a live stream, decoded once from the
/// player.
///
/// Counters accumulate from the start of the stream. A value the player did not report reads as zero or
/// `false`, except ``frameGenerationGenerated``, which is `nil` while frame generation is not running.
public struct RenderStatistics: Equatable, Sendable {
    /// Video units received.
    public var received = 0
    /// Video bytes received.
    public var bytes = 0
    /// Video frames lost.
    public var lost = 0
    /// Frames shown after being pointed at an older reference picture because their own was lost.
    public var recovered = 0
    /// Frames the decoder failed.
    public var decoderFailures = 0
    /// Decoded surfaces handed to the renderer.
    public var surfaces = 0
    /// Whether the core reports transport diagnostics.
    public var coreDiagnosticsAvailable = false
    /// Video units the core received.
    public var coreVideoUnits = 0
    /// Packets the core rejected.
    public var coreRejectedPackets = 0
    /// Packets that failed authentication.
    public var coreCryptoRejections = 0
    /// Frames the core assembled.
    public var coreAssembledVideo = 0
    /// Frames rejected while waiting for a keyframe.
    public var coreDependencyRejections = 0
    /// Frames the core could not assemble.
    public var coreAssemblyRejections = 0
    /// Frames the core completed from FEC parity units.
    public var coreFecRepaired = 0
    /// Video units that arrived too late.
    public var coreVideoStale = 0
    /// Video units that only carried metadata.
    public var coreVideoMetadata = 0
    /// Duplicate video units.
    public var coreVideoDuplicate = 0
    /// Malformed video units.
    public var coreVideoInvalid = 0
    /// The Takion protocol version.
    public var takionVersion = 0
    /// Whether ``takionVersion`` is known.
    public var takionVersionKnown = false
    /// Whether the round trip time is measured.
    public var rttPresent = false
    /// The smoothed round trip time in microseconds.
    public var rttSmoothedMicroseconds = 0.0
    /// The round trip time's variation in microseconds.
    public var rttVariationMicroseconds = 0.0
    /// The round trip samples taken during the stream.
    public var rttSamples = 0
    /// The 99th percentile of the stream's latest round trips, in microseconds.
    public var rttP99Microseconds = 0.0
    /// The largest round trip of the last ten seconds, in microseconds; 0 when none arrived in that time.
    public var rttRecentMaxMicroseconds = 0.0
    /// Whether the console reports extension metrics.
    public var extensionPresent = false
    /// The jitter the console reports, in microseconds.
    public var extensionJitterMicroseconds = 0.0
    /// The packets the console reports lost.
    public var extensionLost = 0
    /// The loss ratio the console reports, from 0 to 1.
    public var extensionLossRatio = 0.0
    /// Whether the core measures video metrics.
    public var videoMetricsPresent = false
    /// The video throughput in bits per second.
    public var videoThroughputBPS = 0.0
    /// The video loss ratio, from 0 to 1.
    public var videoLossRatio = 0.0
    /// How long a video frame takes to arrive, in microseconds.
    public var videoTransferTimeMicroseconds = 0.0
    /// Whether packets carry a type of service marking.
    public var tosPresent = false
    /// Whether the last packet carried a type of service marking.
    public var tosLastPresent = false
    /// The last packet's DSCP value.
    public var tosLastDSCP = 0
    /// The last packet's ECN value.
    public var tosLastECN = 0
    /// Keyframes requested from the console.
    public var keyframeRequests = 0
    /// Packets the core received.
    public var corePacketsReceived = 0
    /// Packets skipped while reordering.
    public var coreReorderSkipped = 0
    /// Packets dropped while reordering.
    public var coreReorderDropped = 0
    /// Events the core dropped internally.
    public var coreDroppedPosts = 0
    /// Packets the core could not send.
    public var coreSendDropped = 0
    /// Errors in the core's network loop.
    public var coreLoopErrors = 0
    /// Whether the console reported the stream it granted.
    public var grantedPresent = false
    /// The granted height.
    public var grantedHeight = 0
    /// The granted frame rate.
    public var grantedFPS = 0
    /// The granted bitrate in kbps.
    public var grantedBitrate = 0
    /// Audio frames dropped because the playback buffer was full.
    public var audioDroppedFrames = 0
    /// Audio frames decoded and handed to playback.
    public var audioPushedFrames = 0
    /// Video frames whose hand-off from the core's session thread took 8 ms or more.
    public var deliverySlowVideo = 0
    /// Audio packets whose hand-off from the core's session thread, decoding included, took 8 ms or more.
    public var deliverySlowAudio = 0
    /// Times the core's session thread delivered no media for 50 ms or more.
    public var deliveryGaps = 0
    /// The longest video hand-off so far, in microseconds.
    public var deliveryLongestVideoMicroseconds = 0
    /// The longest audio hand-off so far, decoding included, in microseconds.
    public var deliveryLongestAudioMicroseconds = 0
    /// The longest time so far without media from the core's session thread, in microseconds.
    public var deliveryLongestGapMicroseconds = 0
    /// Times playback skipped ahead to its target delay after the buffer stayed too full.
    public var audioTrims = 0
    /// Audio frames skipped to bring playback back to its target delay.
    public var audioTrimmedFrames = 0
    /// Times audio ran out.
    public var audioUnderruns = 0
    /// Times audio overflowed.
    public var audioOverflows = 0
    /// Audio frames buffered for playback.
    public var audioBufferedFrames = 0
    /// The most audio frames ever buffered.
    public var audioMaximumBufferedFrames = 0
    /// The playback channels.
    public var audioChannels = 0
    /// The playback sample rate.
    public var audioSampleRate = 0
    /// The channels the console sends.
    public var audioReceivedChannels = 0
    /// The sample rate the console sends.
    public var audioReceivedSampleRate = 0
    /// The received channels that carry sound.
    public var audioReceivedActiveChannels = 0
    /// Audio frames concealed after a loss.
    public var audioConcealmentFrames = 0
    /// The audio output's state.
    public var audioState = 0
    /// Times the audio output device failed.
    public var audioDeviceFailures = 0
    /// The requested height.
    public var requestedHeight = 0
    /// The requested frame rate.
    public var requestedFPS = 0
    /// The requested bitrate in kbps.
    public var requestedBitrate = 0
    /// Whether HEVC was requested.
    public var requestedHEVC = false
    /// Whether HDR was requested.
    public var requestedHDR = false
    /// The route the stream takes, as the player's route value.
    public var route = 0
    /// The console the route reaches, as the player's console value.
    public var routeConsole = 0
    /// Seconds since the stream started.
    public var streamSeconds = 0.0
    /// Frames generated by frame generation, or `nil` while it is not running.
    public var frameGenerationGenerated: Int?
    /// Frames submitted to the renderer.
    public var submitted = 0
    /// Frames the renderer completed.
    public var completed = 0
    /// Frames the renderer rejected.
    public var rejected = 0
    /// Frames rejected because no drawable was free.
    public var noDrawable = 0
    /// Generated frames dropped.
    public var generatedDrops = 0
    /// Frames replaced by a newer one before presentation.
    public var replacedFrames = 0
    /// Display refreshes with no new frame.
    public var idleTicks = 0
    /// Presentation deadlines missed.
    public var deadlineMisses = 0
    /// The last GPU error, or `0`.
    public var gpuError = 0
    /// Whether the picture is upscaled.
    public var spatialUpscaling = false
    /// Whether the neural upscaler runs.
    public var advancedSpatial = false
    /// Whether the neural upscaler fell back for the frame budget.
    public var advancedBudgetFallback = false
    /// The decoded width.
    public var sourceWidth = 0
    /// The decoded height.
    public var sourceHeight = 0
    /// The rendered width.
    public var outputWidth = 0
    /// The rendered height.
    public var outputHeight = 0
    /// Whether the video is 10-bit.
    public var tenBit = false
    /// Whether the video uses the PQ transfer function.
    public var perceptualQuantizer = false
    /// Whether the video uses BT.2020 primaries.
    public var bt2020 = false
    /// Whether the layer presents in HDR.
    public var layerHDR = false
    /// Where tone mapping takes the content's peak from.
    public var toneMapSource = 0
    /// The content's peak brightness in nits.
    public var contentPeakNits = 0.0
    /// The GPU time per frame in milliseconds.
    public var gpuMilliseconds = 0.0
    /// The presentation frame rate.
    public var presentationFrameRate = 0
    /// The display's maximum refresh rate.
    public var displayMaximumFPS = 0
    /// The display's current EDR headroom.
    public var displayMaximumEDR = 0.0
    /// The EDR headroom the display could reach, which can exceed ``displayMaximumEDR`` while macOS
    /// holds headroom back.
    public var displayPotentialEDR = 0.0
    /// The light levels measured in the picture.
    public var light = StreamLightLevels()
    /// The measurements a PS5 cloud server reports, or `nil` when the server reports none.
    public var server: CloudServerStatistics?

    /// Creates statistics with every value zero.
    public init() {}
}

/// The measurements a PS5 cloud server reports about the stream it sends.
public struct CloudServerStatistics: Equatable, Sendable {
    /// The downstream bandwidth the server sees available, in kbps; zero when it did not say.
    public var availableDownKbps = 0

    /// The downstream bandwidth the stream uses, in kbps.
    public var usedDownKbps = 0

    /// The upstream bandwidth the stream uses, in kbps.
    public var usedUpKbps = 0

    /// The round trip time the server measures, in milliseconds.
    public var roundTripMilliseconds = 0

    /// The downstream loss, in percent.
    public var lossPercent = 0.0

    /// The upstream loss, in percent.
    public var upstreamLossPercent = 0.0

    /// The audio channels the server sends.
    public var audioChannels = 0

    /// The width of the picture the server sends.
    public var width = 0

    /// The height of the picture the server sends.
    public var height = 0

    /// The frames the server reports as corrupt.
    public var corruptFrames = 0

    /// Creates measurements with every value zero.
    public init() {}
}

/// The light levels the renderer measures in the picture while stream diagnostics or a video analysis show.
///
/// Each measurement window starts fresh when measuring is switched on or the picture's dynamic range
/// changes; the maximums cover the whole window.
public struct StreamLightLevels: Equatable, Sendable {
    /// The frames measured in this window.
    public var measurements = 0

    /// How long this window has measured, in seconds.
    public var seconds = 0.0

    /// The brightest pixel of the last measured frame, in nits.
    public var peakNits = 0.0

    /// The average brightness of the last measured frame, in nits.
    public var averageNits = 0.0

    /// The share of the last measured frame above SDR white, in percent.
    public var abovePercent = 0.0

    /// The brightest pixel of the window, in nits.
    public var maxCLL = 0.0

    /// The brightest frame average of the window, in nits.
    public var maxFALL = 0.0

    /// The largest share of a frame above SDR white in the window, in percent.
    public var sessionAbovePercent = 0.0

    /// The largest share of a frame near SDR white in the window, in percent.
    public var sessionNearWhitePercent = 0.0

    /// The brightness under the marker, in nits.
    public var markerNits = 0.0

    /// Whether the marker follows the pointer rather than a placed point.
    public var markerFollowsPointer = false

    /// Whether the marker shows.
    public var markerVisible = false

    /// Creates levels with nothing measured.
    public init() {}
}
