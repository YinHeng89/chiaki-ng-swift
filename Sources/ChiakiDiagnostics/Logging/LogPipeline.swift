import ChiakiModels
import Foundation

/// Owns the app's log destinations: the rotating log file, the system log mirror and the API capture.
///
/// The App composition root builds one pipeline and hands out ``logger``, ``settingsClient`` and
/// ``liveLogClient`` as the live dependency values. Settings are loaded once from the injected
/// ``LogSettingsStore``; concurrent first uses share one load.
public actor LogPipeline {
    private let store: LogSettingsStore
    private let appVersion: String
    private let sink: FileLogSink
    private let capture: APICaptureStore
    private var configuration: LogSettings?
    private var initialization: Task<LogSettings, Error>?

    /// Creates a pipeline; nothing is loaded or written until first use.
    ///
    /// - Parameters:
    ///   - store: Where the settings are persisted.
    ///   - appVersion: The version written into error reports.
    ///   - system: Where kept lines are mirrored.
    ///   - capture: The API capture file.
    public init(
        store: LogSettingsStore, appVersion: String, system: SystemLogSink = .disabled,
        capture: APICaptureStore = APICaptureStore()
    ) {
        self.store = store
        self.appVersion = appVersion
        sink = FileLogSink(system: system)
        self.capture = capture
    }

    /// A logger writing through this pipeline.
    public nonisolated var logger: LoggerClient {
        LoggerClient(
            record: { event, source in
                await self.record(event, source: source)
            },
            capture: { data in
                await self.recordCapture(data)
            }
        )
    }

    /// A settings client backed by this pipeline.
    public nonisolated var settingsClient: LogSettingsClient {
        LogSettingsClient(
            load: {
                try await self.load()
            },
            save: {
                try await self.save($0)
            },
            health: {
                await self.healthy()
            },
            exportReport: {
                try await self.errorReport()
            }
        )
    }

    /// A live log reader backed by this pipeline.
    public nonisolated var liveLogClient: LiveLogClient {
        LiveLogClient {
            await self.liveSnapshot()
        }
    }

    /// Returns the settings in force, loading and applying the stored ones on first use.
    ///
    /// - Returns: The settings.
    /// - Throws: The store's error, or the sink's validation error for the stored folder.
    public func load() async throws -> LogSettings {
        if let configuration {
            return configuration
        }
        if let initialization {
            return try await initialization.value
        }
        let store = store
        let sink = sink
        let capture = capture
        let task = Task {
            let settings = Self.resolved(try await store.load())
            try await sink.configure(settings)
            await capture.configure(settings)
            return settings
        }
        initialization = task
        do {
            let settings = try await task.value
            if configuration == nil {
                configuration = settings
            }
            initialization = nil
            return settings
        } catch {
            initialization = nil
            throw error
        }
    }

    /// Validates, persists and applies settings, then logs what changed.
    ///
    /// - Parameter settings: The new settings.
    /// - Throws: The validation error for the folder or the store's error; nothing is applied on failure.
    public func save(_ settings: LogSettings) async throws {
        if let initialization {
            _ = try? await initialization.value
        }
        try FileLogSink.validate(settings)
        try await store.save(settings)
        try await sink.configure(settings)
        await capture.configure(settings)
        configuration = settings
        await sink.record(.diagnostic(
            .app, .info,
            "Logging settings saved: level \(settings.level.rawValue), folder \(settings.directory), API capture "
                + "\(LogFormat.yesNo(settings.captureAPI)), live log button "
                + "\(LogFormat.yesNo(settings.showLiveLogButton)), identifiers redacted "
                + LogFormat.yesNo(settings.redactIdentifiers)
        ))
    }

    /// Renders an error report from the log files.
    ///
    /// - Returns: The report text.
    /// - Throws: The error from loading the settings.
    public func errorReport() async throws -> String {
        _ = try await load()
        return await sink.errorReport(environment: .current(appVersion: appVersion))
    }

    /// The live log's recent lines.
    ///
    /// - Returns: The snapshot.
    public func liveSnapshot() async -> LiveLogSnapshot {
        _ = try? await load()
        return await sink.snapshot()
    }

    /// Whether both the log file and the API capture are writable.
    ///
    /// - Returns: `false` when either last write failed.
    public func healthy() async -> Bool {
        let logFailed = await sink.writeFailed
        let captureFailed = await capture.writeFailed
        return !logFailed && !captureFailed
    }

    /// Writes an event, loading the settings first when they are not loaded yet.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - source: Where it was logged.
    public func record(_ event: LogEvent, source: LogSource) async {
        if configuration == nil {
            _ = try? await load()
        }
        await sink.record(event, source: source)
        await reportCaptureFailure()
    }

    /// Writes one raw capture record from the core.
    ///
    /// - Parameter data: The core's JSON object.
    public func recordCapture(_ data: Data) async {
        if configuration == nil {
            _ = try? await load()
        }
        await capture.recordCore(data)
        await reportCaptureFailure()
    }

    private func reportCaptureFailure() async {
        if await capture.takeWriteFailure() {
            await sink.record(.apiCaptureWriteFailed)
        }
    }

    private static func resolved(_ stored: LogSettings) -> LogSettings {
        #if os(iOS)
            var settings = stored
            settings.directory = LogSettings.defaults.directory
            return settings
        #else
            return stored
        #endif
    }
}
