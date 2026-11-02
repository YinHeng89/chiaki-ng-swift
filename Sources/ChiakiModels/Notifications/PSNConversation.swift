import Foundation

/// One message of a PSN conversation.
public struct PSNChatMessage: Equatable, Identifiable, Sendable {
    /// PSN's id of the message, or a local id for one still being sent.
    public let id: String

    /// The text, or `nil` for something that is not text, such as a sticker or a voice message.
    public let text: String?

    /// The sender's online id, or an empty string when PSN did not say.
    public let sender: String

    /// Whether the signed-in account sent it.
    public let fromUser: Bool

    /// When it was sent, or `nil` when PSN gave no time.
    public let sent: Date?

    /// Describes a message.
    ///
    /// - Parameters:
    ///   - id: PSN's id of the message.
    ///   - text: The text, or `nil` for a message without any.
    ///   - sender: The sender's online id.
    ///   - fromUser: Whether the account sent it.
    ///   - sent: When it was sent.
    public init(id: String, text: String?, sender: String, fromUser: Bool, sent: Date?) {
        self.id = id
        self.text = text
        self.sender = sender
        self.fromUser = fromUser
        self.sent = sent
    }
}

/// One of the account's PSN message conversations.
public struct PSNConversation: Equatable, Identifiable, Sendable {
    /// PSN's id of the conversation's group, which also identifies the conversation.
    public let id: String

    /// The thread its messages are read and sent in.
    public let threadID: String

    /// Whether it is a group rather than a direct conversation.
    public let isGroup: Bool

    /// The name a group was given, or an empty string.
    public let name: String

    /// The online ids of the other people in it.
    public let members: [String]

    /// The newest message, when PSN gave it.
    public let latest: PSNChatMessage?

    /// When it last changed, or `nil` when PSN gave no time.
    public let updated: Date?

    /// Whether it holds messages the account has not read.
    public let unread: Bool

    /// Describes a conversation.
    ///
    /// - Parameters:
    ///   - id: The group id.
    ///   - threadID: The thread id.
    ///   - isGroup: Whether it is a group.
    ///   - name: The group's name.
    ///   - members: The other people's online ids.
    ///   - latest: The newest message.
    ///   - updated: When it last changed.
    ///   - unread: Whether it holds unread messages.
    public init(
        id: String,
        threadID: String,
        isGroup: Bool = false,
        name: String = "",
        members: [String],
        latest: PSNChatMessage? = nil,
        updated: Date? = nil,
        unread: Bool = false
    ) {
        self.id = id
        self.threadID = threadID
        self.isGroup = isGroup
        self.name = name
        self.members = members
        self.latest = latest
        self.updated = updated
        self.unread = unread
    }

    /// What the conversation is called: the group's name, else the other people's online ids in natural wording.
    public var title: String {
        if !name.isEmpty {
            return name
        }
        let named = members.filter {
            !$0.isEmpty
        }
        guard !named.isEmpty else {
            return "Conversation"
        }
        return named.formatted(.list(type: .and))
    }
}

/// A run of a conversation's messages.
public struct PSNChatThread: Equatable, Sendable {
    /// The messages, oldest first.
    public let messages: [PSNChatMessage]

    /// Whether the run reaches the start of the conversation.
    public let complete: Bool

    /// Describes a run of messages.
    ///
    /// - Parameters:
    ///   - messages: The messages, oldest first.
    ///   - complete: Whether nothing older exists.
    public init(messages: [PSNChatMessage], complete: Bool) {
        self.messages = messages
        self.complete = complete
    }
}

/// Why PSN messages could not be read or sent.
public enum PSNMessagesFailure: Error, Equatable, Sendable {
    /// The account has no PSN sign-in.
    case signedOut
    /// PSN refused the account's credentials.
    case auth
    /// PSN rejected the request, or the text was empty or too long.
    case rejected
    /// PSN asked the app to slow down.
    case rateLimited
    /// PSN could not be reached or did not answer.
    case unavailable
    /// The request was cancelled.
    case cancelled
}
