/// The inputs that decide every seated controller's lights.
public struct ControllerLightPlan: Equatable, Sendable {
    /// The light bar choices.
    public var lightbars: ControllerLightbars

    /// The colours the game set, by seat.
    public var gameColors: [UInt8: UInt32]

    /// The devices, by seat.
    public var devices: [UInt8: ControllerDevice]

    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - lightbars: The light bar choices.
    ///   - gameColors: The game's colours by seat.
    ///   - devices: The devices by seat.
    public init(
        lightbars: ControllerLightbars = ControllerLightbars(),
        gameColors: [UInt8: UInt32] = [:],
        devices: [UInt8: ControllerDevice] = [:]
    ) {
        self.lightbars = lightbars
        self.gameColors = gameColors
        self.devices = devices
    }

    /// The colour player 1's controller shows.
    public var playerOneColor: UInt32? {
        lightbars.color(for: devices[0], game: gameColors[0])
    }

    /// The target for every seated controller other than the keyboard.
    ///
    /// - Returns: The targets by device id.
    public func targets() -> [UInt32: ControllerLightTarget] {
        var targets: [UInt32: ControllerLightTarget] = [:]
        for (pad, device) in devices where !device.isKeyboard {
            let rgb = device.lights
                ? lightbars.color(for: device, game: gameColors[pad])
                : nil
            targets[device.id] = ControllerLightTarget(rgb: rgb, player: Int(pad))
        }
        return targets
    }
}

/// Remembers what was applied to each controller's lights so only differences are sent.
public struct ControllerLightLedger: Equatable, Sendable {
    /// The targets last applied, by device id.
    public private(set) var applied: [UInt32: ControllerLightTarget] = [:]

    /// Creates an empty ledger.
    public init() {
    }

    /// Records new targets and returns what must change.
    ///
    /// - Parameter targets: The targets by device id.
    /// - Returns: The changes to send.
    public mutating func reconcile(to targets: [UInt32: ControllerLightTarget]) -> ControllerLightChanges {
        var changes = ControllerLightChanges()
        for (id, target) in targets {
            let previous = applied[id]
            if previous?.player != target.player {
                changes.players[id] = target.player
            }
            if let rgb = target.rgb {
                if previous?.rgb != rgb {
                    changes.colors[id] = rgb
                }
            } else if previous?.rgb != nil {
                changes.defaults.insert(id)
            }
        }
        for (id, previous) in applied where targets[id] == nil {
            changes.released[id] = previous.rgb != nil
        }
        applied = targets
        return changes
    }
}

/// The light commands needed to move controllers from what was applied to new targets.
public struct ControllerLightChanges: Equatable, Sendable {
    /// New player numbers, by device id.
    public var players: [UInt32: Int] = [:]

    /// New colours, by device id.
    public var colors: [UInt32: UInt32] = [:]

    /// Devices that go back to their default colour.
    public var defaults: Set<UInt32> = []

    /// Devices no longer targeted, and whether each had a colour to clear.
    public var released: [UInt32: Bool] = [:]

    /// Whether nothing needs to be sent.
    public var isEmpty: Bool {
        players.isEmpty && colors.isEmpty && defaults.isEmpty && released.isEmpty
    }
}

/// What one controller's lights should show: a colour and a player number.
public struct ControllerLightTarget: Equatable, Sendable {
    /// The colour, or `nil` for the device's default.
    public var rgb: UInt32?

    /// The zero-based player number.
    public var player: Int

    /// Creates a target.
    ///
    /// - Parameters:
    ///   - rgb: The colour.
    ///   - player: The player number.
    public init(rgb: UInt32?, player: Int) {
        self.rgb = rgb
        self.player = player
    }
}
