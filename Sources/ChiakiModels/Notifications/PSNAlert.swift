import Foundation

/// A message a friend sent the account, as PSN announces it.
///
/// PSN's announcement names the sender and the message group but carries no text, so an alert never shows what
/// the message says.
public struct PSNMessageAlert: Equatable, Hashable, Sendable {
    /// The sender's online id.
    public let sender: String

    /// The message group the message was sent in.
    public let groupID: String

    /// The thread it was sent in, which the conversation is read and answered in; empty when the push named none.
    public let threadID: String

    /// Describes a message alert.
    ///
    /// - Parameters:
    ///   - sender: The sender's online id.
    ///   - groupID: The message group.
    ///   - threadID: The thread it was sent in.
    public init(sender: String, groupID: String, threadID: String = "") {
        self.sender = sender
        self.groupID = groupID
        self.threadID = threadID
    }
}

/// An invitation to a friend's party, as PSN pushes it or the account's notifications list it.
///
/// Party invitations name no game; a PS5 joins the party with the party session.
public struct PSNPartyAlert: Equatable, Hashable, Sendable {
    /// The inviter's online id.
    public let sender: String

    /// The party session.
    public let sessionID: String

    /// The ids of the account's notifications that name the party, which clearing it deletes; empty for a party
    /// only pushed so far.
    public var notificationIDs: [String]

    /// Describes a party invitation.
    ///
    /// - Parameters:
    ///   - sender: The inviter's online id.
    ///   - sessionID: The party session.
    ///   - notificationIDs: The ids of the notifications that name the party.
    public init(sender: String, sessionID: String, notificationIDs: [String] = []) {
        self.sender = sender
        self.sessionID = sessionID
        self.notificationIDs = notificationIDs
    }
}

/// Something PSN told the account about as it happened: a game or party invitation, or a message.
public enum PSNAlert: Equatable, Sendable {
    /// A game invitation that was not listed before.
    case invitation(CloudGameInvitation)

    /// An invitation to a party.
    case party(PSNPartyAlert)

    /// A message someone else sent.
    case message(PSNMessageAlert)
}
