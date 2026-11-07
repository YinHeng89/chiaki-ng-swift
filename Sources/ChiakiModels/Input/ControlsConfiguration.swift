import Foundation

/// The persisted controls: keyboard and mouse use, presets, per-controller preferences, shortcuts and lights.
///
/// Decoding derives ``keyboardMode`` from the older keyboard switch when it is missing and defaults anything
/// added later. ``validated()`` enforces every limit before a configuration is saved.
public struct ControlsConfiguration: Codable, Equatable, Sendable {
    /// The controller key that means "keyboard only".
    public static let keyboardOnlyKey = "keyboard-only"

    /// The most presets a configuration may hold.
    public static let presetLimit = 32

    /// The format version.
    public var version = 1

    /// What the keyboard does during a stream.
    public var keyboardMode = KeyboardMode.typeOnConsole

    /// Whether the mouse drives the controller.
    public var mouseEnabled = false

    /// The controller chosen for player 1, by preference key.
    public var selectedControllerKey: String?

    /// The controllers chosen for players 2 to 4, by preference key; `nil` where the player takes the first
    /// available controller.
    public var seatControllerKeys: [String?] = Array(repeating: nil, count: playerCount - 1)

    /// The preset used by controllers without their own.
    public var selectedPresetID = InputPreset.defaultID

    /// The presets.
    public var presets = [InputPreset.standard]

    /// The per-controller preferences, by preference key.
    public var controllers: [String: ControllerPreferences] = [:]

    /// The controllers seen before, by preference key, so they stay listed while disconnected.
    public var remembered: [String: RememberedController] = [:]

    /// How many players a stream seats.
    public static let playerCount = 4

    /// Each player's own preset, player 1 first; `nil` where the player uses each controller's preset.
    ///
    /// A player's preset wins over the preset of the controller they hold.
    public var playerPresets: [UUID?] = Array(repeating: nil, count: playerCount)

    /// Whether the on-screen touchpad starts enabled: on where the screen is touched, off where it is not.
    public static var onScreenTouchpadDefault: Bool {
        #if os(iOS)
            return true
        #else
            return false
        #endif
    }

    /// Whether the on-screen touchpad can be shown during a stream.
    public var onScreenTouchpad = Self.onScreenTouchpadDefault

    /// The shortcut that opens the touchpad.
    public var touchpadShortcut = TouchpadShortcut.standard

    /// The shortcut that opens the stream menu.
    public var streamMenuShortcut = StreamMenuShortcut.standard

    /// Whether input reaches the stream while the app is in the background.
    public var backgroundInput = false

    /// Whether the device's own motion sensors drive the controller's motion.
    public var deviceMotion = false

    /// When the on-screen gamepad is shown at the start of a touch stream.
    public var virtualGamepad = VirtualGamepadPresence.automatic

    /// The global light bar choice.
    public var lightbar = ControllerLightbar.followGame

    /// Creates the default configuration.
    public init() {
    }

    private enum CodingKeys: String, CodingKey {
        case version, keyboardMode, keyboardEnabled, mouseEnabled, selectedControllerKey, seatControllerKeys,
             selectedPresetID
        case presets, controllers, remembered, playerPresets, onScreenTouchpad, touchpadShortcut,
             streamMenuShortcut, backgroundInput,
             deviceMotion, virtualGamepad, lightbar
    }

    /// Decodes a configuration, upgrading the older keyboard switch.
    ///
    /// - Parameter decoder: The decoder holding the stored configuration.
    /// - Throws: `DecodingError` when a required value is missing or has the wrong type.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        mouseEnabled = try values.decode(Bool.self, forKey: .mouseEnabled)
        selectedControllerKey = try values.decodeIfPresent(String.self, forKey: .selectedControllerKey)
        seatControllerKeys = try values.decodeIfPresent([String?].self, forKey: .seatControllerKeys)
            ?? Array(repeating: nil, count: Self.playerCount - 1)
        selectedPresetID = try values.decode(UUID.self, forKey: .selectedPresetID)
        presets = try values.decode([InputPreset].self, forKey: .presets)
        controllers = try values.decode([String: ControllerPreferences].self, forKey: .controllers)
        remembered = try values
            .decodeIfPresent([String: RememberedController].self, forKey: .remembered) ?? [:]
        playerPresets = try values.decodeIfPresent([UUID?].self, forKey: .playerPresets)
            ?? Array(repeating: nil, count: Self.playerCount)
        onScreenTouchpad = try values.decodeIfPresent(Bool.self, forKey: .onScreenTouchpad)
            ?? Self.onScreenTouchpadDefault
        touchpadShortcut = try values.decodeIfPresent(TouchpadShortcut.self, forKey: .touchpadShortcut)
            ?? .standard
        streamMenuShortcut = try values.decodeIfPresent(StreamMenuShortcut.self, forKey: .streamMenuShortcut)
            ?? .standard
        backgroundInput = try values.decodeIfPresent(Bool.self, forKey: .backgroundInput) ?? false
        deviceMotion = try values.decodeIfPresent(Bool.self, forKey: .deviceMotion) ?? false
        virtualGamepad = try values.decodeIfPresent(VirtualGamepadPresence.self, forKey: .virtualGamepad)
            ?? .automatic
        lightbar = try values.decodeIfPresent(ControllerLightbar.self, forKey: .lightbar) ?? .followGame
        if let mode = try values.decodeIfPresent(KeyboardMode.self, forKey: .keyboardMode) {
            keyboardMode = mode
        } else {
            let keyboardEnabled = try values.decodeIfPresent(Bool.self, forKey: .keyboardEnabled) ?? true
            keyboardMode = keyboardEnabled && (keyboardOnly || customisedKeyboard)
                ? .controller
                : .typeOnConsole
        }
    }

    /// Encodes the configuration; the retired keyboard switch is never written.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: The encoder's error.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(keyboardMode, forKey: .keyboardMode)
        try values.encode(mouseEnabled, forKey: .mouseEnabled)
        try values.encodeIfPresent(selectedControllerKey, forKey: .selectedControllerKey)
        try values.encode(seatControllerKeys, forKey: .seatControllerKeys)
        try values.encode(selectedPresetID, forKey: .selectedPresetID)
        try values.encode(presets, forKey: .presets)
        try values.encode(controllers, forKey: .controllers)
        try values.encode(remembered, forKey: .remembered)
        try values.encode(playerPresets, forKey: .playerPresets)
        try values.encode(onScreenTouchpad, forKey: .onScreenTouchpad)
        try values.encode(touchpadShortcut, forKey: .touchpadShortcut)
        try values.encode(streamMenuShortcut, forKey: .streamMenuShortcut)
        try values.encode(backgroundInput, forKey: .backgroundInput)
        try values.encode(deviceMotion, forKey: .deviceMotion)
        try values.encode(virtualGamepad, forKey: .virtualGamepad)
        try values.encode(lightbar, forKey: .lightbar)
    }

    /// Whether the keyboard drives the controller.
    public var keyboardControlsController: Bool {
        keyboardMode == .controller
    }

    private var customisedKeyboard: Bool {
        let keys = { (preset: InputPreset) in
            preset.bindings.filter {
                $0.source == .macKey
            }
        }
        return keys(preset()) != keys(.standard)
    }

    /// Whether player 1 is the keyboard alone.
    public var keyboardOnly: Bool {
        selectedControllerKey == Self.keyboardOnlyKey
    }

    /// The controller a player chose, by preference key.
    ///
    /// - Parameter player: The player, `0` for player 1.
    /// - Returns: The preference key, ``keyboardOnlyKey`` for player 1 playing with the keyboard alone, or
    ///   `nil` when the player takes the first available controller.
    public func controllerKey(forPlayer player: Int) -> String? {
        guard player > 0 else {
            return selectedControllerKey
        }
        return seatControllerKeys.indices.contains(player - 1)
            ? seatControllerKeys[player - 1]
            : nil
    }

    /// Chooses the controller a player plays with, taking it from any other player who had chosen it.
    ///
    /// Only player 1 may choose ``keyboardOnlyKey``; for another player it clears the choice.
    ///
    /// - Parameters:
    ///   - key: The controller's preference key, or `nil` for the first available controller.
    ///   - player: The player, `0` for player 1.
    public mutating func setControllerKey(_ key: String?, forPlayer player: Int) {
        guard (0..<Self.playerCount).contains(player) else {
            return
        }
        let chosen = player > 0 && key == Self.keyboardOnlyKey
            ? nil
            : key
        if let chosen, chosen != Self.keyboardOnlyKey {
            if player != 0, selectedControllerKey == chosen {
                selectedControllerKey = nil
            }
            seatControllerKeys = seatControllerKeys.enumerated().map { index, key in
                index != player - 1 && key == chosen
                    ? nil
                    : key
            }
        }
        if player == 0 {
            selectedControllerKey = chosen
        } else if seatControllerKeys.indices.contains(player - 1) {
            seatControllerKeys[player - 1] = chosen
        }
    }

    /// The controllers the other players chose, which a player taking the first available controller skips.
    ///
    /// - Parameter player: The player, `0` for player 1.
    /// - Returns: The preference keys the other players chose.
    public func controllerKeys(takenFromPlayer player: Int) -> Set<String> {
        Set((0..<Self.playerCount).filter { $0 != player }.compactMap { controllerKey(forPlayer: $0) })
            .subtracting([Self.keyboardOnlyKey])
    }

    /// The global and per-controller light bar choices.
    public var lightbars: ControllerLightbars {
        ControllerLightbars(
            global: lightbar,
            controllers: controllers.compactMapValues(\.lightbar)
        )
    }

    /// The preset a controller uses.
    ///
    /// - Parameter preferences: The controller's preferences, or `nil` for the selected preset.
    /// - Returns: The controller's own preset, the selected one, or ``InputPreset/standard``.
    public func preset(for preferences: ControllerPreferences? = nil) -> InputPreset {
        presets.first { $0.id == (preferences?.presetID ?? selectedPresetID) } ?? .standard
    }

    /// The preset a controller uses, adapted to what the controller lacks.
    ///
    /// A controller without a touchpad gets the touchpad on Back when the preset leaves it on the touchpad
    /// button. A preset with the standard bindings also gets gyro hold on the right stick button for a
    /// controller without gyro.
    ///
    /// - Parameters:
    ///   - preferences: The controller's preferences.
    ///   - touchpad: Whether the controller has a touchpad.
    ///   - gyro: Whether the controller has gyro.
    /// - Returns: The preset.
    public func preset(for preferences: ControllerPreferences?, touchpad: Bool,
                       gyro: Bool = true) -> InputPreset {
        Self.adapted(preset(for: preferences), touchpad: touchpad, gyro: gyro)
    }

    /// Whether a controller has a preset no other controller shares.
    ///
    /// - Parameter key: The controller's preference key.
    /// - Returns: `true` when its preset is its own.
    public func ownsPreset(_ key: String) -> Bool {
        guard let id = controllers[key]?.presetID, id != selectedPresetID,
              presets.contains(where: { $0.id == id }) else {
            return false
        }
        return !controllers.contains { $0.key != key && $0.value.presetID == id }
    }

    /// Gives a controller its own copy of the preset it uses, so its bindings can change alone.
    ///
    /// - Parameters:
    ///   - key: The controller's preference key.
    ///   - name: The name for the copy, made unique.
    ///   - touchpad: Whether the controller has a touchpad.
    ///   - gyro: Whether the controller has gyro.
    ///   - id: The copy's id.
    /// - Returns: `false` when ``presetLimit`` is reached; `true` when the controller has its own preset.
    public mutating func givePreset(to key: String, named name: String, touchpad: Bool, gyro: Bool = true,
                                    id: UUID = UUID()) -> Bool {
        guard !ownsPreset(key) else {
            return true
        }
        guard presets.count < Self.presetLimit else {
            return false
        }
        var preferences = controllers[key] ?? ControllerPreferences()
        var copy = preset(for: preferences, touchpad: touchpad, gyro: gyro)
        copy.id = id
        copy.name = uniquePresetName(name)
        presets.append(copy)
        preferences.presetID = copy.id
        controllers[key] = preferences
        return true
    }

    private func uniquePresetName(_ name: String) -> String {
        let base = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(70))
        let names = Set(presets.map(\.name))
        let start = base.isEmpty
            ? String(localized: .controlsPresetControllerName)
            : base
        guard names.contains(start) else {
            return start
        }
        var number = 2
        while names.contains("\(start) \(number)") {
            number += 1
        }
        return "\(start) \(number)"
    }

    /// Checks every limit and consistency rule.
    ///
    /// - Returns: The configuration unchanged.
    /// - Throws: ``InputFailure/duplicateBinding`` for a clashing binding, otherwise
    ///   ``InputFailure/invalidConfiguration``.
    public func validated() throws -> Self {
        if let selectedControllerKey, selectedControllerKey.isEmpty || selectedControllerKey.count > 160 {
            throw InputFailure.invalidConfiguration
        }
        let chosen = ([selectedControllerKey] + seatControllerKeys).compactMap(\.self)
            .filter { $0 != Self.keyboardOnlyKey }
        guard seatControllerKeys.count == Self.playerCount - 1,
              seatControllerKeys.allSatisfy({ key in
                  key.map { !$0.isEmpty && $0.count <= 160 && $0 != Self.keyboardOnlyKey } ?? true
              }),
              Set(chosen).count == chosen.count else {
            throw InputFailure.invalidConfiguration
        }
        guard version == 1, !presets.isEmpty, presets.count <= 32,
              Set(presets.map(\.id)).count == presets.count,
              presets.contains(where: { $0.id == selectedPresetID }), controllers.count <= 128,
              touchpadShortcut.isValid, streamMenuShortcut.isValid,
              !streamMenuShortcut.overlaps(touchpadShortcut), lightbar.isValid else {
            throw InputFailure.invalidConfiguration
        }
        for preset in presets {
            guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  preset.name.count <= 80, preset.bindings.count <= 128 else {
                throw InputFailure.invalidConfiguration
            }
            var sources = Set<String>(), targets = Set<String>()
            for binding in preset.bindings {
                let source = binding.target == .gyroHold
                    ? "\(binding.source.rawValue):\(binding.code):hold"
                    : "\(binding.source.rawValue):\(binding.code)"
                let maximum = binding.source == .macKey
                    ? 127
                    : binding.source == .mouseButton
                        ? 7
                        : 25
                guard (0...maximum).contains(binding.code), binding.label.count <= 40,
                      sources.insert(source).inserted,
                      targets.insert("\(binding.source.rawValue):\(binding.target.rawValue)").inserted else {
                    throw InputFailure.duplicateBinding
                }
            }
        }
        guard playerPresets.count == Self.playerCount,
              playerPresets.allSatisfy({ id in id.map { id in presets.contains { $0.id == id } } ?? true }),
              remembered.count <= Self.rememberedLimit,
              remembered.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 160 && $0.value.name.count <= 120 })
        else {
            throw InputFailure.invalidConfiguration
        }
        for (key, value) in controllers {
            guard !key.isEmpty, key.count <= 160, value.nickname.count <= 80,
                  value.deadZone.isFinite, (0...0.5).contains(value.deadZone),
                  value.rumbleStrength.isFinite, (0...1).contains(value.rumbleStrength),
                  value.hapticStrength.isFinite, (0...2.4).contains(value.hapticStrength),
                  value.presetID == nil || presets.contains(where: { $0.id == value.presetID }),
                  value.lightbar?.isValid ?? true else {
                throw InputFailure.invalidConfiguration
            }
        }
        return self
    }
}

extension ControlsConfiguration: PersistedSettingValue {
    /// The key of the controls configuration. The app stores it in its own table, not under this name.
    public static var settingKey: SettingKey<ControlsConfiguration> {
        SettingKey(name: "input.configuration.v1", defaultValue: ControlsConfiguration()) {
            try $0.validated()
        }
    }
}

extension ControlsConfiguration {
    /// The preset a seated player's controller uses: the player's own preset when they have one, otherwise
    /// the controller's, adapted to what the controller lacks.
    ///
    /// - Parameters:
    ///   - player: The player's index, 0 for player 1.
    ///   - preferences: The controller's preferences.
    ///   - touchpad: Whether the controller has a touchpad.
    ///   - gyro: Whether the controller has gyro.
    /// - Returns: The preset.
    public func preset(forPlayer player: Int, preferences: ControllerPreferences?, touchpad: Bool,
                       gyro: Bool = true) -> InputPreset {
        guard let own = playerPreset(player) else {
            return preset(for: preferences, touchpad: touchpad, gyro: gyro)
        }
        return Self.adapted(own, touchpad: touchpad, gyro: gyro)
    }

    /// A player's own preset.
    ///
    /// - Parameter player: The player's index, 0 for player 1.
    /// - Returns: The preset, or `nil` when the player uses each controller's preset.
    public func playerPreset(_ player: Int) -> InputPreset? {
        guard playerPresets.indices.contains(player), let id = playerPresets[player] else {
            return nil
        }
        return presets.first { $0.id == id }
    }

    /// The preset the keyboard uses: player 1's own preset, otherwise the selected preset.
    public var keyboardPreset: InputPreset {
        playerPreset(0) ?? preset()
    }

    /// Gives a player their own copy of the selected preset.
    ///
    /// - Parameters:
    ///   - player: The player's index, 0 for player 1.
    ///   - name: The copy's name, made unique.
    ///   - id: The copy's id.
    /// - Returns: `false` when ``presetLimit`` is reached; `true` when the player has their own preset.
    public mutating func givePlayerPreset(_ player: Int, named name: String, id: UUID = UUID()) -> Bool {
        guard playerPresets.indices.contains(player) else {
            return false
        }
        guard playerPreset(player) == nil else {
            return true
        }
        guard presets.count < Self.presetLimit else {
            return false
        }
        var copy = preset()
        copy.id = id
        copy.name = uniquePresetName(name)
        presets.append(copy)
        playerPresets[player] = id
        return true
    }

    /// Returns a player to each controller's preset, deleting the player's preset unless something else uses
    /// it.
    ///
    /// - Parameter player: The player's index, 0 for player 1.
    public mutating func removePlayerPreset(_ player: Int) {
        guard playerPresets.indices.contains(player), let id = playerPresets[player] else {
            return
        }
        playerPresets[player] = nil
        let used = id == selectedPresetID || playerPresets.contains(id)
            || controllers.values.contains { $0.presetID == id }
        if !used {
            presets.removeAll { $0.id == id }
        }
    }

    /// Stops every player and controller from using a preset that is about to go.
    ///
    /// - Parameter id: The preset's id.
    public mutating func release(_ id: UUID) {
        playerPresets = playerPresets.map {
            $0 == id
                ? nil
                : $0
        }
        for key in controllers.keys where controllers[key]?.presetID == id {
            controllers[key]?.presetID = nil
        }
    }

    private static func adapted(_ preset: InputPreset, touchpad: Bool, gyro: Bool) -> InputPreset {
        let standardLike = preset.bindings == InputPreset.standard.bindings
        var adapted = preset
        if !touchpad {
            adapted = standardLike
                ? adapted.withoutTouchpad
                : adapted.touchpadOffItsButton
        }
        if !gyro, standardLike {
            adapted = adapted.withoutGyro
        }
        return adapted
    }
}

extension ControlsConfiguration {
    /// The most controllers a configuration remembers.
    public static let rememberedLimit = 64

    /// Records connected controllers and the moment others were last seen.
    ///
    /// A controller is recorded when it is first seen or its description changes. One that was connected and
    /// is no longer has its last-seen time moved to `now`. When ``rememberedLimit`` is reached the controller
    /// seen longest ago is dropped first.
    ///
    /// - Parameters:
    ///   - connected: The controllers connected now, without the keyboard.
    ///   - previous: The controllers connected at the last check.
    ///   - now: The current time.
    /// - Returns: `true` when anything worth saving changed.
    public mutating func remember(_ connected: [ControllerDevice], previous: [ControllerDevice],
                                  at now: Date) -> Bool {
        var changed = false
        let current = Set(connected.map(\.preferenceKey))
        for device in connected where !device.isKeyboard {
            let key = device.preferenceKey
            if let known = remembered[key], known.describes(device),
               previous.contains(where: { $0.preferenceKey == key }) {
                continue
            }
            remembered[key] = RememberedController(device, seen: now)
            changed = true
        }
        for device in previous where !current.contains(device.preferenceKey) {
            guard remembered[device.preferenceKey] != nil else {
                continue
            }
            remembered[device.preferenceKey]?.lastSeen = now
            changed = true
        }
        while remembered.count > Self.rememberedLimit,
              let oldest = remembered.filter({ !current.contains($0.key) }).min(by: {
                  $0.value.lastSeen < $1.value.lastSeen
              })?.key {
            remembered.removeValue(forKey: oldest)
        }
        return changed
    }

    /// Whether ``remember(_:previous:at:)`` would change anything, so the time is only read when it would.
    ///
    /// - Parameters:
    ///   - connected: The controllers connected now.
    ///   - previous: The controllers connected at the last check.
    /// - Returns: `true` when a controller appeared, changed or went away.
    public func needsRemembering(_ connected: [ControllerDevice], previous: [ControllerDevice]) -> Bool {
        let now = Set(connected.filter { !$0.isKeyboard }.map(\.preferenceKey))
        let before = Set(previous.filter { !$0.isKeyboard }.map(\.preferenceKey))
        guard now == before else {
            return true
        }
        return connected.contains { device in
            !device.isKeyboard && !(remembered[device.preferenceKey]?.describes(device) ?? false)
        }
    }

    /// Forgets a controller: its record, its preferences, its own preset and any player's choice of it.
    ///
    /// A preset another controller also uses is kept.
    ///
    /// - Parameter key: The controller's preference key.
    public mutating func forget(_ key: String) {
        let owned = ownsPreset(key)
            ? controllers[key]?.presetID
            : nil
        remembered.removeValue(forKey: key)
        controllers.removeValue(forKey: key)
        if let owned {
            presets.removeAll { $0.id == owned }
        }
        if selectedControllerKey == key {
            selectedControllerKey = nil
        }
        seatControllerKeys = seatControllerKeys.map {
            $0 == key
                ? nil
                : $0
        }
    }
}

/// What the app keeps about a controller after it disconnects, so its bindings and preferences stay
/// editable while it is away.
public struct RememberedController: Codable, Equatable, Sendable {
    /// The name the controller reported.
    public var name: String

    /// The maker family, which decides its artwork and button glyphs.
    public var family: ControllerFamily

    /// Whether the controller reports its own identity, rather than sharing preferences with its model.
    public var individual: Bool

    /// Whether the controller has a touchpad.
    public var touchpad: Bool

    /// Whether the controller has motion sensors.
    public var motion: Bool

    /// Whether the controller has rumble motors.
    public var rumble: Bool

    /// Whether the controller has a light bar.
    public var lights: Bool

    /// Whether the controller has adaptive triggers.
    public var adaptiveTriggers: Bool

    /// When the controller was last connected.
    public var lastSeen: Date

    /// Captures what is worth keeping from a connected controller.
    ///
    /// - Parameters:
    ///   - device: The connected controller.
    ///   - seen: The moment it was seen.
    public init(_ device: ControllerDevice, seen: Date) {
        name = device.name
        family = device.family
        individual = device.individual
        touchpad = device.touchpad
        motion = device.motion
        rumble = device.rumble
        lights = device.lights
        adaptiveTriggers = device.adaptiveTriggers
        lastSeen = seen
    }

    /// Whether this record already describes the controller, ignoring when it was seen.
    ///
    /// - Parameter device: The connected controller.
    /// - Returns: `true` when nothing but the time would change.
    public func describes(_ device: ControllerDevice) -> Bool {
        Self(device, seen: lastSeen) == self
    }

    /// A stand-in device for a controller that is not connected, so settings views can describe it.
    ///
    /// - Parameter key: The controller's preference key.
    /// - Returns: A device with no runtime identifier.
    public func device(key: String) -> ControllerDevice {
        ControllerDevice(
            id: 0, preferenceKey: key, name: name, transport: String(localized: .controlsDeviceNotConnected),
            individual: individual,
            rumble: rumble, lights: lights, motion: motion, touchpad: touchpad,
            adaptiveTriggers: adaptiveTriggers, family: family
        )
    }
}

/// What the Mac keyboard does during a stream.
public enum KeyboardMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Typing goes to the console's on-screen keyboard.
    case typeOnConsole

    /// Keys drive the controller through the bindings.
    case controller
}
