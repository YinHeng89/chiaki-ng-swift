import Foundation

/// The device's own accessibility preferences, which PlayStation accessibility follows until a choice is
/// changed.
public struct PlayStationAccessibilityDefaults: Equatable, Sendable {
    /// Whether a screen reader is running on the device.
    public var screenReader: Bool
    /// The text size matching the device's preferred text size, from -1 (small) to 2 (very large).
    public var textSize: Int
    /// Whether the device asks for bold text.
    public var boldText: Bool
    /// Whether the device asks for higher contrast.
    public var higherContrast: Bool

    /// Creates the defaults.
    ///
    /// - Parameters:
    ///   - screenReader: Whether a screen reader is running.
    ///   - textSize: The preferred text size, from -1 to 2.
    ///   - boldText: Whether bold text is preferred.
    ///   - higherContrast: Whether higher contrast is preferred.
    public init(screenReader: Bool, textSize: Int, boldText: Bool, higherContrast: Bool) {
        self.screenReader = screenReader
        self.textSize = textSize
        self.boldText = boldText
        self.higherContrast = higherContrast
    }
}

/// The PlayStation accessibility settings sent with each cloud stream launch.
///
/// The screen reader, text size, bold text and higher contrast follow the device until changed here, so each is
/// stored as an override that is `nil` while it follows the device. Speech speed and voice volume use
/// PlayStation's defaults. The four text sizes are the console's: -1 small, 0 standard, 1 large and 2 very large.
public struct PlayStationAccessibilitySettings: Codable, Equatable, Sendable {
    /// The settings with every device default filled in, as a launch sends them.
    public struct Resolved: Equatable, Sendable {
        /// Whether the PlayStation screen reader reads system menus aloud.
        public let screenReader: Bool
        /// The screen reader's speech speed, from 0 to 8.
        public let screenReaderSpeed: Int
        /// The screen reader's voice volume, from 0 to 24.
        public let screenReaderVolume: Int
        /// The text size, from -1 to 2.
        public let textSize: Int
        /// Whether system menus use bold text.
        public let boldText: Bool
        /// Whether system menus use higher contrast.
        public let higherContrast: Bool
    }

    /// The screen reader choice, or `nil` to follow the device.
    public var screenReaderOverride: Bool?
    /// The screen reader's speech speed, from 0 to 8.
    public var screenReaderSpeed = 3
    /// The screen reader's voice volume, from 0 to 24.
    public var screenReaderVolume = 12
    /// The text size choice, from -1 to 2, or `nil` to follow the device.
    public var textSizeOverride: Int?
    /// The bold text choice, or `nil` to follow the device.
    public var boldTextOverride: Bool?
    /// The higher contrast choice, or `nil` to follow the device.
    public var higherContrastOverride: Bool?

    /// The speech speeds PlayStation offers, from Slow 3 to Fast 5; 3 is standard.
    public static let speedRange = 0...8
    /// The voice volumes PlayStation offers; 12 is the default.
    public static let volumeRange = 0...24
    /// The text sizes PlayStation offers: small, standard, large and very large.
    public static let textSizeRange = -1...2

    /// Creates settings that follow the device and use PlayStation's speech defaults.
    public init() {}

    /// Fills every choice that follows the device from the device's preferences.
    ///
    /// - Parameter defaults: The device's preferences.
    /// - Returns: The settings a launch sends.
    public func resolved(using defaults: PlayStationAccessibilityDefaults) -> Resolved {
        Resolved(
            screenReader: screenReaderOverride ?? defaults.screenReader,
            screenReaderSpeed: screenReaderSpeed,
            screenReaderVolume: screenReaderVolume,
            textSize: textSizeOverride ?? defaults.textSize,
            boldText: boldTextOverride ?? defaults.boldText,
            higherContrast: higherContrastOverride ?? defaults.higherContrast
        )
    }

    private enum CodingKeys: String, CodingKey {
        case screenReaderOverride
        case screenReaderSpeed
        case screenReaderVolume
        case textSizeOverride
        case largeTextOverride
        case boldTextOverride
        case higherContrastOverride
    }

    /// Decodes settings, resetting out-of-range values and reading an earlier Large text choice as Large or
    /// Standard text.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when a stored value has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        screenReaderOverride = try values.decodeIfPresent(Bool.self, forKey: .screenReaderOverride)
        let speed = try values.decodeIfPresent(Int.self, forKey: .screenReaderSpeed) ?? 3
        if Self.speedRange.contains(speed) {
            screenReaderSpeed = speed
        } else {
            screenReaderSpeed = 3
        }
        let volume = try values.decodeIfPresent(Int.self, forKey: .screenReaderVolume) ?? 12
        if Self.volumeRange.contains(volume) {
            screenReaderVolume = volume
        } else {
            screenReaderVolume = 12
        }
        if let size = try values.decodeIfPresent(Int.self, forKey: .textSizeOverride) {
            textSizeOverride = Self.textSizeRange.contains(size)
                ? size
                : nil
        } else if let large = try values.decodeIfPresent(Bool.self, forKey: .largeTextOverride) {
            textSizeOverride = large
                ? 1
                : 0
        }
        boldTextOverride = try values.decodeIfPresent(Bool.self, forKey: .boldTextOverride)
        higherContrastOverride = try values.decodeIfPresent(Bool.self, forKey: .higherContrastOverride)
    }

    /// Encodes the settings, leaving out choices that follow the device.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: `EncodingError` when a value cannot be written.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(screenReaderOverride, forKey: .screenReaderOverride)
        try values.encode(screenReaderSpeed, forKey: .screenReaderSpeed)
        try values.encode(screenReaderVolume, forKey: .screenReaderVolume)
        try values.encodeIfPresent(textSizeOverride, forKey: .textSizeOverride)
        try values.encodeIfPresent(boldTextOverride, forKey: .boldTextOverride)
        try values.encodeIfPresent(higherContrastOverride, forKey: .higherContrastOverride)
    }
}

extension PlayStationAccessibilitySettings: PersistedSettingValue {
    /// The key the PlayStation accessibility settings are stored under.
    public static var settingKey: SettingKey<PlayStationAccessibilitySettings> {
        SettingKeys.playStationAccessibility
    }

    /// The settings with speed, volume and text size kept within PlayStation's ranges.
    ///
    /// - Returns: The normalised settings.
    public func normalized() -> Self {
        var value = self
        value.screenReaderSpeed = min(
            max(screenReaderSpeed, Self.speedRange.lowerBound),
            Self.speedRange.upperBound
        )
        value.screenReaderVolume = min(
            max(screenReaderVolume, Self.volumeRange.lowerBound),
            Self.volumeRange.upperBound
        )
        value.textSizeOverride = textSizeOverride.map {
            min(max($0, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound)
        }
        return value
    }
}
