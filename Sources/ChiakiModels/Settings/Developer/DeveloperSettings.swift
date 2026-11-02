import Foundation

/// The persisted developer overrides: a Takion protocol version and a negotiation switch per target, and how
/// long a cloud library refresh blocks the next one.
///
/// Decoding upgrades the single version older versions stored and resets any version a target does not accept
/// to automatic.
public struct DeveloperSettings: Equatable, Sendable, Codable {
    /// The version value meaning "let the core choose".
    public static let automaticTakionVersion: UInt32 = 0

    /// The versions every target accepts.
    public static let takionVersions: [UInt32] = [9, 12, 15, 19, 20]

    /// The versions only cloud targets accept.
    public static let cloudOnlyTakionVersions: [UInt32] = [21, 23, 25]

    /// The minutes a cloud library refresh blocks the next one unless overridden.
    public static let defaultLibraryRefreshCooldownMinutes: UInt32 = 15

    /// The library refresh cooldowns offered, in minutes; 0 lets every refresh through.
    public static let libraryRefreshCooldownChoices: [UInt32] = [0, 1, 5, 15, 30, 60]

    /// The version override for PS4 streams.
    public var takionLocalPS4: UInt32

    /// The version override for PS5 streams.
    public var takionLocalPS5: UInt32

    /// The version override for PS Now streams.
    public var takionPSNow: UInt32

    /// The version override for PS Cloud streams.
    public var takionPSCloud: UInt32

    /// Whether PS4 streams negotiate the version.
    public var negotiateLocalPS4: Bool

    /// Whether PS5 streams negotiate the version.
    public var negotiateLocalPS5: Bool

    /// Whether PS Now streams negotiate the version.
    public var negotiatePSNow: Bool

    /// Whether PS Cloud streams negotiate the version.
    public var negotiatePSCloud: Bool

    /// The minutes a cloud library refresh blocks the next one, one of ``libraryRefreshCooldownChoices``.
    public var libraryRefreshCooldownMinutes: UInt32

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - takionLocalPS4: The PS4 version override.
    ///   - takionLocalPS5: The PS5 version override.
    ///   - takionPSNow: The PS Now version override.
    ///   - takionPSCloud: The PS Cloud version override.
    ///   - negotiateLocalPS4: Whether PS4 streams negotiate.
    ///   - negotiateLocalPS5: Whether PS5 streams negotiate.
    ///   - negotiatePSNow: Whether PS Now streams negotiate.
    ///   - negotiatePSCloud: Whether PS Cloud streams negotiate.
    ///   - libraryRefreshCooldownMinutes: The minutes a cloud library refresh blocks the next one.
    public init(
        takionLocalPS4: UInt32 = Self.automaticTakionVersion,
        takionLocalPS5: UInt32 = Self.automaticTakionVersion,
        takionPSNow: UInt32 = Self.automaticTakionVersion,
        takionPSCloud: UInt32 = Self.automaticTakionVersion,
        negotiateLocalPS4: Bool = false,
        negotiateLocalPS5: Bool = false,
        negotiatePSNow: Bool = false,
        negotiatePSCloud: Bool = false,
        libraryRefreshCooldownMinutes: UInt32 = Self.defaultLibraryRefreshCooldownMinutes
    ) {
        self.takionLocalPS4 = takionLocalPS4
        self.takionLocalPS5 = takionLocalPS5
        self.takionPSNow = takionPSNow
        self.takionPSCloud = takionPSCloud
        self.negotiateLocalPS4 = negotiateLocalPS4
        self.negotiateLocalPS5 = negotiateLocalPS5
        self.negotiatePSNow = negotiatePSNow
        self.negotiatePSCloud = negotiatePSCloud
        self.libraryRefreshCooldownMinutes = libraryRefreshCooldownMinutes
    }

    /// Creates settings with one version override for every target.
    ///
    /// - Parameter version: The version for every target.
    public init(allTakion version: UInt32) {
        self.init(
            takionLocalPS4: version,
            takionLocalPS5: version,
            takionPSNow: version,
            takionPSCloud: version
        )
    }

    private enum CodingKeys: String, CodingKey {
        case takionVersion, takionLocalPS4, takionLocalPS5, takionPSNow, takionPSCloud
        case negotiateLocalPS4, negotiateLocalPS5, negotiatePSNow, negotiatePSCloud
        case libraryRefreshCooldownMinutes
    }

    /// Decodes settings, upgrading the single stored version and resetting unaccepted versions and library
    /// refresh cooldowns.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try container.decodeIfPresent(UInt32.self, forKey: .takionVersion)
            ?? Self.automaticTakionVersion
        takionLocalPS4 = Self.decodedVersion(
            try container.decodeIfPresent(UInt32.self, forKey: .takionLocalPS4) ?? legacy, for: .localPS4
        )
        takionLocalPS5 = Self.decodedVersion(
            try container.decodeIfPresent(UInt32.self, forKey: .takionLocalPS5) ?? legacy, for: .localPS5
        )
        takionPSNow = Self.decodedVersion(
            try container.decodeIfPresent(UInt32.self, forKey: .takionPSNow) ?? legacy, for: .psNow
        )
        takionPSCloud = Self.decodedVersion(
            try container.decodeIfPresent(UInt32.self, forKey: .takionPSCloud) ?? legacy, for: .psCloud
        )
        negotiateLocalPS4 = try container.decodeIfPresent(Bool.self, forKey: .negotiateLocalPS4) ?? false
        negotiateLocalPS5 = try container.decodeIfPresent(Bool.self, forKey: .negotiateLocalPS5) ?? false
        negotiatePSNow = try container.decodeIfPresent(Bool.self, forKey: .negotiatePSNow) ?? false
        negotiatePSCloud = try container.decodeIfPresent(Bool.self, forKey: .negotiatePSCloud) ?? false
        let cooldown = try container.decodeIfPresent(UInt32.self, forKey: .libraryRefreshCooldownMinutes)
            ?? Self.defaultLibraryRefreshCooldownMinutes
        libraryRefreshCooldownMinutes = Self.libraryRefreshCooldownChoices.contains(cooldown)
            ? cooldown
            : Self.defaultLibraryRefreshCooldownMinutes
    }

    private static func decodedVersion(_ version: UInt32, for target: TakionTarget) -> UInt32 {
        isValidTakionVersion(version, for: target)
            ? version
            : automaticTakionVersion
    }

    /// Encodes the per-target values; the retired single version is never written.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: The encoder's error.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(takionLocalPS4, forKey: .takionLocalPS4)
        try container.encode(takionLocalPS5, forKey: .takionLocalPS5)
        try container.encode(takionPSNow, forKey: .takionPSNow)
        try container.encode(takionPSCloud, forKey: .takionPSCloud)
        try container.encode(negotiateLocalPS4, forKey: .negotiateLocalPS4)
        try container.encode(negotiateLocalPS5, forKey: .negotiateLocalPS5)
        try container.encode(negotiatePSNow, forKey: .negotiatePSNow)
        try container.encode(negotiatePSCloud, forKey: .negotiatePSCloud)
        try container.encode(libraryRefreshCooldownMinutes, forKey: .libraryRefreshCooldownMinutes)
    }

    /// How long a cloud library refresh blocks the next one.
    public var libraryRefreshCooldown: Duration {
        .seconds(Int64(libraryRefreshCooldownMinutes) * 60)
    }

    /// The negotiation switch for a target.
    ///
    /// - Parameter target: The target.
    public subscript(negotiation target: TakionTarget) -> Bool {
        get {
            switch target {
            case .localPS4:
                negotiateLocalPS4
            case .localPS5:
                negotiateLocalPS5
            case .psNow:
                negotiatePSNow
            case .psCloud:
                negotiatePSCloud
            }
        }
        set {
            switch target {
            case .localPS4:
                negotiateLocalPS4 = newValue
            case .localPS5:
                negotiateLocalPS5 = newValue
            case .psNow:
                negotiatePSNow = newValue
            case .psCloud:
                negotiatePSCloud = newValue
            }
        }
    }

    /// The version override for a target.
    ///
    /// - Parameter target: The target.
    public subscript(target: TakionTarget) -> UInt32 {
        get {
            switch target {
            case .localPS4:
                takionLocalPS4
            case .localPS5:
                takionLocalPS5
            case .psNow:
                takionPSNow
            case .psCloud:
                takionPSCloud
            }
        }
        set {
            switch target {
            case .localPS4:
                takionLocalPS4 = newValue
            case .localPS5:
                takionLocalPS5 = newValue
            case .psNow:
                takionPSNow = newValue
            case .psCloud:
                takionPSCloud = newValue
            }
        }
    }

    /// The versions offered for a target.
    ///
    /// - Parameter target: The target.
    /// - Returns: The shared versions, plus the cloud-only ones for a cloud target.
    public static func takionVersions(for target: TakionTarget) -> [UInt32] {
        target.isCloud
            ? takionVersions + cloudOnlyTakionVersions
            : takionVersions
    }

    /// Whether any target accepts a version.
    ///
    /// - Parameter version: The version.
    /// - Returns: `true` for automatic or a known version.
    public static func isValidTakionVersion(_ version: UInt32) -> Bool {
        version == automaticTakionVersion || takionVersions.contains(version)
            || cloudOnlyTakionVersions.contains(version)
    }

    /// Whether a target accepts a version.
    ///
    /// - Parameters:
    ///   - version: The version.
    ///   - target: The target.
    /// - Returns: `true` for automatic or a version offered for the target.
    public static func isValidTakionVersion(_ version: UInt32, for target: TakionTarget) -> Bool {
        version == automaticTakionVersion || takionVersions(for: target).contains(version)
    }

    /// Checks every target's override.
    ///
    /// - Returns: The settings unchanged.
    /// - Throws: ``DeveloperSettingsError/unknownTakionVersion(_:)`` for the first unaccepted override, or
    ///   ``DeveloperSettingsError/unknownLibraryRefreshCooldown(_:)`` for a cooldown that is not offered.
    public func validated() throws -> Self {
        for target in TakionTarget.allCases where !Self.isValidTakionVersion(self[target], for: target) {
            throw DeveloperSettingsError.unknownTakionVersion(self[target])
        }
        guard Self.libraryRefreshCooldownChoices.contains(libraryRefreshCooldownMinutes) else {
            throw DeveloperSettingsError.unknownLibraryRefreshCooldown(libraryRefreshCooldownMinutes)
        }
        return self
    }
}

extension DeveloperSettings: PersistedSettingValue {
    /// The key the Takion version settings are stored under.
    public static var settingKey: SettingKey<DeveloperSettings> {
        SettingKeys.developer
    }
}

extension DeveloperSettings {
    /// The name of a Takion version choice.
    ///
    /// - Parameters:
    ///   - version: The chosen version, or ``DeveloperSettings/automaticTakionVersion``.
    ///   - build: The version this build negotiates when the choice is automatic.
    /// - Returns: `"Automatic"`, `"Automatic (v12)"` or `"v12"`.
    public static func versionTitle(for version: UInt32, build: UInt32) -> String {
        switch version {
        case DeveloperSettings.automaticTakionVersion:
            return build == DeveloperSettings.automaticTakionVersion
                ? "Automatic"
                : "Automatic (v\(build))"
        default:
            return "v\(version)"
        }
    }
}

extension DeveloperSettings {
    /// The name of a library refresh cooldown choice.
    ///
    /// - Parameter minutes: The cooldown in minutes.
    /// - Returns: `"Off"`, `"1 minute"` or `"15 minutes"`.
    public static func libraryRefreshCooldownTitle(minutes: UInt32) -> String {
        switch minutes {
        case 0:
            "Off"
        case 1:
            "1 minute"
        default:
            "\(minutes) minutes"
        }
    }
}

/// Why developer settings were refused.
public enum DeveloperSettingsError: Error, Equatable {
    /// The Takion protocol version is not one the target accepts.
    case unknownTakionVersion(UInt32)

    /// The library refresh cooldown, in minutes, is not one of the offered choices.
    case unknownLibraryRefreshCooldown(UInt32)
}
