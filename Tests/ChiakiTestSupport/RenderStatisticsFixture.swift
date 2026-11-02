import ChiakiModels
import Foundation

extension RenderStatistics {
    /// Statistics built from named values, the way tests describe a stream.
    ///
    /// - Parameter raw: The values by field name; a missing name reads as zero.
    public init(fixture raw: [String: NSNumber]) {
        self.init()
        let int = { (key: String) in
            raw[key]?.intValue ?? 0
        }
        let double = { (key: String) in
            raw[key]?.doubleValue ?? 0
        }
        let bool = { (key: String) in
            raw[key]?.boolValue ?? false
        }
        for (key, path) in Self.fixtureInts {
            self[keyPath: path] = int(key)
        }
        for (key, path) in Self.fixtureDoubles {
            self[keyPath: path] = double(key)
        }
        for (key, path) in Self.fixtureBools {
            self[keyPath: path] = bool(key)
        }
        frameGenerationGenerated = raw["frameGenerationGenerated"]?.intValue
        if bool("serverPresent") {
            var reported = CloudServerStatistics()
            reported.availableDownKbps = int("serverAvailableDownKbps")
            reported.usedDownKbps = int("serverUsedDownKbps")
            reported.usedUpKbps = int("serverUsedUpKbps")
            reported.roundTripMilliseconds = int("serverRoundTripMilliseconds")
            reported.lossPercent = double("serverLossPercent")
            reported.upstreamLossPercent = double("serverUpstreamLossPercent")
            reported.audioChannels = int("serverAudioChannels")
            reported.width = int("serverWidth")
            reported.height = int("serverHeight")
            reported.corruptFrames = int("serverCorruptFrames")
            server = reported
        }
    }

    private static let fixtureInts: [(String, WritableKeyPath<RenderStatistics, Int> & Sendable)] = [
        ("received", \.received),
        ("bytes", \.bytes),
        ("lost", \.lost),
        ("recovered", \.recovered),
        ("decoderFailures", \.decoderFailures),
        ("surfaces", \.surfaces),
        ("coreVideoUnits", \.coreVideoUnits),
        ("coreRejectedPackets", \.coreRejectedPackets),
        ("coreCryptoRejections", \.coreCryptoRejections),
        ("coreAssembledVideo", \.coreAssembledVideo),
        ("coreDependencyRejections", \.coreDependencyRejections),
        ("coreAssemblyRejections", \.coreAssemblyRejections),
        ("coreFecRepaired", \.coreFecRepaired),
        ("coreVideoStale", \.coreVideoStale),
        ("coreVideoMetadata", \.coreVideoMetadata),
        ("coreVideoDuplicate", \.coreVideoDuplicate),
        ("coreVideoInvalid", \.coreVideoInvalid),
        ("takionVersion", \.takionVersion),
        ("extensionLost", \.extensionLost),
        ("tosLastDSCP", \.tosLastDSCP),
        ("tosLastECN", \.tosLastECN),
        ("keyframeRequests", \.keyframeRequests),
        ("corePacketsReceived", \.corePacketsReceived),
        ("coreReorderSkipped", \.coreReorderSkipped),
        ("coreReorderDropped", \.coreReorderDropped),
        ("coreDroppedPosts", \.coreDroppedPosts),
        ("coreSendDropped", \.coreSendDropped),
        ("coreLoopErrors", \.coreLoopErrors),
        ("grantedHeight", \.grantedHeight),
        ("grantedFPS", \.grantedFPS),
        ("grantedBitrate", \.grantedBitrate),
        ("audioDroppedFrames", \.audioDroppedFrames),
        ("audioPushedFrames", \.audioPushedFrames),
        ("deliverySlowVideo", \.deliverySlowVideo),
        ("deliverySlowAudio", \.deliverySlowAudio),
        ("deliveryGaps", \.deliveryGaps),
        ("deliveryLongestVideoMicroseconds", \.deliveryLongestVideoMicroseconds),
        ("deliveryLongestAudioMicroseconds", \.deliveryLongestAudioMicroseconds),
        ("deliveryLongestGapMicroseconds", \.deliveryLongestGapMicroseconds),
        ("audioTrims", \.audioTrims),
        ("audioTrimmedFrames", \.audioTrimmedFrames),
        ("audioUnderruns", \.audioUnderruns),
        ("audioOverflows", \.audioOverflows),
        ("audioBufferedFrames", \.audioBufferedFrames),
        ("audioMaximumBufferedFrames", \.audioMaximumBufferedFrames),
        ("audioChannels", \.audioChannels),
        ("audioSampleRate", \.audioSampleRate),
        ("audioReceivedChannels", \.audioReceivedChannels),
        ("audioReceivedSampleRate", \.audioReceivedSampleRate),
        ("audioReceivedActiveChannels", \.audioReceivedActiveChannels),
        ("audioConcealmentFrames", \.audioConcealmentFrames),
        ("audioState", \.audioState),
        ("audioDeviceFailures", \.audioDeviceFailures),
        ("requestedHeight", \.requestedHeight),
        ("requestedFPS", \.requestedFPS),
        ("rttSamples", \.rttSamples),
        ("requestedBitrate", \.requestedBitrate),
        ("route", \.route),
        ("routeConsole", \.routeConsole),
        ("submitted", \.submitted),
        ("completed", \.completed),
        ("rejected", \.rejected),
        ("noDrawable", \.noDrawable),
        ("generatedDrops", \.generatedDrops),
        ("replacedFrames", \.replacedFrames),
        ("idleTicks", \.idleTicks),
        ("deadlineMisses", \.deadlineMisses),
        ("gpuError", \.gpuError),
        ("sourceWidth", \.sourceWidth),
        ("sourceHeight", \.sourceHeight),
        ("outputWidth", \.outputWidth),
        ("outputHeight", \.outputHeight),
        ("toneMapSource", \.toneMapSource),
        ("presentationFrameRate", \.presentationFrameRate),
        ("displayMaximumFPS", \.displayMaximumFPS),
        ("lightMeasurements", \.light.measurements)
    ]

    private static let fixtureDoubles: [(String, WritableKeyPath<RenderStatistics, Double> & Sendable)] = [
        ("rttSmoothedMicroseconds", \.rttSmoothedMicroseconds),
        ("rttVariationMicroseconds", \.rttVariationMicroseconds),
        ("rttP99Microseconds", \.rttP99Microseconds),
        ("rttRecentMaxMicroseconds", \.rttRecentMaxMicroseconds),
        ("extensionJitterMicroseconds", \.extensionJitterMicroseconds),
        ("extensionLossRatio", \.extensionLossRatio),
        ("videoThroughputBPS", \.videoThroughputBPS),
        ("videoLossRatio", \.videoLossRatio),
        ("videoTransferTimeMicroseconds", \.videoTransferTimeMicroseconds),
        ("streamSeconds", \.streamSeconds),
        ("contentPeakNits", \.contentPeakNits),
        ("gpuMilliseconds", \.gpuMilliseconds),
        ("displayMaximumEDR", \.displayMaximumEDR),
        ("displayPotentialEDR", \.displayPotentialEDR),
        ("lightSeconds", \.light.seconds),
        ("lightPeakNits", \.light.peakNits),
        ("lightAverageNits", \.light.averageNits),
        ("lightAbovePercent", \.light.abovePercent),
        ("maxCLL", \.light.maxCLL),
        ("maxFALL", \.light.maxFALL),
        ("sessionAbovePercent", \.light.sessionAbovePercent),
        ("sessionNearWhitePercent", \.light.sessionNearWhitePercent),
        ("markerNits", \.light.markerNits)
    ]

    private static let fixtureBools: [(String, WritableKeyPath<RenderStatistics, Bool> & Sendable)] = [
        ("coreDiagnosticsAvailable", \.coreDiagnosticsAvailable),
        ("takionVersionKnown", \.takionVersionKnown),
        ("rttPresent", \.rttPresent),
        ("extensionPresent", \.extensionPresent),
        ("videoMetricsPresent", \.videoMetricsPresent),
        ("tosPresent", \.tosPresent),
        ("tosLastPresent", \.tosLastPresent),
        ("grantedPresent", \.grantedPresent),
        ("requestedHEVC", \.requestedHEVC),
        ("requestedHDR", \.requestedHDR),
        ("spatialUpscaling", \.spatialUpscaling),
        ("advancedSpatial", \.advancedSpatial),
        ("advancedBudgetFallback", \.advancedBudgetFallback),
        ("tenBit", \.tenBit),
        ("pq", \.perceptualQuantizer),
        ("bt2020", \.bt2020),
        ("layerHDR", \.layerHDR),
        ("markerFollowsPointer", \.light.markerFollowsPointer),
        ("markerVisible", \.light.markerVisible)
    ]
}
