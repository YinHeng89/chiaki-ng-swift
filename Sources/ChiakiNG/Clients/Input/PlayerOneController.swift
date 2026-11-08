import ChiakiFeatures
import ChiakiModels

/// Which controller plays as player one, and the preferences it plays with.
///
/// Until the user or the saved configuration names a controller, the first one connected becomes player one.
/// A controller chosen explicitly wins over the saved preference; the keyboard-only preference leaves player
/// one without a controller.
struct PlayerOneController {
    /// What a new look at the connected controllers decided.
    enum Choice: Equatable {
        /// Player one keeps its controller.
        case unchanged
        /// Player one moves to another controller, or to none.
        case changed(ControllerDevice?)
    }

    /// Player one's controller, or `nil` when only the keyboard plays.
    private(set) var device: ControllerDevice?

    /// The preferences of player one's controller.
    private(set) var preferences = ControllerPreferences()

    private var primaryKey: String?
    private var primaryResolved: Bool
    private var reserved: Set<String>

    /// Creates the controller from the saved preference.
    ///
    /// - Parameters:
    ///   - primaryKey: The preference key of the saved player one, or `nil` when none was saved.
    ///   - reserved: The preference keys of the controllers the other players chose, which player one never
    ///     takes as the first available controller.
    init(primaryKey: String?, reserved: Set<String> = []) {
        self.primaryKey = primaryKey
        self.reserved = reserved
        primaryResolved = primaryKey != nil
    }

    /// The preference key the app-wide controller routing should treat as the stream's.
    var preferredKey: String {
        device?.preferenceKey ?? primaryKey ?? ControlsConfiguration.keyboardOnlyKey
    }

    /// Stops adopting the first controller that connects as player one.
    mutating func resolve() {
        primaryResolved = true
    }

    /// Chooses player one among the controllers no couch seat holds.
    ///
    /// - Parameters:
    ///   - devices: The free controllers, in connection order.
    ///   - chosen: A controller the user just picked, if any.
    /// - Returns: Whether player one changes; call ``adopt(_:configuration:)`` with the new controller.
    mutating func choose(from devices: [ControllerDevice], adopting chosen: UInt32? = nil) -> Choice {
        let devices = devices.filter {
            $0.id == chosen || $0.preferenceKey == primaryKey || !reserved.contains($0.preferenceKey)
        }
        if !primaryResolved, let first = devices.first {
            primaryKey = first.preferenceKey
            primaryResolved = true
        }
        let next = PlayerOneChoice.choose(
            from: devices, current: device?.id, primaryKey: primaryKey, adopting: chosen
        )
        guard next?.id != device?.id else {
            return .unchanged
        }
        return .changed(next)
    }

    /// Makes a controller player one.
    ///
    /// - Parameters:
    ///   - next: The controller, or `nil` for the keyboard.
    ///   - configuration: Where its preferences come from.
    mutating func adopt(_ next: ControllerDevice?, configuration: ControlsConfiguration) {
        device = next
        preferences = next.flatMap { configuration.controllers[$0.preferenceKey] } ?? .init()
    }

    /// Forgets player one's controller after it disconnected, keeping its preferences until another is chosen.
    mutating func disconnect() {
        device = nil
    }

    /// Records the user's choice of player one.
    ///
    /// - Parameters:
    ///   - chosen: The controller, or the keyboard.
    ///   - seated: Whether a couch seat already holds the controller.
    /// - Returns: `false` when the controller sits on a couch seat and cannot become player one.
    mutating func prefer(_ chosen: ControllerDevice, seated: Bool) -> Bool {
        if chosen.isKeyboard {
            primaryKey = ControlsConfiguration.keyboardOnlyKey
        } else {
            guard !seated else {
                return false
            }
            primaryKey = chosen.preferenceKey
        }
        primaryResolved = true
        return true
    }

    /// Takes player one's preferences from a new configuration.
    ///
    /// - Parameter configuration: The configuration.
    /// - Returns: The preferences player one had before.
    mutating func reload(_ configuration: ControlsConfiguration) -> ControllerPreferences {
        reserved = configuration.controllerKeys(takenFromPlayer: 0)
        let previous = preferences
        preferences = device.flatMap { configuration.controllers[$0.preferenceKey] } ?? .init()
        return previous
    }

    /// Whether player one's microphone button toggles the stream's microphone.
    ///
    /// - Parameters:
    ///   - configuration: The configuration whose bindings may claim the button.
    ///   - microphone: Whether the stream offers a microphone.
    /// - Returns: `true` when the controller has the button and no binding uses it.
    func ownsMicrophoneButton(in configuration: ControlsConfiguration, microphone: Bool) -> Bool {
        guard microphone, device?.adaptiveTriggers == true else {
            return false
        }
        return !configuration.preset(forPlayer: 0, preferences: preferences, touchpad: true).bindings
            .contains {
                $0.source == .gamepadButton && $0.code == Int(GameInputLane.microphoneButton)
            }
    }
}
