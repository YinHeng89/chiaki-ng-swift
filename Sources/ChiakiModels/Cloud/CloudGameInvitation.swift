import Foundation

/// An invitation to a game session or a party that a friend sent.
public struct CloudGameInvitation: Equatable, Identifiable, Sendable {
    /// What the invitation is to.
    public enum Kind: Equatable, Sendable {
        /// A game session, joined with the game.
        case game
        /// A party, which names no game and is joined on a PS5.
        case party
    }

    /// Whether the session can be joined now.
    public enum Joining: Equatable, Sendable {
        /// The session has room and the player is not in it.
        case joinable
        /// The player already plays in the session.
        case alreadyJoined
        /// The session has as many players as it allows.
        case full
        /// The session has ended or gives no way to join it.
        case cannotJoin
    }

    /// The session manager's id of the game session or party, which also identifies the invitation.
    public let id: String

    /// What the invitation is to.
    public let kind: Kind

    /// The invitation's own id, which a PS5 cloud stream joins it with, or an empty string when the
    /// notification did not carry one.
    public let invitationID: String

    /// The ids of the account's notifications that name this session, which clearing the invitation deletes.
    public let notificationIDs: [String]

    /// The online id of the friend who sent it, or an empty string when PSN did not say.
    public let inviter: String

    /// The session's name as the game set it, or an empty string.
    public let sessionName: String

    /// The games the session plays, such as `PPSA01234_00`.
    public let titleIDs: [String]

    /// When the invitation was last updated, or `nil` when PSN gave no time.
    public let sent: Date?

    /// Whether the player has not looked at it yet.
    public let unread: Bool

    /// The players in the session.
    public let players: Int

    /// The most players the session allows, or `0` when PSN did not say.
    public let maxPlayers: Int

    /// Whether it can be joined now.
    public let joining: Joining

    /// Describes an invitation.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - invitationID: The invitation's own id.
    ///   - notificationIDs: The ids of the notifications that name the session.
    ///   - inviter: The sender's online id.
    ///   - sessionName: The session's name.
    ///   - titleIDs: The games the session plays.
    ///   - sent: When it was last updated.
    ///   - unread: Whether it is unread.
    ///   - players: The players in the session.
    ///   - maxPlayers: The most players allowed.
    ///   - joining: Whether it can be joined now.
    ///   - kind: What the invitation is to.
    public init(
        id: String,
        invitationID: String = "",
        notificationIDs: [String] = [],
        inviter: String,
        sessionName: String,
        titleIDs: [String],
        sent: Date?,
        unread: Bool,
        players: Int,
        maxPlayers: Int,
        joining: Joining,
        kind: Kind = .game
    ) {
        self.id = id
        self.kind = kind
        self.invitationID = invitationID
        self.notificationIDs = notificationIDs
        self.inviter = inviter
        self.sessionName = sessionName
        self.titleIDs = titleIDs
        self.sent = sent
        self.unread = unread
        self.players = players
        self.maxPlayers = maxPlayers
        self.joining = joining
    }

    /// Whether the invitation is to the game a store product belongs to, matched by title number.
    ///
    /// - Parameter product: The product, such as `EP0000-PPSA01234_00-GAME000000000000`.
    /// - Returns: `true` when one of ``titleIDs`` has the product's title number.
    public func isFor(product: ProductID) -> Bool {
        let parts = product.rawValue.split(separator: "-")
        guard parts.count > 1, let number = Self.titleNumber(of: parts[1]) else {
            return false
        }
        return titleIDs.contains {
            Self.titleNumber(of: Substring($0)) == number
        }
    }

    private static func titleNumber(of titleID: Substring) -> Substring? {
        let number = titleID.prefix {
            $0 != "_"
        }
        guard !number.isEmpty else {
            return nil
        }
        return number
    }
}
