import ChiakiModels
import Dependencies

/// Reads a profile's PSN message conversations and sends text in them.
///
/// The live value, in `ChiakiClientsLive`, asks PSN through the core; the test value refuses everything.
public struct PSNMessagesClient: Sendable {
    /// The profile's conversations, most recently changed first.
    public var conversations: @Sendable (_ profile: ProfileID) async throws(PSNMessagesFailure)
        -> [PSNConversation]

    /// A conversation's newest messages, or the ones before a message id when one is given.
    public var thread: @Sendable (
        _ profile: ProfileID,
        _ groupID: String,
        _ threadID: String,
        _ before: String?
    ) async throws(PSNMessagesFailure) -> PSNChatThread

    /// Sends text in a conversation and returns the message as sent.
    public var send: @Sendable (
        _ profile: ProfileID,
        _ groupID: String,
        _ threadID: String,
        _ text: String
    ) async throws(PSNMessagesFailure) -> PSNChatMessage

    /// Marks a conversation read up to a message.
    public var markRead: @Sendable (
        _ profile: ProfileID,
        _ groupID: String,
        _ threadID: String,
        _ messageID: String
    ) async throws(PSNMessagesFailure) -> Void

    /// Creates a client from its operations.
    ///
    /// - Parameters:
    ///   - conversations: Lists the profile's conversations.
    ///   - thread: Reads a conversation's messages.
    ///   - send: Sends text.
    ///   - markRead: Marks a conversation read.
    public init(
        conversations: @escaping @Sendable (ProfileID) async throws(PSNMessagesFailure) -> [PSNConversation],
        thread: @escaping @Sendable (ProfileID, String, String, String?) async throws(PSNMessagesFailure)
            -> PSNChatThread,
        send: @escaping @Sendable (ProfileID, String, String, String) async throws(PSNMessagesFailure)
            -> PSNChatMessage,
        markRead: @escaping @Sendable (ProfileID, String, String, String) async throws(PSNMessagesFailure)
            -> Void = { _, _, _, _ in
            }
    ) {
        self.conversations = conversations
        self.thread = thread
        self.send = send
        self.markRead = markRead
    }
}

extension PSNMessagesClient: TestDependencyKey {
    /// Refuses everything, so tests never reach PSN.
    public static let testValue = Self(
        conversations: { _ throws(PSNMessagesFailure) in
            throw .unavailable
        },
        thread: { _, _, _, _ throws(PSNMessagesFailure) in
            throw .unavailable
        },
        send: { _, _, _, _ throws(PSNMessagesFailure) in
            throw .unavailable
        }
    )
}

extension DependencyValues {
    /// Reads and sends PSN messages.
    public var psnMessages: PSNMessagesClient {
        get {
            self[PSNMessagesClient.self]
        }
        set {
            self[PSNMessagesClient.self] = newValue
        }
    }
}
