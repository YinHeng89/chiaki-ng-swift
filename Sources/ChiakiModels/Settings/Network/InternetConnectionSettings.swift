import Foundation

/// The persisted preferences for reaching a console over the internet.
///
/// The port-guess bounds mirror the core's `InternetOptions`; a bridge test asserts they stay equal.
public struct InternetConnectionSettings: Codable, Equatable, Sendable {
    /// The number of ports the core may guess when punching through a NAT.
    public static let portGuessRange = 5...80

    /// The increment the guess count moves in.
    public static let portGuessStep = 5

    /// The core's default guess count.
    public static let defaultPortGuessCount = 75

    /// Whether port guessing is used even when the NAT looks predictable.
    public var forcePortGuessing: Bool

    /// How many ports are guessed.
    public var portGuessCount: Int

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - forcePortGuessing: Whether guessing is always used.
    ///   - portGuessCount: How many ports are guessed.
    public init(forcePortGuessing: Bool = false, portGuessCount: Int = Self.defaultPortGuessCount) {
        self.forcePortGuessing = forcePortGuessing
        self.portGuessCount = portGuessCount
    }

    /// Decodes settings, defaulting anything missing and clamping the guess count.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        forcePortGuessing = try values.decodeIfPresent(Bool.self, forKey: .forcePortGuessing) ?? false
        let stored = try values.decodeIfPresent(Int.self, forKey: .portGuessCount)
            ?? Self.defaultPortGuessCount
        portGuessCount = min(max(stored, Self.portGuessRange.lowerBound), Self.portGuessRange.upperBound)
    }

    /// Checks the guess count.
    ///
    /// - Returns: The settings unchanged.
    /// - Throws: ``InternetConnectionSettingsFailure/invalidPortGuessCount`` when it is out of range.
    public func validated() throws -> Self {
        guard Self.portGuessRange.contains(portGuessCount) else {
            throw InternetConnectionSettingsFailure.invalidPortGuessCount
        }
        return self
    }
}

extension InternetConnectionSettings: PersistedSettingValue {
    /// The key the internet connection settings are stored under.
    public static var settingKey: SettingKey<InternetConnectionSettings> {
        SettingKeys.internetConnection
    }
}

/// Why internet connection settings were refused.
public enum InternetConnectionSettingsFailure: Error, Equatable {
    /// The port guess count is outside ``InternetConnectionSettings/portGuessRange``.
    case invalidPortGuessCount
}
