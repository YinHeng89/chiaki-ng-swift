import Foundation

/// Which networks console discovery searches.
public struct DiscoverySettings: Codable, Equatable, Sendable {
    /// The settings format version.
    public var version = 1

    /// Whether the extra subnets are searched address by address.
    public var unicastEnabled = false

    /// Extra subnets to search, in CIDR notation.
    public var subnets: [String] = []

    /// Creates the default settings: no extra subnets.
    public init() {}

    /// The settings with each subnet trimmed and duplicates removed.
    ///
    /// - Returns: The normalised settings.
    /// - Throws: ``DiscoveryFailure/invalidSubnets`` when the version is not one this app reads.
    public func normalized() throws(DiscoveryFailure) -> Self {
        guard version == 1 else {
            throw .invalidSubnets
        }
        var result = self
        var normalized: [String] = []
        for text in subnets.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where !normalized.contains(text) {
            normalized.append(text)
        }
        result.subnets = normalized
        return result
    }
}

extension DiscoverySettings: PersistedSettingValue {
    /// The key the console discovery settings are stored under.
    public static var settingKey: SettingKey<DiscoverySettings> {
        SettingKeys.discovery
    }

    /// The settings normalised for storage. The core checks the subnets again when the settings are saved
    /// and before every search.
    ///
    /// - Returns: The settings to store.
    /// - Throws: ``DiscoveryFailure/invalidSubnets`` when the version is not one this app reads.
    public func validated() throws(DiscoveryFailure) -> Self {
        try normalized()
    }
}

/// Why console discovery stopped or its settings were refused.
public enum DiscoveryFailure: Error, Equatable, Sendable {
    /// A subnet is not valid, or there are too many.
    case invalidSubnets

    /// The subnets cover more addresses than a search visits.
    case tooManyTargets

    /// The network could not be searched.
    case network

    /// The settings could not be stored.
    case storage
}
