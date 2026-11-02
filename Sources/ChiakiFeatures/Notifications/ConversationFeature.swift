import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Owns one PSN conversation shown in the Notifications panel: its messages, older pages, the reply being
/// written and sending it.
///
/// Reading, reading older messages and sending each move through their own state machine, and every completion
/// carries the operation that started it, so an answer to an older request never lands. Once messages are shown
/// the conversation is marked read up to the newest one someone else sent.
@Reducer public struct ConversationFeature {
    /// Where reading the newest messages stands.
    public enum Reading: Equatable, Sendable {
        /// Nothing has been asked yet.
        case idle
        /// The operation with this id is reading.
        case loading(UUID)
        /// The newest messages are shown.
        case loaded
        /// The last read failed.
        case failed(PSNMessagesFailure)
    }

    /// Where reading older messages stands.
    public enum Older: Equatable, Sendable {
        /// Nothing older is being read.
        case idle
        /// The operation with this id is reading the messages before the oldest shown.
        case loading(UUID)
        /// The last read of older messages failed.
        case failed(PSNMessagesFailure)
    }

    /// Where sending the reply stands.
    public enum Sending: Equatable, Sendable {
        /// Nothing is being sent.
        case idle
        /// The operation with this id is sending this text.
        case sending(UUID, String)
        /// The last send failed; the draft still holds its text.
        case failed(PSNMessagesFailure)
    }

    /// The conversation's state.
    @ObservableState public struct State: Equatable {
        /// The profile whose conversation it is.
        public let profile: ProfileID
        /// The conversation's group.
        public let groupID: String
        /// The conversation's thread.
        public let threadID: String
        /// What the conversation is called: the name it was opened with, or the people who wrote in it once
        /// more than one other person has.
        public var title: String
        /// Where reading the newest messages stands.
        public var reading = Reading.idle
        /// Where reading older messages stands.
        public var older = Older.idle
        /// Where sending the reply stands.
        public var sending = Sending.idle
        /// The messages shown, oldest first.
        public var messages: [PSNChatMessage] = []
        /// Whether the messages reach the start of the conversation.
        public var complete = false
        /// The reply being written.
        public var draft = ""
        /// The newest message PSN accepted the conversation as read up to.
        public var markedRead: String?

        /// Creates the state for a conversation.
        ///
        /// - Parameters:
        ///   - profile: The profile whose conversation it is.
        ///   - groupID: The conversation's group.
        ///   - threadID: The conversation's thread.
        ///   - title: What the conversation is called.
        public init(profile: ProfileID, groupID: String, threadID: String, title: String) {
            self.profile = profile
            self.groupID = groupID
            self.threadID = threadID
            self.title = title
        }

        /// Whether the draft can be sent: it holds text, within the core's limit, and nothing is being sent.
        public var canSend: Bool {
            if case .sending = sending {
                return false
            }
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text.utf16.count <= ConversationFeature.longestText
        }
    }

    /// Events the conversation handles.
    public enum Action: Equatable, Sendable {
        /// The conversation appeared, so its messages are read when they have not been yet.
        case appeared
        /// The person asked for the newest messages again, or a new message arrived.
        case refresh
        /// PSN answered the read started by an operation.
        case read(UUID, Result<PSNChatThread, PSNMessagesFailure>)
        /// The person asked for the messages before the oldest shown.
        case loadOlder
        /// PSN answered the older read started by an operation.
        case olderRead(UUID, Result<PSNChatThread, PSNMessagesFailure>)
        /// The person changed the reply.
        case draftChanged(String)
        /// The person sent the reply.
        case send
        /// PSN answered the send started by an operation.
        case sent(UUID, Result<PSNChatMessage, PSNMessagesFailure>)
        /// PSN accepted the conversation as read up to a message.
        case marked(String)
    }

    /// Cancellation identifiers for the conversation's requests.
    public enum CancelID: Hashable, Sendable {
        /// The latest read of the newest messages.
        case reading
        /// The latest read of older messages.
        case older
        /// The latest send.
        case sending
        /// The latest read marker.
        case marking
    }

    /// The longest reply sent, in UTF-16 code units, as PSN and the core measure it.
    public static let longestText = 512

    @Dependency(\.psnMessages) private var client
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard state.reading == .idle else {
                    return .none
                }
                return read(&state)
            case .refresh:
                return read(&state)
            case let .read(operation, result):
                guard case .loading(operation) = state.reading else {
                    return .none
                }
                switch result {
                case .success(let thread):
                    state.reading = .loaded
                    merge(thread.messages, into: &state)
                    if state.messages.count == thread.messages.count {
                        state.complete = thread.complete
                    }
                    retitle(&state)
                    return markRead(state)
                case .failure(let failure):
                    state.reading = .failed(failure)
                    return .none
                }
            case .loadOlder:
                return loadOlder(&state)
            case let .olderRead(operation, result):
                guard case .loading(operation) = state.older else {
                    return .none
                }
                switch result {
                case .success(let thread):
                    state.older = .idle
                    merge(thread.messages, into: &state)
                    state.complete = thread.complete || thread.messages.isEmpty
                case .failure(let failure):
                    state.older = .failed(failure)
                }
                return .none
            case .draftChanged(let text):
                state.draft = text
                if case .failed = state.sending {
                    state.sending = .idle
                }
                return .none
            case .send:
                return send(&state)
            case let .sent(operation, result):
                guard case .sending(operation, let text) = state.sending else {
                    return .none
                }
                switch result {
                case .success(let message):
                    state.sending = .idle
                    if state.draft.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                        state.draft = ""
                    }
                    merge([message], into: &state)
                case .failure(let failure):
                    state.sending = .failed(failure)
                }
                return .none
            case .marked(let id):
                state.markedRead = id
                return .none
            }
        }
    }

    private func read(_ state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.reading = .loading(operation)
        let (profile, group, thread) = (state.profile, state.groupID, state.threadID)
        return .run { [client] send in
            do throws(PSNMessagesFailure) {
                let read = try await client.thread(profile, group, thread, nil)
                await send(.read(operation, .success(read)))
            } catch {
                await send(.read(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.reading, cancelInFlight: true)
    }

    private func loadOlder(_ state: inout State) -> Effect<Action> {
        guard !state.complete, let oldest = state.messages.first?.id else {
            return .none
        }
        if case .loading = state.older {
            return .none
        }
        let operation = uuid()
        state.older = .loading(operation)
        let (profile, group, thread) = (state.profile, state.groupID, state.threadID)
        return .run { [client] send in
            do throws(PSNMessagesFailure) {
                let read = try await client.thread(profile, group, thread, oldest)
                await send(.olderRead(operation, .success(read)))
            } catch {
                await send(.olderRead(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.older, cancelInFlight: true)
    }

    private func send(_ state: inout State) -> Effect<Action> {
        guard state.canSend else {
            return .none
        }
        let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let operation = uuid()
        state.sending = .sending(operation, text)
        let (profile, group, thread) = (state.profile, state.groupID, state.threadID)
        return .run { [client] send in
            do throws(PSNMessagesFailure) {
                let sent = try await client.send(profile, group, thread, text)
                await send(.sent(operation, .success(sent)))
            } catch {
                await send(.sent(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.sending, cancelInFlight: true)
    }

    private func markRead(_ state: State) -> Effect<Action> {
        guard let newest = state.messages.last(where: { !$0.fromUser }), newest.id != state.markedRead else {
            return .none
        }
        let (profile, group, thread) = (state.profile, state.groupID, state.threadID)
        return .run { [client] send in
            do throws(PSNMessagesFailure) {
                try await client.markRead(profile, group, thread, newest.id)
                await send(.marked(newest.id))
            } catch {
                return
            }
        }
        .cancellable(id: CancelID.marking, cancelInFlight: true)
    }

    private func retitle(_ state: inout State) {
        var others: [String] = []
        for message in state.messages where !message.fromUser && !message.sender.isEmpty {
            if !others.contains(message.sender) {
                others.append(message.sender)
            }
        }
        if others.count > 1 {
            state.title = others.formatted(.list(type: .and))
        }
    }

    private func merge(_ messages: [PSNChatMessage], into state: inout State) {
        var byID = Dictionary(state.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in
            first
        })
        for message in messages {
            byID[message.id] = message
        }
        state.messages = byID.values.sorted { left, right in
            (left.sent ?? .distantPast, left.id) < (right.sent ?? .distantPast, right.id)
        }
    }
}
