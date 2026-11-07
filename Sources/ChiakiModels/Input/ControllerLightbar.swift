import Foundation

/// The choice of light bar colour for a controller.
public enum ControllerLightbar: Codable, Equatable, Hashable, Sendable {
    /// Use the colour the game sets.
    case followGame

    /// Use a fixed 24-bit RGB colour.
    case fixed(rgb: UInt32)

    /// The largest valid RGB value.
    public static let maximumRGB: UInt32 = 0xffffff

    /// Whether a fixed colour is a valid 24-bit value.
    public var isValid: Bool {
        switch self {
        case .followGame:
            true
        case .fixed(let rgb):
            rgb <= Self.maximumRGB
        }
    }

    /// The colour to show.
    ///
    /// - Parameter game: The colour the game set, if any.
    /// - Returns: The game's colour or the fixed colour.
    public func color(game: UInt32?) -> UInt32? {
        switch self {
        case .followGame:
            game
        case .fixed(let rgb):
            rgb
        }
    }
}

/// The global light bar choice and each controller's override.
public struct ControllerLightbars: Equatable, Sendable {
    /// The choice for controllers without their own.
    public var global: ControllerLightbar

    /// The per-controller choices, by preference key.
    public var controllers: [String: ControllerLightbar]

    /// Creates the choices.
    ///
    /// - Parameters:
    ///   - global: The global choice.
    ///   - controllers: The per-controller choices.
    public init(global: ControllerLightbar = .followGame, controllers: [String: ControllerLightbar] = [:]) {
        self.global = global
        self.controllers = controllers
    }

    /// The choice that applies to a device.
    ///
    /// - Parameter device: The device, if any.
    /// - Returns: Its override, the global choice, or ``ControllerLightbar/followGame`` for a device without
    ///   lights.
    public func policy(for device: ControllerDevice?) -> ControllerLightbar {
        guard let device, !device.isKeyboard, device.lights else {
            return .followGame
        }
        return controllers[device.preferenceKey] ?? global
    }

    /// The colour a device shows.
    ///
    /// - Parameters:
    ///   - device: The device.
    ///   - game: The colour the game set for it.
    /// - Returns: The colour, or `nil` to leave the device's default.
    public func color(for device: ControllerDevice?, game: UInt32?) -> UInt32? {
        policy(for: device).color(game: game)
    }
}

/// A named light bar colour offered in settings.
public struct ControllerLightbarSwatch: Equatable, Hashable, Sendable, Identifiable {
    /// The swatches offered, in order.
    public static let all: [Self] = [
        .init(name: .controlsLightbarBlue, rgb: 0x0050ff),
        .init(name: .controlsLightbarRed, rgb: 0xff2020),
        .init(name: .controlsLightbarGreen, rgb: 0x20d040),
        .init(name: .controlsLightbarPink, rgb: 0xff40a0),
        .init(name: .controlsLightbarPurple, rgb: 0x8a40ff),
        .init(name: .controlsLightbarOrange, rgb: 0xff8000),
        .init(name: .controlsLightbarCyan, rgb: 0x00d0e0),
        .init(name: .controlsLightbarWhite, rgb: 0xffffff),
        .init(name: .controlsLightbarOff, rgb: 0x000000)
    ]

    /// The colour's name.
    public let name: LocalizedStringResource

    /// The 24-bit RGB value.
    public let rgb: UInt32

    /// The swatch's identity, its colour.
    public var id: UInt32 {
        rgb
    }

    /// Hashes the swatch by its colour, since its name is not hashable.
    ///
    /// - Parameter hasher: The hasher to feed.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rgb)
    }
}
