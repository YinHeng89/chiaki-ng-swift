import ChiakiModels

/// Picks which connected controller drives player one.
public enum PlayerOneChoice {
    /// Chooses the player one controller, preferring an explicitly adopted device, then the current device
    /// when
    /// it differs from a connected preferred one, then the preferred device, then any connected device.
    /// - Parameters:
    ///   - devices: The connected controllers.
    ///   - current: The identifier of the controller currently acting as player one, if any.
    ///   - primaryKey: The saved preference key for player one; the keyboard-only key yields no controller.
    ///   - adopting: The identifier of a controller the user just chose to adopt, if any.
    /// - Returns: The chosen controller, or `nil` when none is connected or keyboard-only play is configured.
    public static func choose(from devices: [ControllerDevice], current: UInt32?, primaryKey: String?,
                              adopting: UInt32?) -> ControllerDevice? {
        if let adopting, let chosen = devices.first(where: { $0.id == adopting }) {
            return chosen
        }
        guard primaryKey != ControlsConfiguration.keyboardOnlyKey else {
            return nil
        }
        let preferred = devices.first { $0.preferenceKey == primaryKey }
        let connected = current.flatMap { id in
            devices.first { $0.id == id }
        }
        if let connected, preferred != nil, connected.preferenceKey != primaryKey {
            return connected
        }
        return preferred ?? connected ?? devices.first
    }
}
