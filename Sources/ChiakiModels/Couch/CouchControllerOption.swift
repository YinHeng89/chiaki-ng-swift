import Foundation

/// A controller offered in a seat's controller picker, with who holds it now and whether it can be chosen.
public struct CouchControllerOption: Equatable, Sendable, Identifiable {
    /// The controller on offer.
    public let device: ControllerDevice
    /// Who holds the controller now, or `nil` when nobody does.
    public let holder: CouchHolder?
    /// Whether the controller can be taken for the seat without leaving another player without input.
    public let available: Bool

    /// Creates a controller option.
    ///
    /// - Parameters:
    ///   - device: The controller on offer.
    ///   - holder: Who holds the controller now, or `nil` when nobody does.
    ///   - available: Whether the controller can be taken for the seat.
    public init(device: ControllerDevice, holder: CouchHolder?, available: Bool) {
        self.device = device
        self.holder = holder
        self.available = available
    }

    /// The controller's identifier, which also identifies the option.
    public var id: UInt32 {
        device.id
    }
}

/// Who holds a controller now: player 1 or the player in one of the extra seats.
public enum CouchHolder: Equatable, Sendable {
    /// Player 1 holds the controller.
    case playerOne
    /// The player on this pad holds the controller.
    case seat(UInt8)
}

/// The answer to the question of who uses a controller that just connected.
public enum CouchNewControllerChoice: Equatable, Sendable {
    /// Give it to player 1, seat it as a new player, or leave it unused for now.
    case playerOne, newPlayer, notNow
}
