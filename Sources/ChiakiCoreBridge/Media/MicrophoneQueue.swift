import ChiakiBridge

/// Hands captured microphone samples from the real-time input thread to the thread that encodes them.
///
/// One thread pushes and one thread pulls. ``push(_:)`` never waits, locks or allocates, so the audio input
/// callback can call it. When the queue holds more than the target delay for a while it skips ahead to the
/// target, so microphone delay does not build up.
public final class MicrophoneQueue: @unchecked Sendable {
    private let queue: chiaki_bridge.MicrophoneQueue

    /// Creates a queue, or `nil` when the core cannot make one for the format.
    ///
    /// - Parameters:
    ///   - channels: Interleaved channels of each pushed sample frame.
    ///   - sampleRate: Frames per second.
    ///   - targetMilliseconds: The delay the queue keeps.
    public init?(channels: Int, sampleRate: Int, targetMilliseconds: Int) {
        guard let queue = chiaki_bridge.MicrophoneQueue.create(
            UInt32(channels),
            UInt32(sampleRate),
            UInt32(targetMilliseconds)
        ).value else {
            return nil
        }
        self.queue = queue
    }

    /// Queues interleaved samples, dropping the newest when the queue is full.
    ///
    /// - Parameter samples: Whole frames of interleaved samples.
    public func push(_ samples: UnsafeBufferPointer<Int16>) {
        queue.push(chiaki_bridge.MicrophonePcm(samples))
    }

    /// Takes queued samples, filling what is missing with silence.
    ///
    /// - Parameter samples: Where the interleaved samples go.
    /// - Returns: The frames of audio taken before the silence.
    public func pull(into samples: UnsafeMutableBufferPointer<Int16>) -> Int {
        queue.pull(chiaki_bridge.MicrophoneSamples(samples))
    }

    /// The frames ready to be pulled.
    public var bufferedFrames: Int {
        Int(queue.buffered_frames())
    }
}
