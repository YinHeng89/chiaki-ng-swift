import Foundation

/// One of the player's PSN friends.
public struct PSNFriend: Equatable, Identifiable, Sendable {
    /// The friend's account id in decimal, which also identifies the friend.
    public let id: String
    /// The friend's online id, or an empty string when PSN did not give it.
    public var onlineID: String
    /// The friend's avatar, or `nil`.
    public var avatarURL: URL?
    /// Whether the friend is online now.
    public var online: Bool
    /// The game the friend is playing, or an empty string.
    public var playing: String

    /// Describes a friend.
    ///
    /// - Parameters:
    ///   - id: The account id.
    ///   - onlineID: The online id.
    ///   - avatarURL: The avatar.
    ///   - online: Whether the friend is online.
    ///   - playing: The game being played.
    public init(
        id: String,
        onlineID: String,
        avatarURL: URL? = nil,
        online: Bool = false,
        playing: String = ""
    ) {
        self.id = id
        self.onlineID = onlineID
        self.avatarURL = avatarURL
        self.online = online
        self.playing = playing
    }

    /// The name shown for the friend: the online id, or the account id when PSN gave no online id.
    public var name: String {
        onlineID.isEmpty
            ? id
            : onlineID
    }
}

/// A game session the player plays in, which friends can be invited to.
public struct OwnGameSession: Equatable, Sendable {
    /// The session manager's session id.
    public var id: String
    /// The session's name as the game set it, or an empty string.
    public var name: String
    /// The players in the session.
    public var players: Int
    /// The most players the session allows, or `0` when PSN did not say.
    public var maxPlayers: Int
    /// Whether anyone may join, the only kind a share link is offered for.
    public var openToAnyone: Bool

    /// Describes a session.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - name: The session's name.
    ///   - players: The players in it.
    ///   - maxPlayers: The most players allowed.
    ///   - openToAnyone: Whether anyone may join.
    public init(
        id: String,
        name: String = "",
        players: Int = 0,
        maxPlayers: Int = 0,
        openToAnyone: Bool = false
    ) {
        self.id = id
        self.name = name
        self.players = players
        self.maxPlayers = maxPlayers
        self.openToAnyone = openToAnyone
    }
}

/// A link friends can open to join the player's game session.
public struct SessionLink: Equatable, Sendable {
    /// The link.
    public var url: URL
    /// A picture of the link PSN made, such as a QR code, or `nil`.
    public var imageURL: URL?

    /// Describes a link.
    ///
    /// - Parameters:
    ///   - url: The link.
    ///   - imageURL: A picture of it.
    public init(url: URL, imageURL: URL? = nil) {
        self.url = url
        self.imageURL = imageURL
    }
}

/// The session or party friends are invited to.
public enum InvitationTarget: Equatable, Sendable {
    /// The game session with this id.
    case game(String)
    /// The party with this id.
    case party(String)
}
