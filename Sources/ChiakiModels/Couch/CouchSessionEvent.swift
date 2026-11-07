import Foundation

/// Something that happened to couch seats or controllers during a stream.
public enum CouchSessionEvent: Equatable, Sendable {
    /// The console announced a seat for a pad.
    case announced(pad: UInt8)

    /// The console confirmed a pad's seat with its light colour.
    case confirmed(pad: UInt8, color: UInt32)

    /// A pad's join failed.
    case joinFailed(pad: UInt8, failure: CouchFailure)

    /// A pad's seat was dropped.
    case dropped(pad: UInt8)

    /// The console could not resolve a pad's account.
    case accountUnresolvable(pad: UInt8)

    /// The console asked for a pad's passcode, again when `retry` is set.
    case passcodeRequested(pad: UInt8, retry: Bool)

    /// A controller connected.
    case controllerConnected(ControllerDevice)

    /// A controller was claimed for a seat.
    case controllerClaimed(ControllerDevice)

    /// The controller with the given id was removed.
    case controllerRemoved(UInt32)

    /// Player 1's controller changed to the given id, or to none.
    case playerOneChanged(UInt32?)
}

/// An instruction for the stream, sent through the stream session client's couch commands.
public enum CouchCommand: Equatable, Sendable {
    /// Asks the console to add a player on a pad with this controller type and, on a PS5, this account.
    case join(pad: UInt8, controllerType: UInt8, accountID: Data?)
    /// Asks the console to remove the player on a pad.
    case remove(pad: UInt8)
    /// Sends a controller's input to a pad, or stops sending input to it for `nil`.
    case route(pad: UInt8, device: ControllerDevice?)
    /// Makes a controller player 1's input.
    case assignPlayerOne(ControllerDevice)
}

/// The controllers the stream's input can see, and which of them player 1 uses.
public struct CouchInventory: Equatable, Sendable {
    /// Every controller connected to the stream's input.
    public var controllers: [ControllerDevice]
    /// The controller player 1 uses, or `nil` when player 1 uses the keyboard.
    public var playerOne: ControllerDevice?
    /// The controllers players 2 to 4 chose in the controls settings, by preference key and keyed by pad.
    public var chosenControllers: [UInt8: String]
    /// Creates an inventory.
    ///
    /// - Parameters:
    ///   - controllers: Every connected controller.
    ///   - playerOne: The controller player 1 uses, or `nil` for the keyboard.
    ///   - chosenControllers: The controllers players 2 to 4 chose, by preference key and keyed by pad.
    public init(
        controllers: [ControllerDevice] = [],
        playerOne: ControllerDevice? = nil,
        chosenControllers: [UInt8: String] = [:]
    ) {
        self.controllers = controllers
        self.playerOne = playerOne
        self.chosenControllers = chosenControllers
    }
}

/// The light bar choices and player 1's colour shared with couch guests, with a revision for ordering.
public struct CouchLights: Equatable, Sendable {
    /// The light bar choices.
    public var lightbars: ControllerLightbars

    /// Player 1's colour.
    public var playerOne: UInt32?

    /// Increases with every change, so an older update is ignored.
    public var revision: UInt64

    /// Creates the shared lights.
    ///
    /// - Parameters:
    ///   - lightbars: The light bar choices.
    ///   - playerOne: Player 1's colour.
    ///   - revision: The revision.
    public init(
        lightbars: ControllerLightbars = ControllerLightbars(),
        playerOne: UInt32? = nil,
        revision: UInt64 = 0
    ) {
        self.lightbars = lightbars
        self.playerOne = playerOne
        self.revision = revision
    }
}
