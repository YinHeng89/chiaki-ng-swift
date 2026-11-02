import Foundation

/// A named, typed setting with its default and its validation.
///
/// The value is stored as JSON under ``name``; dates inside it are stored as whole milliseconds since 1970.
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    /// The key the value is stored under.
    public let name: String

    /// The value read when nothing is stored.
    public let defaultValue: Value

    /// Checks a value before it is stored and after it is read, returning the value to keep.
    public let validate: @Sendable (Value) throws -> Value

    /// Describes a setting.
    ///
    /// - Parameters:
    ///   - name: The storage key.
    ///   - defaultValue: The value read when nothing is stored.
    ///   - validate: Checks a value; the identity by default.
    public init(
        name: String,
        defaultValue: Value,
        validate: @escaping @Sendable (Value) throws -> Value = {
            $0
        }
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.validate = validate
    }
}

/// Every setting the app stores, with its storage key, default and validation.
public enum SettingKeys {
    /// The console picture settings.
    public static let picture = SettingKey(name: "picture.v1", defaultValue: PictureSettings()) {
        try $0.validated()
    }

    /// The cloud picture settings.
    public static let cloudPicture = SettingKey(
        name: "cloud.picture.v1",
        defaultValue: CloudPictureSettings()
    ) {
        try $0.validated()
    }

    /// The sound settings.
    public static let sound = SettingKey(name: "sound.v1", defaultValue: SoundSettings()) {
        try $0.validated()
    }

    /// What happens to the console when a stream ends.
    public static let consolePower = SettingKey(
        name: "console.power.v1",
        defaultValue: ConsolePowerSettings()
    )

    /// The internet connection settings.
    public static let internetConnection = SettingKey(
        name: "internet.connection.v1",
        defaultValue: InternetConnectionSettings()
    ) {
        try $0.validated()
    }

    /// The PlayStation accessibility settings sent with cloud stream launches.
    public static let playStationAccessibility = SettingKey(
        name: "playstation.accessibility.v1",
        defaultValue: PlayStationAccessibilitySettings()
    )

    /// The console discovery settings.
    public static let discovery = SettingKey(name: "discovery", defaultValue: DiscoverySettings()) {
        try $0.normalized()
    }

    /// The logging settings.
    public static let logging = SettingKey(name: "logging", defaultValue: LogSettings.defaults)

    /// The profile id of the active account.
    public static let activeAccount = SettingKey<UUID?>(name: "accounts.active.v1", defaultValue: nil)

    /// The Kakusan settings.
    public static let kakusan = SettingKey(name: "kakusan.v1", defaultValue: KakusanSettings()) {
        try $0.validated()
    }

    /// The user's cloud datacenter choices; the measurements are stored separately.
    public static let cloudDatacenters = SettingKey(
        name: "cloud.datacenters.v1",
        defaultValue: CloudDatacenterSettings()
    ) {
        try $0.validated()
    }

    /// The developer settings.
    public static let developer = SettingKey(name: "developer.v1", defaultValue: DeveloperSettings()) {
        try $0.validated()
    }

    /// The interface settings.
    public static let interface = SettingKey(name: "interface.v1", defaultValue: InterfaceSettings())

    /// Which PSN alerts are shown, and whose are muted.
    public static let psnAlerts = SettingKey(name: "psn.alerts.v1", defaultValue: PSNAlertSettings())

    /// How the stream diagnostics panel looks.
    public static let streamDiagnostics = SettingKey(
        name: "stream.diagnostics.v1",
        defaultValue: StreamDiagnosticsAppearance()
    )
}
