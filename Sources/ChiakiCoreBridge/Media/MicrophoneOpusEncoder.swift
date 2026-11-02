import ChiakiBridge

/// Encodes microphone audio into the Opus frames the console accepts.
///
/// The encoder is not thread safe; one capture pipeline owns it.
public final class MicrophoneOpusEncoder: @unchecked Sendable {
    /// The sample rate the encoder takes.
    public static let sampleRate = Int(chiaki_bridge.MicrophoneEncoder.sample_rate())

    /// The channels the encoder takes.
    public static let channels = Int(chiaki_bridge.MicrophoneEncoder.channels())

    /// The samples per channel in one frame.
    public static let samplesPerFrame = Int(chiaki_bridge.MicrophoneEncoder.samples_per_frame())

    /// The bytes in one encoded frame.
    public static let frameSize = Int(chiaki_bridge.MicrophoneEncoder.frame_size())

    private var encoder: chiaki_bridge.MicrophoneEncoder

    /// Creates an encoder, or `nil` when the core cannot make one.
    public init?() {
        guard let encoder = chiaki_bridge.MicrophoneEncoder.create().value else {
            return nil
        }
        self.encoder = encoder
    }

    /// Encodes one frame of interleaved samples.
    ///
    /// - Parameters:
    ///   - pcm: ``samplesPerFrame`` times ``channels`` samples.
    ///   - frame: Receives ``frameSize`` bytes.
    /// - Returns: Whether the frame was encoded.
    public func encode(_ pcm: UnsafeBufferPointer<Int16>,
                       into frame: UnsafeMutableBufferPointer<UInt8>) -> Bool {
        encoder.encode(chiaki_bridge.MicrophonePcm(pcm), chiaki_bridge.MicrophoneFrame(frame))
    }
}
