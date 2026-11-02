import ChiakiModels
import Dependencies

/// Loads and saves the logging settings and reports on the log's health, for the logging settings pane.
public struct LogSettingsClient: Sendable {
    /// Returns the settings in force, loading them on first use.
    public var load: @Sendable () async throws -> LogSettings

    /// Validates, persists and applies settings.
    public var save: @Sendable (LogSettings) async throws -> Void

    /// Returns whether both the log file and the API capture are writable.
    public var health: @Sendable () async -> Bool

    /// Renders an error report from the log files.
    public var exportReport: @Sendable () async throws -> String

    /// Creates a client from its operations.
    ///
    /// - Parameters:
    ///   - load: Returns the settings in force.
    ///   - save: Validates, persists and applies settings.
    ///   - health: Returns whether logging is writable.
    ///   - exportReport: Renders an error report.
    public init(
        load: @escaping @Sendable () async throws -> LogSettings,
        save: @escaping @Sendable (LogSettings) async throws -> Void,
        health: @escaping @Sendable () async -> Bool = {
            true
        },
        exportReport: @escaping @Sendable () async throws -> String = {
            ""
        }
    ) {
        self.load = load
        self.save = save
        self.health = health
        self.exportReport = exportReport
    }
}

extension LogSettingsClient: TestDependencyKey {
    /// Tests load the defaults and discard saves unless they install their own client.
    public static let testValue = Self(
        load: {
            .defaults
        },
        save: { _ in
        }
    )
}

public extension DependencyValues {
    /// The logging settings client.
    var logSettings: LogSettingsClient {
        get {
            self[LogSettingsClient.self]
        }
        set {
            self[LogSettingsClient.self] = newValue
        }
    }
}

/// Where a ``LogPipeline`` reads and writes the persisted `LogSettings`.
///
/// The App supplies one backed by the settings table; Diagnostics never opens the database itself.
public struct LogSettingsStore: Sendable {
    /// Reads the stored settings, or the defaults when none were saved.
    public var load: @Sendable () async throws -> LogSettings

    /// Persists settings.
    public var save: @Sendable (LogSettings) async throws -> Void

    /// Creates a store from its two operations.
    ///
    /// - Parameters:
    ///   - load: Reads the stored settings.
    ///   - save: Persists settings.
    public init(
        load: @escaping @Sendable () async throws -> LogSettings,
        save: @escaping @Sendable (LogSettings) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }
}
