import Foundation

/// A player in a seat: where their input comes from and the account they joined with, if any.
public struct CouchPlayer: Equatable, Sendable {
    /// The local controller or remote guest the player uses.
    public let input: CouchInput
    /// The account the player joined with, if one was chosen.
    public let account: AccountProfile?
    /// Creates a player who uses a controller on this Mac.
    ///
    /// - Parameters:
    ///   - device: The controller.
    ///   - account: The account the player joins with, if any.
    public init(device: ControllerDevice, account: AccountProfile? = nil) {
        input = .local(device)
        self.account = account
    }

    /// Creates a player who uses a local controller or a remote guest's input.
    ///
    /// - Parameters:
    ///   - input: Where the player's input comes from.
    ///   - account: The account the player joins with, if any.
    public init(input: CouchInput, account: AccountProfile? = nil) {
        self.input = input
        self.account = account
    }

    /// The local controller, or `nil` for a remote guest.
    public var device: ControllerDevice? {
        input.device
    }

    /// The remote guest, or `nil` for a local controller.
    public var remote: CouchRemoteInput? {
        input.remote
    }
}

/// Where a seat's input comes from: a controller on this Mac or a remote guest.
public enum CouchInput: Equatable, Sendable {
    /// A controller on this Mac.
    case local(ControllerDevice)
    /// A remote play guest.
    case remote(CouchRemoteInput)

    /// The local controller, or `nil` for a remote guest.
    public var device: ControllerDevice? {
        if case .local(let device) = self {
            return device
        }
        return nil
    }

    /// The remote guest, or `nil` for a local controller.
    public var remote: CouchRemoteInput? {
        if case .remote(let remote) = self {
            return remote
        }
        return nil
    }
}

/// A remote play guest who plays through a seat on the console.
public struct CouchRemoteInput: Equatable, Sendable {
    /// The guest's identifier in the remote play session.
    public let guest: KakusanGuestID
    /// The guest's display name, if known.
    public let name: String?

    /// Creates a remote guest's input.
    ///
    /// - Parameters:
    ///   - guest: The guest's identifier.
    ///   - name: The guest's display name, if known.
    public init(guest: KakusanGuestID, name: String?) {
        self.guest = guest
        self.name = name
    }
}
