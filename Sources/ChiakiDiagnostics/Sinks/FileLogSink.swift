import ChiakiModels
import Foundation

/// Filters, redacts and writes log events to the rotating `chiaki.log` and the system log, keeping the most
/// recent lines for the live log.
///
/// Consecutive identical lines collapse into one "repeated" line. A write failure never reaches the caller: it
/// sets ``writeFailed`` until a later write succeeds.
public actor FileLogSink {
    private static let recentLimit = 250
    private static let lineLimit = 4096

    private var settings: LogSettings
    private let maximumBytes: Int
    private let system: SystemLogSink
    private let redactor: LogRedactor
    private var file: RotatingLogFile?
    private var recent: [LiveLogEntry] = []
    private var sequence: UInt64 = 0
    private var repeated: RepeatedLine?

    /// Whether the last write to the log file failed.
    public private(set) var writeFailed = false

    /// Creates a sink.
    ///
    /// - Parameters:
    ///   - settings: The initial settings.
    ///   - maximumBytes: The size `chiaki.log` may reach before it rotates.
    ///   - system: Where kept lines are mirrored.
    ///   - redactor: The redactor applied while `LogSettings/redactIdentifiers` is on.
    public init(
        settings: LogSettings = .defaults, maximumBytes: Int = 1_048_576,
        system: SystemLogSink = .disabled, redactor: LogRedactor = .random()
    ) {
        self.settings = settings
        self.maximumBytes = max(1, maximumBytes)
        self.system = system
        self.redactor = redactor
    }

    /// The most recent lines, the level and the write state, for the live log.
    ///
    /// - Returns: The snapshot.
    public func snapshot() -> LiveLogSnapshot {
        .init(entries: recent, level: settings.level, writeFailed: writeFailed)
    }

    /// Applies new settings, reopening the file when the folder changes or logging turns off.
    ///
    /// - Parameter settings: The settings to apply.
    /// - Throws: The error from ``validate(_:)``; the previous settings stay in force.
    public func configure(_ settings: LogSettings) throws {
        try Self.validate(settings)
        if settings.directory != self.settings.directory || settings.level == .off {
            file = nil
        }
        self.settings = settings
        writeFailed = false
    }

    /// Checks that the folder in `settings` is absolute and writable whenever anything will be written there,
    /// first opening the access its bookmark grants.
    ///
    /// - Parameter settings: The settings to check.
    /// - Throws: `CocoaError` for a relative folder, or the file system error from creating the folder or
    ///   writing a probe file.
    public static func validate(_ settings: LogSettings) throws {
        if settings.level == .off && !settings.captureAPI {
            return
        }
        guard settings.directory.hasPrefix("/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        FolderAccess.open(settings.directory, bookmark: settings.directoryBookmark)
        let directory = URL(fileURLWithPath: settings.directory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let probe = directory.appendingPathComponent(".chiaki-write-test-\(UUID().uuidString)")
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }

    /// Writes an event when the configured level admits it.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - source: Where it was logged.
    ///   - now: The timestamp for the line.
    public func record(_ event: LogEvent, source: LogSource = .init(), now: Date = Date()) {
        guard settings.level.admits(event.level) else {
            return
        }
        let message = sanitize(event.message)
        if let previous = repeated, previous.level == event.level, previous.message == message {
            repeated?.count += 1
            return
        }
        flushRepeats(now: now)
        repeated = RepeatedLine(level: event.level, message: message, source: source)
        system.record(event.level, message, source)
        write(level: event.level, source: source, message: message, now: now)
    }

    /// Renders an error report from the log files on disk, redacting older lines when redaction is on.
    ///
    /// - Parameters:
    ///   - environment: The app and machine description.
    ///   - now: The report timestamp.
    /// - Returns: The report text.
    public func errorReport(environment: ErrorReportEnvironment, now: Date = Date()) -> String {
        flushRepeats(now: now)
        let directory = URL(fileURLWithPath: settings.directory, isDirectory: true)
        let files = ErrorReport.fileNames.map { name -> ErrorReport.File in
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                return .init(name: name, text: nil)
            }
            guard let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1)
            else {
                return .init(name: name, text: nil)
            }
            guard settings.redactIdentifiers else {
                return .init(name: name, text: text)
            }
            let redacted = text.split(separator: "\n", omittingEmptySubsequences: false).map {
                redactor.redact(String($0))
            }.joined(separator: "\n")
            return .init(name: name, text: redacted)
        }
        return ErrorReport.render(
            environment: environment, settings: settings, directory: sanitize(settings.directory),
            generated: now, files: files
        )
    }

    private func sanitize(_ text: String) -> String {
        settings.redactIdentifiers
            ? redactor.redact(text)
            : text
    }

    private func flushRepeats(now: Date) {
        guard let previous = repeated, previous.count > 0 else {
            return
        }
        repeated = nil
        write(
            level: previous.level, source: previous.source,
            message: "Previous line repeated \(previous.count) more "
                + (previous.count == 1
                    ? "time"
                    : "times"),
            now: now
        )
    }

    private func write(level: LogLevel, source: LogSource, message: String, now: Date) {
        let timestamp = now.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let line = "\(timestamp) [\(level.rawValue.uppercased())] "
            + "[\(source.file):\(source.line) \(source.function)] \(message)"
        sequence &+= 1
        recent.append(.init(id: sequence, line: String(line.prefix(Self.lineLimit))))
        if recent.count > Self.recentLimit {
            recent.removeFirst(recent.count - Self.recentLimit)
        }
        do {
            if file == nil {
                file = RotatingLogFile(
                    directory: URL(fileURLWithPath: settings.directory, isDirectory: true),
                    name: "chiaki", suffix: "log", maximumBytes: maximumBytes
                )
            }
            try file?.append(Data((line + "\n").utf8))
            writeFailed = false
        } catch {
            file = nil
            writeFailed = true
        }
    }

    private struct RepeatedLine {
        let level: LogLevel
        let message: String
        let source: LogSource
        var count = 0
    }
}
