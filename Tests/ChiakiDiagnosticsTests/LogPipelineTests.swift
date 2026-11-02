import Foundation
import Synchronization
import Testing
import ChiakiModels
@testable import ChiakiDiagnostics

@Test func loggerFiltersFormatsRotatesAndChangesFolder() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let sink = FileLogSink(settings: .init(directory: folder.path, level: .info), maximumBytes: 400)
    let source = LogSource(file: "Example.swift", function: "connect()", line: 42)
    await sink.record(.coreDiagnostic(severity: 4, message: "debug diagnostic"), source: source)
    #expect(
        !FileManager.default.fileExists(atPath: folder.appendingPathComponent("chiaki.log").path)
    )
    await sink.record(
        .diagnostic(.accounts, .info, "account saved"),
        source: source,
        now: Date(timeIntervalSince1970: 0)
    )
    let text = try String(contentsOf: folder.appendingPathComponent("chiaki.log"), encoding: .utf8)
    #expect(
        text
            == "1970-01-01T00:00:00.000Z [INFO] [Example.swift:42 connect()] Accounts: account saved\n"
    )
    for index in 0..<30 {
        await sink.record(.diagnostic(.app, .info, "line \(index)"), source: source)
    }
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == [
            "chiaki.1.log", "chiaki.2.log", "chiaki.3.log", "chiaki.log"
        ]
    )
    let second = folder.appendingPathComponent("other")
    try await sink.configure(.init(directory: second.path, level: .debug))
    await sink.record(.coreDiagnostic(severity: 4, message: "debug diagnostic"), source: source)
    #expect(
        try String(contentsOf: second.appendingPathComponent("chiaki.log"), encoding: .utf8)
            .contains("[DEBUG]")
    )
    try await sink.configure(.init(directory: second.path, level: .off))
    let before = try Data(contentsOf: second.appendingPathComponent("chiaki.log"))
    await sink.record(.diagnostic(.accounts, .error, "sign-in failed"))
    #expect(try Data(contentsOf: second.appendingPathComponent("chiaki.log")) == before)
}

@Test func loggerReportsUnwritableDestinationWithoutThrowingIntoAuthentication() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer {
        try? FileManager.default.removeItem(at: file)
    }
    let sink = FileLogSink(settings: .init(directory: file.path))
    await sink.record(.diagnostic(.accounts, .error, "sign-in failed"))
    #expect(await sink.writeFailed)
}

@Test func nativeAndFileLoggingShareVerbosityAndOffPolicy() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let messages = Mutex<[String]>([])
    let system = SystemLogSink { _, message, _ in
        messages.withLock { $0.append(message) }
    }
    let sink = FileLogSink(settings: .init(directory: folder.path, level: .error), system: system)
    await sink.record(.diagnostic(.app, .info, "app ready"))
    await sink.record(.diagnostic(.app, .error, "app failed"))
    #expect(messages.withLock { $0 } == ["App: app failed"])
    try await sink.configure(.init(directory: folder.path, level: .off))
    await sink.record(.diagnostic(.accounts, .error, "accountLoad failed"))
    #expect(messages.withLock { $0 } == ["App: app failed"])
    let text = try String(contentsOf: folder.appendingPathComponent("chiaki.log"), encoding: .utf8)
    #expect(text.contains("app failed"))
    #expect(!text.contains("accountLoad"))
}

@Test func failedLogReconfigurationPreservesWorkingDestination() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let sink = FileLogSink(settings: .init(directory: folder.path))
    await sink.record(.diagnostic(.app, .info, "app ready"))
    let invalid = folder.appendingPathComponent("not-a-directory")
    try Data().write(to: invalid)
    await #expect(throws: (any Error).self) {
        try await sink.configure(.init(directory: invalid.path))
    }
    await sink.record(.diagnostic(.accounts, .info, "account saved"))
    #expect(await !sink.writeFailed)
    let text = try String(contentsOf: folder.appendingPathComponent("chiaki.log"), encoding: .utf8)
    #expect(text.contains("App: app ready"))
    #expect(text.contains("Accounts: account saved"))
}

@Test func nativeLoggingSurvivesFileFailureAndFileLoggingRecovers() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: folder)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let messages = Mutex<[String]>([])
    let sink = FileLogSink(settings: .init(directory: folder.path), system: SystemLogSink { _, message, _ in
        messages.withLock { $0.append(message) }
    })
    await sink.record(.diagnostic(.app, .error, "app failed"))
    #expect(await sink.writeFailed)
    #expect(messages.withLock { $0 } == ["App: app failed"])
    try FileManager.default.removeItem(at: folder)
    await sink.record(.diagnostic(.app, .info, "app ready"))
    #expect(await !sink.writeFailed)
    #expect(try String(contentsOf: folder.appendingPathComponent("chiaki.log"), encoding: .utf8)
        .contains("App: app ready"))
}

@Test func fileLoggerAppendsExistingContentAndSerializesConcurrentWriters() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let file = folder.appendingPathComponent("chiaki.log")
    try Data("existing\n".utf8).write(to: file)
    let sink = FileLogSink(settings: .init(directory: folder.path))
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<100 {
            group.addTask {
                await sink.record(.diagnostic(.app, .info, "line \(index)"))
            }
        }
    }
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.hasPrefix("existing\n"))
    #expect(text.split(separator: "\n").count == 101)
    #expect(await !sink.writeFailed)
}

@Test func liveLogIsBoundedFilteredAndSurvivesFileFailure() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let sink = FileLogSink(settings: .init(directory: file.path, level: .error))
    await sink.record(.diagnostic(.app, .info, "app ready"))
    #expect(await sink.snapshot().entries.isEmpty)
    for index in 0..<260 {
        await sink.record(.diagnostic(.playback, .error, "native status \(index)"))
    }
    let snapshot = await sink.snapshot()
    #expect(snapshot.entries.count == 250)
    #expect(snapshot.entries.first?.line.contains("native status 10") == true)
    #expect(snapshot.entries.last?.line.contains("native status 259") == true)
    #expect(snapshot.writeFailed)
    try await sink.configure(.init(directory: file.path, level: .off))
    await sink.record(.diagnostic(.playback, .error, "native status 999"))
    #expect(await sink.snapshot().entries == snapshot.entries)
    #expect(await sink.snapshot().level == .off)
}

@Test func liveLogPreferenceUpgradesOldSettingsAndRoundTrips() throws {
    let old = Data(#"{"directory":"/tmp/logs","level":"debug"}"#.utf8)
    var settings = try JSONDecoder().decode(LogSettings.self, from: old)
    #expect(!settings.showLiveLogButton)
    settings.showLiveLogButton = true
    let encoded = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(LogSettings.self, from: encoded) == settings)
}

@Test func coreDiagnosticsUseSharedLiveFileAndVerbosity() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let sink = FileLogSink(settings: .init(directory: folder.path, level: .info))
    await sink.record(.coreDiagnostic(severity: 4, message: "core debug filtered"))
    await sink.record(.coreDiagnostic(
        severity: 2,
        message: "core attempt=1 sequence=1 local operation=session_init outcome=begin"
    ))
    await sink.record(.coreDiagnostic(
        severity: 0,
        message: "core attempt=1 sequence=2 local operation=session_init outcome=failed"
    ))
    let snapshot = await sink.snapshot()
    #expect(snapshot.entries.count == 2)
    #expect(snapshot.entries[0].line.contains("outcome=begin"))
    #expect(snapshot.entries[1].line.contains("[ERROR]"))
    let text = try String(contentsOf: folder.appendingPathComponent("chiaki.log"), encoding: .utf8)
    #expect(text.contains("sequence=1"))
    #expect(text.contains("sequence=2"))
    #expect(!text.contains("filtered"))
    try await sink.configure(.init(directory: folder.path, level: .off))
    await sink.record(.coreDiagnostic(severity: 0, message: "disabled"))
    #expect(await sink.snapshot().entries.count == 2)
}

@Test func videoRequestLogStatesTheRequestedDynamicRange() {
    #expect(
        LogEvent.videoConfigured(
            height: 1080, framesPerSecond: 60, megabitsPerSecond: 30, codec: "HEVC HDR",
            dynamicRange: .init(ps5: true, hdrCodec: true)
        ).message
            == "Video requested: 1080p 60 fps 30 Mbps HEVC HDR; HEVC HDR requested"
    )
    #expect(
        LogEvent.videoConfigured(
            height: 1080, framesPerSecond: 60, megabitsPerSecond: 30, codec: "HEVC",
            dynamicRange: .init(ps5: true, hdrCodec: false)
        ).message
            == "Video requested: 1080p 60 fps 30 Mbps HEVC; HDR off (setting, codec or screen)"
    )
    #expect(
        LogEvent.videoConfigured(
            height: 720, framesPerSecond: 60, megabitsPerSecond: 10, codec: "H.264",
            dynamicRange: .init(ps5: false, hdrCodec: false)
        ).message
            == "Video requested: 720p 60 fps 10 Mbps H.264; HDR unavailable on PS4"
    )
}

@Test func sinkRedactsIdentifiersOnlyWhileTheSettingIsOn() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let messages = Mutex<[String]>([])
    let sink = FileLogSink(
        settings: .init(directory: folder.path), system: SystemLogSink { _, message, _ in
            messages.withLock { $0.append(message) }
        }, redactor: LogRedactor(salt: Data(repeating: 1, count: 16))
    )
    await sink.record(.consoleDiagnostic("console at 192.168.1.20 MAC aa:bb:cc:dd:ee:ff"))
    var raw = LogSettings(directory: folder.path)
    raw.redactIdentifiers = false
    try await sink.configure(raw)
    await sink.record(.consoleDiagnostic("console at 192.168.1.21"))
    let text = try String(contentsOf: folder.appendingPathComponent("chiaki.log"), encoding: .utf8)
    #expect(!text.contains("192.168.1.20"))
    #expect(text.contains("[lan-ip#"))
    #expect(text.contains("[mac#"))
    #expect(text.contains("192.168.1.21"))
    let system = messages.withLock { $0 }
    #expect(system.count == 2)
    #expect(!system[0].contains("192.168.1.20"))
    #expect(system[1].contains("192.168.1.21"))
    #expect(await sink.snapshot().entries.allSatisfy { !$0.line.contains("192.168.1.20") })
}

@Test func errorReportBundlesRotatedFilesOldestFirstAndRedactsOldLines() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    try Data("old line from 192.168.1.5\n".utf8).write(to: folder.appendingPathComponent("chiaki.1.log"))
    let redactor = LogRedactor(salt: Data(repeating: 3, count: 16))
    let sink = FileLogSink(settings: .init(directory: folder.path), redactor: redactor)
    await sink.record(.diagnostic(.app, .info, "app ready"), now: Date(timeIntervalSince1970: 0))
    await sink.record(.diagnostic(.app, .info, "app ready"), now: Date(timeIntervalSince1970: 0))
    let environment = ErrorReportEnvironment(
        appVersion: "v2.0.0", build: "7", system: "Version 26.0 (Build 25A1)", model: "Mac16,6",
        architecture: "arm64"
    )
    let report = await sink.errorReport(environment: environment, now: Date(timeIntervalSince1970: 86400))
    let header = """
    chiaki-ng error report
    Generated: 1970-01-02T00:00:00Z
    App: v2.0.0 (build 7)
    macOS: Version 26.0 (Build 25A1)
    Mac: Mac16,6 arm64
    Log level: info
    Identifiers redacted: yes
    API capture: no
    Log folder: \(redactor.redact(folder.path))

    ===== chiaki.3.log =====
    (no file)

    ===== chiaki.2.log =====
    (no file)

    ===== chiaki.1.log =====
    old line from [lan-ip#
    """
    #expect(report.hasPrefix(header))
    #expect(!report.contains("192.168.1.5"))
    let current = report.range(of: "===== chiaki.log =====")
    #expect(current != nil)
    #expect(report.contains("App: app ready"))
    #expect(report.contains("Previous line repeated 1 more time"))
    #expect(report.hasSuffix("\n"))
    #expect(ErrorReport.suggestedFileName(now: Date(timeIntervalSince1970: 0))
        == "chiaki-ng-error-report-1970-01-01T00-00-00Z.txt")
}

@Test func pipelineLoadsSettingsOnceAndPersistsSavedOnes() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let loads = Mutex(0)
    let saved = Mutex<LogSettings?>(nil)
    let store = LogSettingsStore(
        load: {
            loads.withLock {
                $0 += 1
            }
            return LogSettings(directory: folder.path, level: .info)
        },
        save: { settings in
            saved.withLock {
                $0 = settings
            }
        }
    )
    let pipeline = LogPipeline(store: store, appVersion: "test")
    async let first = pipeline.load()
    async let second = pipeline.load()
    _ = try await (first, second)
    await pipeline.logger.log(.slowControllerStep(step: "poll", milliseconds: 80))
    #expect(loads.withLock { $0 } == 1)
    var next = LogSettings(directory: folder.path, level: .debug)
    next.captureAPI = true
    try await pipeline.settingsClient.save(next)
    #expect(saved.withLock { $0 } == next)
    #expect(try await pipeline.load() == next)
    let lines = await pipeline.liveLogClient.snapshot().entries.map(\.line)
    #expect(lines.first?
        .hasSuffix("Controller: Slow controller step: poll took 80 ms on the main thread") == true)
    #expect(lines.last?.contains("Logging settings saved: level debug") == true)
    #expect(await pipeline.healthy())
}

@Test func pipelineRejectsARelativeFolderWithoutSavingIt() async throws {
    let saved = Mutex(false)
    let pipeline = LogPipeline(
        store: LogSettingsStore(
            load: {
                LogSettings(directory: "/tmp", level: .off)
            },
            save: { _ in
                saved.withLock {
                    $0 = true
                }
            }
        ),
        appVersion: "test"
    )
    await #expect(throws: CocoaError.self) {
        try await pipeline.save(LogSettings(directory: "relative", level: .info))
    }
    #expect(!saved.withLock { $0 })
}
