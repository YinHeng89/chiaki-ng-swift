import Foundation

/// The persisted logging preferences: where logs go, how verbose they are and what is redacted.
///
/// Decoding tolerates settings saved by older versions: every flag added later falls back to its default.
public struct LogSettings: Equatable, Codable, Sendable {
    /// The absolute folder log files are written to.
    public var directory: String

    /// The security-scoped bookmark saved when the user chose ``directory``, or `nil` for the default folder;
    /// ``FolderAccess`` uses it to reach the folder again after a relaunch.
    public var directoryBookmark: Data?

    /// The most verbose level written.
    public var level: LogLevel

    /// Whether the live log button is shown over the stream.
    public var showLiveLogButton = false

    /// Whether redacted PSN API exchanges are captured to disk.
    public var captureAPI = false

    /// Whether addresses, ids and other identifiers are replaced by salted tags.
    public var redactIdentifiers = true

    /// Whether on-screen text hides identifying details.
    public var streamerMode = false

    /// Creates settings with every flag at its default.
    ///
    /// - Parameters:
    ///   - directory: The absolute log folder.
    ///   - level: The most verbose level written.
    public init(directory: String, level: LogLevel = .info) {
        self.directory = directory
        self.level = level
    }

    private enum CodingKeys: String, CodingKey {
        case directory, directoryBookmark, level, showLiveLogButton, captureAPI, redactIdentifiers,
             streamerMode
    }

    /// Decodes settings, defaulting any flag an older version did not store.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when the folder or level is missing or malformed.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        directory = try values.decode(String.self, forKey: .directory)
        directoryBookmark = try values.decodeIfPresent(Data.self, forKey: .directoryBookmark)
        level = try values.decode(LogLevel.self, forKey: .level)
        captureAPI = try values.decodeIfPresent(Bool.self, forKey: .captureAPI) ?? false
        showLiveLogButton = try values.decodeIfPresent(Bool.self, forKey: .showLiveLogButton) ?? false
        redactIdentifiers = try values.decodeIfPresent(Bool.self, forKey: .redactIdentifiers) ?? true
        streamerMode = try values.decodeIfPresent(Bool.self, forKey: .streamerMode) ?? false
    }

    /// The settings used before any are saved: the installation's log folder at ``LogLevel/info``.
    public static var defaults: Self {
        .init(directory: UserData.current.logs.path)
    }
}

extension LogSettings: PersistedSettingValue {
    /// The key the logging settings are stored under.
    public static var settingKey: SettingKey<LogSettings> {
        SettingKeys.logging
    }
}

/// How much the app writes to its log, from nothing to every debug line.
///
/// The raw values are the persisted text. ``priority`` ranks levels explicitly, so reordering the declaration
/// cannot change which events are kept.
public enum LogLevel: String, Codable, CaseIterable, Sendable {
    /// Nothing is logged.
    case off

    /// Only failures.
    case error

    /// Failures and conditions worth a second look.
    case warning

    /// Normal progress as well as problems.
    case info

    /// Everything, including high-volume detail.
    case debug

    /// The rank of the level; a higher rank is more verbose.
    public var priority: Int {
        switch self {
        case .off:
            0
        case .error:
            1
        case .warning:
            2
        case .info:
            3
        case .debug:
            4
        }
    }

    /// Whether an event at `level` is kept when this is the configured level.
    ///
    /// - Parameter level: The level of the event.
    /// - Returns: `true` when neither level is ``off`` and `level` is no more verbose than this one.
    public func admits(_ level: LogLevel) -> Bool {
        self != .off && level != .off && level.priority <= priority
    }
}
