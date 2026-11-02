import Foundation

/// The persisted preferences for what happens to the console when a stream ends or the Mac sleeps.
///
/// Decoding tolerates a missing or unknown leave action and falls back to the defaults.
public struct ConsolePowerSettings: Codable, Equatable, Sendable {
    /// What to do with the console when the user leaves a stream.
    public var leaveAction: ConsoleLeaveAction

    /// Whether the console is put in rest mode when the Mac goes to sleep mid-stream.
    public var restOnMacSleep: Bool

    /// Whether the stream resumes after the Mac wakes.
    public var resumeAfterWake: Bool

    /// Whether a console stream whose connection drops connects again, up to three times, instead of ending.
    public var reconnectAfterDrop: Bool

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - leaveAction: What to do with the console when leaving.
    ///   - restOnMacSleep: Whether to rest the console when the Mac sleeps.
    ///   - resumeAfterWake: Whether to resume after the Mac wakes.
    ///   - reconnectAfterDrop: Whether to connect again after the connection drops.
    public init(
        leaveAction: ConsoleLeaveAction = .ask,
        restOnMacSleep: Bool = false,
        resumeAfterWake: Bool = true,
        reconnectAfterDrop: Bool = true
    ) {
        self.leaveAction = leaveAction
        self.restOnMacSleep = restOnMacSleep
        self.resumeAfterWake = resumeAfterWake
        self.reconnectAfterDrop = reconnectAfterDrop
    }

    /// Decodes settings, defaulting anything missing or unreadable.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored flag has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        leaveAction = (try? values.decodeIfPresent(ConsoleLeaveAction.self, forKey: .leaveAction)) ?? .ask
        restOnMacSleep = try values.decodeIfPresent(Bool.self, forKey: .restOnMacSleep) ?? false
        resumeAfterWake = try values.decodeIfPresent(Bool.self, forKey: .resumeAfterWake) ?? true
        reconnectAfterDrop = try values.decodeIfPresent(Bool.self, forKey: .reconnectAfterDrop) ?? true
    }
}

extension ConsolePowerSettings: PersistedSettingValue {
    /// The key the console power settings are stored under.
    public static var settingKey: SettingKey<ConsolePowerSettings> {
        SettingKeys.consolePower
    }
}

/// The saved choice for what happens to the console when the user leaves a stream.
public enum ConsoleLeaveAction: String, Codable, CaseIterable, Equatable, Sendable {
    /// Ask each time.
    case ask

    /// Put the console in rest mode.
    case restMode

    /// Leave the console on.
    case leaveOn
}
