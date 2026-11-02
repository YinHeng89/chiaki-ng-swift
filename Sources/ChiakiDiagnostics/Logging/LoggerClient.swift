import Dependencies
import Foundation

/// Writes ``LogEvent`` values and raw API captures to wherever the app sends diagnostics.
///
/// Reducers and clients read it as `@Dependency(\.logger)`; types outside the dependency system take one in
/// their initialiser. The App composition root supplies the live value over one ``LogPipeline``; tests get
/// ``disabled``. Synchronous code hands events to ``enqueue(_:file:function:line:)``, which writes them one
/// at a time in the order they were enqueued.
public struct LoggerClient: Sendable {
    private struct Entry: Sendable {
        let event: LogEvent
        let source: LogSource
    }

    private let sink: @Sendable (LogEvent, LogSource) async -> Void
    private let capture: @Sendable (Data) async -> Void
    private let queue: AsyncStream<Entry>.Continuation

    /// Creates a logger from its two destinations.
    ///
    /// - Parameters:
    ///   - record: Receives each event with the location that logged it.
    ///   - capture: Receives each raw JSON capture record from the core.
    public init(
        record: @escaping @Sendable (LogEvent, LogSource) async -> Void,
        capture: @escaping @Sendable (Data) async -> Void = { _ in
        }
    ) {
        sink = record
        self.capture = capture
        let (entries, queue) = AsyncStream<Entry>.makeStream()
        self.queue = queue
        Task {
            for await entry in entries {
                await record(entry.event, entry.source)
            }
        }
    }

    /// Logs an event from the caller's source location.
    ///
    /// - Parameters:
    ///   - event: The event to write.
    ///   - file: The calling file.
    ///   - function: The calling function.
    ///   - line: The calling line.
    public func log(
        _ event: LogEvent, file: String = #fileID, function: String = #function, line: UInt = #line
    ) async {
        await sink(event, LogSource(file: file, function: function, line: line))
    }

    /// Queues an event from the caller's source location without waiting for it to be written.
    ///
    /// Queued events are written one at a time in the order they were queued.
    ///
    /// - Parameters:
    ///   - event: The event to write.
    ///   - file: The calling file.
    ///   - function: The calling function.
    ///   - line: The calling line.
    public func enqueue(
        _ event: LogEvent, file: String = #fileID, function: String = #function, line: UInt = #line
    ) {
        queue.yield(Entry(event: event, source: LogSource(file: file, function: function, line: line)))
    }

    /// Hands one raw JSON capture record from the core to the API capture file.
    ///
    /// - Parameter record: The JSON object the core captured.
    public func capture(core record: Data) async {
        await capture(record)
    }

    /// A logger that drops everything.
    public static let disabled = Self { _, _ in
    }
}

extension LoggerClient: TestDependencyKey {
    /// Tests drop every log line unless they install their own logger.
    public static let testValue = Self.disabled
}

public extension DependencyValues {
    /// The app-wide logger.
    var logger: LoggerClient {
        get {
            self[LoggerClient.self]
        }
        set {
            self[LoggerClient.self] = newValue
        }
    }
}

/// The source location that wrote a log line.
public struct LogSource: Equatable, Sendable {
    /// The file identifier, as `#fileID` gives it.
    public let file: String

    /// The function name.
    public let function: String

    /// The line number.
    public let line: UInt

    /// Captures a source location, defaulting to the caller's.
    ///
    /// - Parameters:
    ///   - file: The file identifier.
    ///   - function: The function name.
    ///   - line: The line number.
    public init(file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.file = file
        self.function = function
        self.line = line
    }
}
