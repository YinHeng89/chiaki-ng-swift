import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func streamHealthReportsOncePerWindowAndStaysDebugWhenHealthy() {
    var window = StreamHealthWindow()
    var due = [Double]()
    for step in 0...1000 {
        let now = 10 + Double(step) * 0.01
        if window.poll(at: now) {
            due.append(now)
            let report = window.report(
                RenderStatistics(fixture: ["audioUnderruns": 3]),
                controller: "pad",
                at: now
            )
            #expect(report.level == .debug)
            #expect(report.message.contains("audio underruns +0 (3 total)"))
            #expect(report.message.contains("longest main-thread gap 10 ms"))
        }
    }
    #expect(due.count == 2)
    #expect(abs((due.first ?? 0) - 15) < 0.001)
    #expect(abs((due.last ?? 0) - 20) < 0.001)
}

@Test func streamHealthEscalatesWhenAudioCountersGrow() {
    var window = StreamHealthWindow()
    _ = window.poll(at: 0)
    _ = window.report(
        RenderStatistics(fixture: ["audioUnderruns": 2, "audioDroppedFrames": 5]),
        controller: "pad",
        at: 0
    )
    _ = window.poll(at: 5)
    let report = window.report(
        RenderStatistics(fixture: ["audioUnderruns": 4, "audioDroppedFrames": 5]),
        controller: "pad",
        at: 5
    )
    #expect(report.level == .info)
    #expect(report.message.contains("audio underruns +2 (4 total)"))
    #expect(report.message.contains("dropped frames +0"))
}

@Test func streamHealthCountsPushedFramesWithoutCallingThemAProblem() {
    var window = StreamHealthWindow()
    var reports = [StreamHealthWindow.Report]()
    for step in 0...1000 {
        let now = 10 + Double(step) * 0.01
        if window.poll(at: now) {
            let pushed = NSNumber(value: 1000 + reports.count * 240_000)
            reports.append(window.report(
                RenderStatistics(fixture: ["audioPushedFrames": pushed]),
                controller: "pad",
                at: now
            ))
        }
    }
    #expect(reports.count == 2)
    #expect(reports.last?.level == .debug)
    #expect(reports.last?.message.contains("pushed frames +240000") == true)
    #expect(reports.last?.message.contains("trims +0 (0 frames)") == true)
}

@Test func streamHealthEscalatesWhenPlaybackTrimsItsDelay() {
    var window = StreamHealthWindow()
    _ = window.poll(at: 0)
    _ = window.report(RenderStatistics(fixture: [:]), controller: "pad", at: 0)
    _ = window.poll(at: 5)
    let report = window.report(
        RenderStatistics(fixture: ["audioTrims": 1, "audioTrimmedFrames": 3840]),
        controller: "pad",
        at: 5
    )
    #expect(report.level == .info)
    #expect(report.message.contains("trims +1 (3840 frames)"))
}

@Test func streamHealthReportsVideoPresentationAndEscalatesOnMissedFrames() {
    var window = StreamHealthWindow()
    var reports = [StreamHealthWindow.Report]()
    let windows: [[String: NSNumber]] = [
        ["coreAssembledVideo": 0, "submitted": 0, "completed": 0],
        ["coreAssembledVideo": 300, "submitted": 300, "completed": 300, "idleTicks": 300]
    ]
    for step in 0...1000 {
        let now = 10 + Double(step) * 0.01
        if window.poll(at: now), reports.count < windows.count {
            reports.append(window.report(
                RenderStatistics(fixture: windows[reports.count]),
                controller: "pad",
                at: now
            ))
        }
    }
    #expect(reports.count == 2)
    #expect(reports[1].level == .debug)
    #expect(reports[1].message.contains(
        "video assembled +300, submitted +300, completed +300, replaced +0, rejected +0, no drawable +0, "
            + "deadline misses +0, idle refreshes +300"
    ))
}

@Test func streamHealthReportsHowTheCoreHandedMediaOver() {
    var window = StreamHealthWindow()
    var reports = [StreamHealthWindow.Report]()
    let windows: [[String: NSNumber]] = [
        [:],
        [
            "deliverySlowVideo": 3, "deliverySlowAudio": 1, "deliveryGaps": 2,
            "deliveryLongestVideoMicroseconds": 12_400, "deliveryLongestAudioMicroseconds": 9_000,
            "deliveryLongestGapMicroseconds": 140_000
        ]
    ]
    for step in 0...1000 {
        let now = 10 + Double(step) * 0.01
        if window.poll(at: now), reports.count < windows.count {
            reports.append(window.report(
                RenderStatistics(fixture: windows[reports.count]),
                controller: "pad",
                at: now
            ))
        }
    }
    #expect(reports.count == 2)
    #expect(reports[1].message.contains(
        "delivery slow video +3, slow audio +1, gaps +2, longest video 12 ms, audio 9 ms, gap 140 ms"
    ))
}

@Test func streamHealthEscalatesWhenVideoMissesItsDeadlines() {
    var window = StreamHealthWindow()
    var reports = [StreamHealthWindow.Report]()
    for step in 0...1000 {
        let now = 10 + Double(step) * 0.01
        if window.poll(at: now) {
            let misses = NSNumber(value: reports.count * 4)
            reports.append(window.report(
                RenderStatistics(fixture: ["deadlineMisses": misses, "noDrawable": misses]),
                controller: "pad",
                at: now
            ))
        }
    }
    #expect(reports.count == 2)
    #expect(reports[1].level == .info)
    #expect(reports[1].message.contains("no drawable +4, deadline misses +4"))
}

@Test func streamHealthReportsTheLongestGapAndResetsRumbleEachWindow() {
    var window = StreamHealthWindow()
    _ = window.poll(at: 0)
    _ = window.poll(at: 0.25)
    window.rumbleSent()
    window.rumbleSent()
    _ = window.poll(at: 0.26)
    let stalled = window.report(RenderStatistics(), controller: "pad", at: 0.26)
    #expect(stalled.level == .info)
    #expect(stalled.message.contains("longest main-thread gap 250 ms"))
    #expect(stalled.message.contains("rumble updates 2"))
    _ = window.poll(at: 0.27)
    let calm = window.report(RenderStatistics(), controller: "pad", at: 0.27)
    #expect(calm.level == .debug)
    #expect(calm.message.contains("longest main-thread gap 10 ms"))
    #expect(calm.message.contains("rumble updates 0"))
}

@Test func streamHealthIgnoresTheGapWhileMeasurementIsPaused() {
    var window = StreamHealthWindow()
    _ = window.poll(at: 0)
    _ = window.poll(at: 0.01)
    window.pause()
    _ = window.poll(at: 3)
    _ = window.poll(at: 3.01)
    let report = window.report(RenderStatistics(), controller: "pad", at: 3.01)
    #expect(report.level == .debug)
    #expect(report.message.contains("longest main-thread gap 10 ms"))
}

@Test func streamHealthReportsHowLongInputTookToReachTheStream() {
    var window = StreamHealthWindow()
    _ = window.poll(at: 0)
    let idle = window.report(RenderStatistics(), controller: "pad", at: 0)
    #expect(idle.message.contains("no controller input sent"))
    window.inputSent(delayMicroseconds: 2000)
    window.inputSent(delayMicroseconds: 6000)
    window.inputSent(delayMicroseconds: 20_000_000)
    let report = window.report(RenderStatistics(), controller: "pad", at: 0)
    #expect(report.message.contains("4.0 ms after SDL on average, 6.0 ms at worst (2 batches)"))
    let reset = window.report(RenderStatistics(), controller: "pad", at: 0)
    #expect(reset.message.contains("no controller input sent"))
}

@Test func streamHealthReportsReceivedAndPlaybackAudioFormatsSeparately() {
    var window = StreamHealthWindow()
    let report = window.report(RenderStatistics(fixture: [
        "audioReceivedChannels": 12,
        "audioReceivedSampleRate": 48000,
        "audioChannels": 8,
        "audioSampleRate": 48000
    ]), controller: "pad", at: 0)
    #expect(report.message.contains("received audio 12 channels at 48000 Hz"))
    #expect(report.message.contains("playback input 8 channels at 48000 Hz"))
}

@Test func streamHealthNotesWhenOnlySomeReceivedChannelsCarrySound() {
    var window = StreamHealthWindow()
    let report = window.report(RenderStatistics(fixture: [
        "audioReceivedChannels": 8,
        "audioReceivedActiveChannels": 2,
        "audioReceivedSampleRate": 48000
    ]), controller: "pad", at: 0)
    #expect(report.message.contains("received audio 8 channels (2 active) at 48000 Hz"))
}
