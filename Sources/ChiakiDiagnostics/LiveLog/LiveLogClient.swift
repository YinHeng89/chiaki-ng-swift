import ChiakiModels
import Dependencies

/// Reads the live log's recent lines.
public struct LiveLogClient: Sendable {
    /// Returns the current snapshot.
    public var snapshot: @Sendable () async -> LiveLogSnapshot

    /// Creates a client from its read function.
    ///
    /// - Parameter snapshot: Returns the current snapshot.
    public init(snapshot: @escaping @Sendable () async -> LiveLogSnapshot) {
        self.snapshot = snapshot
    }
}

extension LiveLogClient: TestDependencyKey {
    /// Tests see an empty log unless they install their own client.
    public static let testValue = Self {
        .init()
    }
}

public extension DependencyValues {
    /// The live log reader.
    var liveLog: LiveLogClient {
        get {
            self[LiveLogClient.self]
        }
        set {
            self[LiveLogClient.self] = newValue
        }
    }
}

/// One line shown in the live log.
public struct LiveLogEntry: Equatable, Identifiable, Sendable {
    /// The line's position in the run, increasing with each line written.
    public let id: UInt64

    /// The formatted, already redacted line.
    public let line: String

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - id: The line's sequence number.
    ///   - line: The formatted line.
    public init(id: UInt64, line: String) {
        self.id = id
        self.line = line
    }
}

/// The recent log lines and logging state shown by the live log panel.
public struct LiveLogSnapshot: Equatable, Sendable {
    /// The most recent lines, oldest first.
    public var entries: [LiveLogEntry]

    /// The configured level.
    public var level: LogLevel

    /// Whether the last write to the log file failed.
    public var writeFailed: Bool

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - entries: The recent lines.
    ///   - level: The configured level.
    ///   - writeFailed: Whether the last file write failed.
    public init(entries: [LiveLogEntry] = [], level: LogLevel = .info, writeFailed: Bool = false) {
        self.entries = entries
        self.level = level
        self.writeFailed = writeFailed
    }
}
