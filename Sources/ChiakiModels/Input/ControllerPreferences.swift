import Foundation

/// The saved preferences for one controller.
///
/// Decoding upgrades the older native haptics switch and defaults anything added later.
public struct ControllerPreferences: Codable, Equatable, Sendable {
    /// The name the user gave the controller.
    public var nickname = ""

    /// The preset the controller uses, or `nil` for the selected one.
    public var presetID: UUID?

    /// The stick dead zone, 0 to 0.5.
    public var deadZone = 0.12

    /// Whether the right stick's vertical axis is inverted.
    public var invertRightY = false

    /// Whether the sticks are swapped.
    public var swapSticks = false

    /// The rumble strength, 0 to 1.
    public var rumbleStrength = 1.0

    /// How haptics reach the controller.
    public var hapticFeedback = HapticFeedback.automatic

    /// The haptics strength, 0 to 2.4.
    public var hapticStrength = 1.0

    /// Whether adaptive trigger effects are played.
    public var adaptiveTriggersEnabled = true

    /// How strongly trigger effects play, never above the PS5's own setting.
    public var triggerStrength = TriggerStrength.strong

    /// The controller's light bar choice, or `nil` to use the global one.
    public var lightbar: ControllerLightbar?

    /// How face buttons are matched.
    public var buttonLayout = ButtonLayout.position

    /// How gyro steers a stick.
    public var stickGyro = StickGyroMode.automatic

    /// Creates the default preferences.
    public init() {
    }

    private enum CodingKeys: String, CodingKey {
        case nickname, presetID, deadZone, invertRightY, swapSticks, rumbleStrength
        case hapticFeedback, hapticStrength, adaptiveTriggersEnabled, triggerStrength, lightbar, buttonLayout
        case stickGyro
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case nativeHapticsEnabled
    }

    /// Decodes preferences, upgrading older values.
    ///
    /// - Parameter decoder: The decoder holding the stored preferences.
    /// - Throws: `DecodingError` when a required value is missing or has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try values.decode(String.self, forKey: .nickname)
        presetID = try values.decodeIfPresent(UUID.self, forKey: .presetID)
        deadZone = try values.decode(Double.self, forKey: .deadZone)
        invertRightY = try values.decode(Bool.self, forKey: .invertRightY)
        swapSticks = try values.decode(Bool.self, forKey: .swapSticks)
        rumbleStrength = try values.decode(Double.self, forKey: .rumbleStrength)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let nativeHapticsEnabled = try legacy
            .decodeIfPresent(Bool.self, forKey: .nativeHapticsEnabled) ?? true
        hapticFeedback = (try? values.decodeIfPresent(HapticFeedback.self, forKey: .hapticFeedback))
            ?? (nativeHapticsEnabled
                ? .automatic
                : .off)
        hapticStrength = try values.decodeIfPresent(Double.self, forKey: .hapticStrength) ?? 1.0
        adaptiveTriggersEnabled = try values
            .decodeIfPresent(Bool.self, forKey: .adaptiveTriggersEnabled) ?? true
        triggerStrength = (try? values.decodeIfPresent(TriggerStrength.self, forKey: .triggerStrength))
            ?? .strong
        lightbar = try values.decodeIfPresent(ControllerLightbar.self, forKey: .lightbar)
        buttonLayout = (try? values.decodeIfPresent(ButtonLayout.self, forKey: .buttonLayout)) ?? .position
        stickGyro = (try? values.decodeIfPresent(StickGyroMode.self, forKey: .stickGyro)) ?? .automatic
    }

    /// How haptics play on a device under these preferences.
    ///
    /// - Parameter device: The device.
    /// - Returns: Native, rumble or nothing, depending on the choice and what the device has.
    public func hapticOutput(for device: ControllerDevice) -> HapticOutput {
        switch hapticFeedback {
        case .off:
            return .none
        case .rumble:
            return device.rumble
                ? .rumble
                : .none
        case .automatic:
            if device.nativeHaptics {
                return .native
            }
            return device.rumble
                ? .rumble
                : .none
        }
    }
}

/// How haptics actually play on one controller.
public enum HapticOutput: Equatable, Sendable {
    /// The console's haptics play natively.
    case native

    /// The haptics are converted to rumble.
    case rumble

    /// Nothing plays.
    case none
}

/// The saved choice for how the console's haptics reach a controller.
public enum HapticFeedback: String, Codable, CaseIterable, Equatable, Sendable {
    /// Native haptics where the controller has them, otherwise rumble.
    case automatic

    /// Always rumble.
    case rumble

    /// No haptics.
    case off
}
