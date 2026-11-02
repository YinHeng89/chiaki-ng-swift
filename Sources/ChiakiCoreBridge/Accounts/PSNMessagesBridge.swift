import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reads an account's PSN message conversations and sends text in them, through the open core.
///
/// Each call talks to PSN and blocks a core thread, so it runs on a dispatch queue while the calling task waits;
/// cancelling the task cancels the core request.
public struct PSNMessagesBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// The account's conversations, most recently changed first.
    ///
    /// - Parameter account: The account.
    /// - Returns: The conversations.
    /// - Throws: The `ChiakiModels/PSNMessagesFailure` that stopped the listing.
    public func conversations(account: AccountID) async throws(PSNMessagesFailure) -> [PSNConversation] {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.MessagesBridge.conversations(request, UsersBridge.vector(account))
            switch outcome.kind() {
            case .listed:
                return Result<[PSNConversation], PSNMessagesFailure>.success(
                    outcome.conversations().map(Self.conversation(of:))
                )
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// A conversation's newest messages, or the ones before a message.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - groupID: The conversation's group.
    ///   - threadID: The conversation's thread.
    ///   - before: The message to read before, or `nil` for the newest.
    /// - Returns: The messages, oldest first.
    /// - Throws: The `ChiakiModels/PSNMessagesFailure` that stopped the read.
    public func thread(
        account: AccountID,
        groupID: String,
        threadID: String,
        before: String?
    ) async throws(PSNMessagesFailure) -> PSNChatThread {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.MessagesBridge.thread(
                request,
                UsersBridge.vector(account),
                std.string(groupID),
                std.string(threadID),
                std.string(before ?? "")
            )
            switch outcome.kind() {
            case .read:
                let page = outcome.page()
                return Result<PSNChatThread, PSNMessagesFailure>.success(PSNChatThread(
                    messages: page.messages.map(Self.message(of:)),
                    complete: page.complete
                ))
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// Sends text in a conversation.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - groupID: The conversation's group.
    ///   - threadID: The conversation's thread.
    ///   - text: The text.
    /// - Returns: The message as sent.
    /// - Throws: The `ChiakiModels/PSNMessagesFailure` that stopped the send.
    public func send(
        account: AccountID,
        groupID: String,
        threadID: String,
        text: String
    ) async throws(PSNMessagesFailure) -> PSNChatMessage {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.MessagesBridge.send(
                request,
                UsersBridge.vector(account),
                std.string(groupID),
                std.string(threadID),
                std.string(text)
            )
            switch outcome.kind() {
            case .sent:
                return Result<PSNChatMessage, PSNMessagesFailure>.success(Self.message(of: outcome.message()))
            case .unanswered:
                return .failure(Self.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// Marks a conversation read up to a message.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - groupID: The conversation's group.
    ///   - threadID: The conversation's thread.
    ///   - messageID: The newest message shown.
    /// - Throws: The `ChiakiModels/PSNMessagesFailure` that stopped it.
    public func markRead(
        account: AccountID,
        groupID: String,
        threadID: String,
        messageID: String
    ) async throws(PSNMessagesFailure) {
        let result: Result<Void, PSNMessagesFailure> = await CoreCancellation.run(qos: .utility) { request in
            let refused = chiaki_bridge.MessagesBridge.mark_read(
                request,
                UsersBridge.vector(account),
                std.string(groupID),
                std.string(threadID),
                std.string(messageID)
            )
            if let unanswered = refused.value {
                return .failure(Self.failure(of: unanswered.reason))
            }
            return .success(())
        }
        try result.get()
    }

    /// The model conversation of the bridge's facts.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The conversation.
    static func conversation(of facts: chiaki_bridge.ConversationFacts) -> PSNConversation {
        PSNConversation(
            id: String(facts.group_id),
            threadID: String(facts.thread_id),
            isGroup: facts.group,
            name: String(facts.name),
            members: facts.member_names.map {
                String($0)
            },
            latest: facts.latest.value.map(message(of:)),
            updated: date(of: facts.updated_ms),
            unread: facts.unread
        )
    }

    /// The model message of the bridge's facts.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The message.
    static func message(of facts: chiaki_bridge.ChatMessageFacts) -> PSNChatMessage {
        PSNChatMessage(
            id: String(facts.id),
            text: facts.text
                ? String(facts.body)
                : nil,
            sender: String(facts.sender),
            fromUser: facts.from_user,
            sent: date(of: facts.sent_ms)
        )
    }

    /// The date of milliseconds since the epoch.
    ///
    /// - Parameter milliseconds: The time, or 0 for none.
    /// - Returns: The date, or `nil` for none.
    static func date(of milliseconds: Int64) -> Date? {
        milliseconds > 0
            ? Timestamp.date(milliseconds: milliseconds)
            : nil
    }

    /// The model failure of a request PSN did not answer.
    ///
    /// - Parameter reason: Why PSN did not answer.
    /// - Returns: The failure.
    static func failure(of reason: libchiaking.users.Unanswered.Reason) -> PSNMessagesFailure {
        switch reason {
        case .cancelled:
            .cancelled
        case .signed_out:
            .signedOut
        case .sign_in_expired, .store_access_lapsed, .remote_play_access_missing:
            .auth
        case .rejected:
            .rejected
        case .rate_limited:
            .rateLimited
        case .unavailable, .malformed, .old_service_refused:
            .unavailable
        }
    }
}
