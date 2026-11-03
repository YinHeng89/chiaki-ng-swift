import Foundation

/// The persisted layout preferences for the main window.
///
/// Decoding tolerates a missing or unknown value and falls back to the default.
public struct InterfaceSettings: Codable, Equatable, Sendable {
    /// The window edge the library rail sits on.
    public var railEdge: LibraryRailEdge

    /// Creates settings.
    ///
    /// - Parameter railEdge: The edge the library rail sits on.
    public init(railEdge: LibraryRailEdge = .right) {
        self.railEdge = railEdge
    }

    /// Decodes settings, defaulting anything missing or unreadable.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when the stored value is not a keyed container.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        railEdge = (try? values.decodeIfPresent(LibraryRailEdge.self, forKey: .railEdge)) ?? .right
    }
}

extension InterfaceSettings: PersistedSettingValue {
    /// The key the interface settings are stored under.
    public static var settingKey: SettingKey<InterfaceSettings> {
        SettingKeys.interface
    }
}
