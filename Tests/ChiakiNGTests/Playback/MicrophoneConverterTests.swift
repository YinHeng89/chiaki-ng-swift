import AVFoundation
import ChiakiCoreBridge
import ChiakiModels
import Testing
@testable import ChiakiNG
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

@Test func voiceProcessedCaptureSendsTheVoiceChannelAtFullLevel() throws {
    let peak = try capturedPeak(channels: 9, signal: 0, processing: .voice)
    #expect(peak.kept == 1)
    #expect(peak.converted > 15000)
}

@Test func rawStereoCaptureKeepsAMicrophoneOnEitherSide() throws {
    let peak = try capturedPeak(
        layout: kAudioChannelLayoutTag_Stereo,
        channels: 2,
        signal: 1,
        processing: .raw
    )
    #expect(peak.kept == 2)
    #expect(peak.converted > 15000)
}

@Test func rawDiscreteCaptureKeepsTheFirstInput() throws {
    let peak = try capturedPeak(channels: 4, signal: 0, processing: .raw)
    #expect(peak.kept == 1)
    #expect(peak.converted > 15000)
}

@Test func theInputCopyClampsToFullScaleAndInterleaves() throws {
    let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo))
    let input = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layout)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4))
    buffer.frameLength = 4
    let channels = try #require(buffer.floatChannelData)
    let left: [Float] = [0, 0.5, 2, -2]
    let right: [Float] = [-0.5, 0, 1, -1]
    for frame in 0..<4 {
        channels[0][frame] = left[frame]
        channels[1][frame] = right[frame]
    }
    let output = UnsafeMutableBufferPointer<Int16>.allocate(capacity: 8)
    defer {
        output.deallocate()
    }
    MicrophoneEncoderPipeline.copy(
        UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
        format: input,
        frames: 0..<4,
        channels: 2,
        into: output
    )
    #expect(Array(output) == [0, -16384, 16384, 0, 32767, 32767, -32767, -32767])
}

@Test func theQueueHandsTheCopiedAudioToTheEncodingSide() throws {
    let queue = try #require(MicrophoneQueue(channels: 1, sampleRate: 48000, targetMilliseconds: 40))
    let samples = (0..<480).map { Int16($0 + 1) }
    samples.withUnsafeBufferPointer { queue.push($0) }
    #expect(queue.bufferedFrames == 480)
    var pulled = [Int16](repeating: 0, count: 480)
    let frames = pulled.withUnsafeMutableBufferPointer { queue.pull(into: $0) }
    #expect(frames == 480)
    #expect(pulled == samples)
}

private func capturedPeak(
    layout tag: AudioChannelLayoutTag? = nil,
    channels count: UInt32,
    signal: Int,
    processing: MicrophoneProcessing
) throws -> (kept: Int, converted: Int) {
    let layout =
        try #require(AVAudioChannelLayout(layoutTag: tag ?? kAudioChannelLayoutTag_DiscreteInOrder | count))
    let input = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layout)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 480))
    buffer.frameLength = 480
    let channels = try #require(buffer.floatChannelData)
    for frame in 0..<480 {
        for channel in 0..<Int(count) {
            channels[channel][frame] = channel == signal
                ? 0.5
                : 0
        }
    }
    let kept = MicrophoneEncoderPipeline.keptChannels(of: input, processing: processing)
    let captured = try #require(MicrophoneEncoderPipeline.capturedFormat(of: input, channels: kept))
    let queued = try #require(AVAudioPCMBuffer(pcmFormat: captured, frameCapacity: 480))
    queued.frameLength = 480
    let samples = try #require(queued.int16ChannelData?[0])
    MicrophoneEncoderPipeline.copy(
        UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
        format: input,
        frames: 0..<480,
        channels: kept,
        into: UnsafeMutableBufferPointer(start: samples, count: 480 * kept)
    )
    let converter = try #require(MicrophoneEncoderPipeline.converter(from: captured))
    let output = try #require(AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 1024))
    var supplied = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, state in
        if supplied {
            state.pointee = .noDataNow
            return nil
        }
        supplied = true
        state.pointee = .haveData
        return queued
    }
    #expect(status != .error)
    let converted = try #require(output.int16ChannelData?[0])
    #expect(output.frameLength > 0)
    let total = Int(output.frameLength) * Int(output.format.channelCount)
    return (kept, (0..<total).map { abs(Int(converted[$0])) }.max() ?? 0)
}
