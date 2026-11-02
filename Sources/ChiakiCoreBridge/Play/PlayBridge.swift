import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Answers what the core's play context supports and knows outside of a running stream.
public struct PlayBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// The port guesses an Internet connection may make.
    public static var portGuessRange: ClosedRange<Int> {
        let guessing = chiaki_bridge.PlayBridge.port_guessing()
        return Int(guessing.fewest) ... Int(guessing.most)
    }

    /// The port guesses an Internet connection makes unless told otherwise.
    public static var defaultPortGuesses: Int {
        Int(chiaki_bridge.PlayBridge.port_guessing().usual)
    }

    /// The audio buffer lengths the player accepts, in milliseconds.
    public static var audioBufferRange: ClosedRange<Int> {
        let buffering = chiaki_bridge.PlayBridge.audio_buffering()
        return Int(buffering.shortest_ms) ... Int(buffering.longest_ms)
    }

    /// The audio buffer length the player uses unless told otherwise, in milliseconds.
    public static var defaultAudioBufferMilliseconds: Int {
        Int(chiaki_bridge.PlayBridge.audio_buffering().usual_ms)
    }

    /// The Takion protocol version this build of the core speaks to a target.
    ///
    /// - Parameter target: The kind of stream.
    /// - Returns: The version, or `0` when the build leaves it to negotiation.
    public static func builtProtocolVersion(_ target: TakionTarget) -> UInt32 {
        chiaki_bridge.PlayBridge.built_protocol_version(streamTarget(target))
    }

    /// Whether streams of a kind can carry the console's 3D audio.
    ///
    /// - Parameter target: The kind of stream.
    /// - Returns: The core's answer.
    public static func supportsAudio3D(_ target: SoundTarget) -> Bool {
        chiaki_bridge.PlayBridge.supports_audio_3d(streamTarget(target))
    }

    /// The datacenter measurements the core knows for a cloud service.
    ///
    /// - Parameter service: The cloud service.
    /// - Returns: The measurements, empty when the core is closed.
    public func knownDatacenters(for service: CloudDatacenterService) -> [DatacenterMeasurement] {
        chiaki_bridge.PlayBridge.known_datacenters(Self.generation(service)).map(Self.measurement(of:))
    }

    /// Forgets every datacenter measurement of a cloud service.
    ///
    /// - Parameter service: The cloud service.
    /// - Returns: Whether the core forgot them.
    public func forgetDatacenters(for service: CloudDatacenterService) -> Bool {
        chiaki_bridge.PlayBridge.forget_datacenters(Self.generation(service))
    }

    private static func generation(_ service: CloudDatacenterService) -> libchiaking.catalog
        .ServiceGeneration {
        switch service {
        case .psNow:
            .old_service
        case .psCloud:
            .ps5_cloud
        }
    }

    private static func streamTarget(_ target: TakionTarget) -> chiaki_bridge.StreamTarget {
        switch target {
        case .localPS4:
            .local_ps4
        case .localPS5:
            .local_ps5
        case .psNow:
            .ps_now
        case .psCloud:
            .ps_cloud
        }
    }

    private static func streamTarget(_ target: SoundTarget) -> chiaki_bridge.StreamTarget {
        switch target {
        case .ps4:
            .local_ps4
        case .ps5:
            .local_ps5
        case .psNow:
            .ps_now
        case .psCloud:
            .ps_cloud
        }
    }

    private static func measurement(of facts: chiaki_bridge.DatacenterFacts) -> DatacenterMeasurement {
        DatacenterMeasurement(
            name: String(facts.name),
            roundTripMs: Int(facts.round_trip_ms),
            samplesMs: facts.samples_ms.map { Int($0) },
            mtuIn: Int(facts.mtu_in),
            mtuOut: Int(facts.mtu_out),
            port: Int(facts.port),
            publicAddress: String(facts.public_address),
            maxBandwidth: Int(facts.max_bandwidth),
            measuredAt: Timestamp.date(milliseconds: facts.measured_at_ms),
            bandwidth: facts.bandwidth_kbps > 0
                ? DatacenterBandwidth(
                    kbps: Int(facts.bandwidth_kbps),
                    measuredAt: Timestamp.date(milliseconds: facts.bandwidth_measured_at_ms),
                    roundTripMs: Int(facts.bandwidth_round_trip_ms)
                )
                : nil
        )
    }
}
