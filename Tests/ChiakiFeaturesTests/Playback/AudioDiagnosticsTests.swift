import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing
@testable import ChiakiFeatures
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private func audioReport(_ raw: [String: NSNumber]) -> StreamDiagnosticsReport {
    StreamDiagnosticsReport(telemetry: StreamTelemetry(statistics: RenderStatistics(fixture: raw)))
}

@Test func audioDiagnosticsWaitForReceivedHeader() {
    let report = audioReport(["audioChannels": 2, "audioSampleRate": 48000])
    #expect(String(localized: report.receivedAudioChannels) == "Waiting")
    #expect(String(localized: report.receivedAudioRate) == "Waiting")
    #expect(String(localized: report.playbackAudioChannels) == "2 channels")
}

@Test func audioDiagnosticsShowReceivedFormatWhenPlaybackIsUnavailable() {
    for channels in [1, 2, 6, 8, 12] {
        let report = audioReport([
            "audioReceivedChannels": NSNumber(value: channels),
            "audioReceivedSampleRate": 48000,
            "audioDeviceFailures": 1
        ])
        let label = channels == 1
            ? "channel"
            : "channels"
        #expect(String(localized: report.receivedAudioChannels) == "\(channels) \(label)")
        #expect(String(localized: report.playbackAudioChannels) == "Waiting")
        #expect(String(localized: report.receivedAudioRate) == "48000 Hz")
        #expect(String(localized: report.audioStatus) == "Unavailable")
        #expect(String(localized: report.audioUnderrunsSummary.value) == "Unavailable")
    }
}

@Test func audioDiagnosticsKeepReceivedAndPlaybackFormatsDistinct() {
    let report = audioReport([
        "audioReceivedChannels": 8,
        "audioReceivedSampleRate": 48000,
        "audioChannels": 2,
        "audioSampleRate": 44100
    ])
    #expect(String(localized: report.receivedAudioChannels) == "8 channels")
    #expect(String(localized: report.receivedAudioRate) == "48000 Hz")
    #expect(String(localized: report.playbackAudioChannels) == "2 channels")
}

@Test func audioDiagnosticsShowHowManyReceivedChannelsCarrySound() {
    func report(_ active: Int) -> StreamDiagnosticsReport {
        audioReport([
            "audioReceivedChannels": 8,
            "audioReceivedSampleRate": 48000,
            "audioReceivedActiveChannels": NSNumber(value: active)
        ])
    }
    #expect(String(localized: report(2).receivedAudioChannels) == "8 channels, 2 active")
    #expect(String(localized: report(8).receivedAudioChannels) == "8 channels")
    #expect(String(localized: report(0).receivedAudioChannels) == "8 channels")
}
