import ChiakiBridge
import ChiakiModels

/// Reads the statistics the core keeps for a running stream into `RenderStatistics`.
///
/// Only the decoder, transport, granted picture and audio values come from the core; the renderer fills in its
/// own.
public enum StreamStatisticsReader {
    /// The core's statistics as render statistics.
    ///
    /// - Parameter statistics: What the core reported.
    /// - Returns: Statistics with every core value filled in and the renderer's left at zero.
    public static func statistics(of statistics: chiaki_bridge.StreamStatistics) -> RenderStatistics {
        var read = RenderStatistics()
        read.received = Int(statistics.units)
        read.bytes = Int(statistics.bytes)
        read.lost = Int(statistics.lost)
        read.recovered = Int(statistics.recovered)
        read.decoderFailures = Int(statistics.decoder_failures)
        read.surfaces = Int(statistics.surfaces)
        read.keyframeRequests = Int(statistics.keyframe_requests)
        read.coreLoopErrors = Int(statistics.loop_errors)
        if let version = statistics.protocol_version.value {
            read.takionVersion = Int(version)
            read.takionVersionKnown = true
        }
        if let link = statistics.link.value {
            readLink(link, into: &read)
        }
        if let granted = statistics.granted.value {
            read.grantedPresent = true
            read.grantedHeight = Int(granted.height)
            read.grantedFPS = Int(granted.max_fps)
            read.grantedBitrate = Int(granted.bitrate_kbps)
        }
        readAudio(statistics.audio, into: &read)
        read.deliverySlowVideo = Int(statistics.delivery.slow_video)
        read.deliverySlowAudio = Int(statistics.delivery.slow_audio)
        read.deliveryGaps = Int(statistics.delivery.gaps)
        read.deliveryLongestVideoMicroseconds = Int(statistics.delivery.longest_video_us)
        read.deliveryLongestAudioMicroseconds = Int(statistics.delivery.longest_audio_us)
        read.deliveryLongestGapMicroseconds = Int(statistics.delivery.longest_gap_us)
        return read
    }

    private static func readLink(_ link: chiaki_bridge.LinkFacts, into read: inout RenderStatistics) {
        read.coreDiagnosticsAvailable = true
        read.coreVideoUnits = Int(link.video_units)
        read.coreRejectedPackets = Int(link.rejected_packets)
        read.coreCryptoRejections = Int(link.crypto_rejections)
        read.coreAssembledVideo = Int(link.assembled_video)
        read.coreDependencyRejections = Int(link.dependency_rejections)
        read.coreAssemblyRejections = Int(link.assembly_rejections)
        read.coreFecRepaired = Int(link.fec_repaired_frames)
        read.coreVideoStale = Int(link.video_stale)
        read.coreVideoMetadata = Int(link.video_metadata)
        read.coreVideoDuplicate = Int(link.video_duplicate)
        read.coreVideoInvalid = Int(link.video_invalid)
        read.coreReorderSkipped = Int(link.reorder_skipped)
        read.coreReorderDropped = Int(link.reorder_dropped)
        read.coreDroppedPosts = Int(link.dropped_posts)
        read.coreSendDropped = Int(link.send_dropped)
        if let roundTrip = link.round_trip.value {
            read.rttPresent = true
            read.rttSmoothedMicroseconds = Double(roundTrip.smoothed_us)
            read.rttVariationMicroseconds = Double(roundTrip.variation_us)
            read.rttSamples = Int(roundTrip.samples)
            read.rttP99Microseconds = Double(roundTrip.p99_us)
            read.rttRecentMaxMicroseconds = Double(roundTrip.recent_max_us)
        }
        if let reception = link.reception.value {
            read.extensionPresent = true
            read.extensionJitterMicroseconds = Double(reception.jitter_us)
            read.extensionLost = Int(reception.lost)
            read.extensionLossRatio = reception.loss_ratio
            read.corePacketsReceived = Int(reception.received)
        }
        if let metrics = link.video_metrics.value {
            read.videoMetricsPresent = true
            read.videoThroughputBPS = Double(metrics.throughput_bps)
            read.videoLossRatio = metrics.loss_ratio
            read.videoTransferTimeMicroseconds = Double(metrics.transfer_time_us)
        }
        if let marks = link.service_marks.value {
            read.tosPresent = true
            if let dscp = marks.last_dscp.value, let ecn = marks.last_ecn.value {
                read.tosLastPresent = true
                read.tosLastDSCP = Int(dscp)
                read.tosLastECN = Int(ecn)
            }
        }
        if let server = link.server.value {
            var reported = CloudServerStatistics()
            reported.availableDownKbps = Int(server.available_down_kbps)
            reported.usedDownKbps = Int(server.used_down_kbps)
            reported.usedUpKbps = Int(server.used_up_kbps)
            reported.roundTripMilliseconds = Int(server.round_trip_ms)
            reported.lossPercent = Double(server.loss_percent)
            reported.upstreamLossPercent = Double(server.upstream_loss_percent)
            reported.audioChannels = Int(server.audio_channels)
            reported.width = Int(server.width)
            reported.height = Int(server.height)
            reported.corruptFrames = Int(server.corrupt_frames)
            read.server = reported
        }
    }

    private static func readAudio(_ audio: chiaki_bridge.AudioStatistics, into read: inout RenderStatistics) {
        read.audioDroppedFrames = Int(audio.dropped_frames)
        read.audioPushedFrames = Int(audio.pcm_frames)
        read.audioTrims = Int(audio.trims)
        read.audioTrimmedFrames = Int(audio.trimmed_frames)
        read.audioUnderruns = Int(audio.underruns)
        read.audioOverflows = Int(audio.overflows)
        read.audioBufferedFrames = Int(audio.buffered_frames)
        read.audioMaximumBufferedFrames = Int(audio.maximum_buffered_frames)
        read.audioChannels = Int(audio.channels)
        read.audioSampleRate = Int(audio.sample_rate)
        read.audioReceivedChannels = Int(audio.received_channels)
        read.audioReceivedSampleRate = Int(audio.received_sample_rate)
        read.audioReceivedActiveChannels = Int(audio.received_active_channels)
        read.audioConcealmentFrames = Int(audio.concealment_frames)
        read.audioState = state(of: audio.state)
        read.audioDeviceFailures = Int(audio.device_failures)
    }

    private static func state(of state: chiaki_bridge.AudioOutputState) -> Int {
        switch state {
        case .created:
            0
        case .configured:
            1
        case .priming:
            2
        case .playing:
            3
        case .stopping:
            4
        case .stopped:
            5
        case .failed:
            6
        }
    }
}
