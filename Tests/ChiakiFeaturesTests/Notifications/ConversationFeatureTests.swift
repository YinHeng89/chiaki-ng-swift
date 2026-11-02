import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let profile = ProfileID(uuid: UUID(100))

private func message(_ id: String, _ seconds: Double, fromUser: Bool = false, text: String? = "hi")
    -> PSNChatMessage {
    PSNChatMessage(
        id: id,
        text: text,
        sender: fromUser
            ? "player"
            : "Friend",
        fromUser: fromUser,
        sent: Date(timeIntervalSince1970: seconds)
    )
}

private final class Calls: Sendable {
    let reads = LockIsolated<[String?]>([])
    let sent = LockIsolated<[String]>([])
    let marked = LockIsolated<[String]>([])
}

@MainActor private func conversationStore(
    calls: Calls,
    newest: PSNChatThread = PSNChatThread(messages: [message("m-1", 1), message("m-2", 2)], complete: false),
    older: PSNChatThread = PSNChatThread(messages: [message("m-0", 0)], complete: true),
    sendFailure: PSNMessagesFailure? = nil
) -> TestStoreOf<ConversationFeature> {
    let store = TestStore(initialState: ConversationFeature.State(
        profile: profile,
        groupID: "g-1",
        threadID: "t-1",
        title: "Friend"
    )) {
        ConversationFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnMessages = PSNMessagesClient(
            conversations: { _ throws(PSNMessagesFailure) in
                []
            },
            thread: { _, _, _, before throws(PSNMessagesFailure) in
                calls.reads.withValue {
                    $0.append(before)
                }
                return before == nil
                    ? newest
                    : older
            },
            send: { _, _, _, text throws(PSNMessagesFailure) in
                if let sendFailure {
                    throw sendFailure
                }
                calls.sent.withValue {
                    $0.append(text)
                }
                return message("m-9", 9, fromUser: true, text: text)
            },
            markRead: { _, _, _, id throws(PSNMessagesFailure) in
                calls.marked.withValue {
                    $0.append(id)
                }
            }
        )
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func aConversationReadsItsNewestMessagesAndMarksThemRead() async {
    let calls = Calls()
    let store = conversationStore(calls: calls)
    await store.send(.appeared)
    await store.receive(\.read)
    #expect(store.state.reading == .loaded)
    #expect(store.state.messages.map(\.id) == ["m-1", "m-2"])
    #expect(!store.state.complete)
    #expect(ConversationView.showsOlder(store.state))
    await store.finish()
    #expect(calls.marked.value == ["m-2"])
    await store.send(.appeared)
    #expect(calls.reads.value == [nil])
}

@MainActor @Test func earlierMessagesArePrependedUntilTheStart() async {
    let calls = Calls()
    let store = conversationStore(calls: calls)
    await store.send(.appeared)
    await store.receive(\.read)
    await store.send(.loadOlder)
    await store.receive(\.olderRead)
    #expect(store.state.messages.map(\.id) == ["m-0", "m-1", "m-2"])
    #expect(store.state.complete)
    #expect(!ConversationView.showsOlder(store.state))
    await store.send(.loadOlder)
    #expect(calls.reads.value == [nil, "m-1"])
}

@MainActor @Test func aReplyIsSentOnceAndAddedToTheConversation() async {
    let calls = Calls()
    let store = conversationStore(calls: calls)
    await store.send(.appeared)
    await store.receive(\.read)
    await store.send(.send)
    #expect(store.state.sending == .idle)
    await store.send(.draftChanged("  see you soon "))
    #expect(store.state.canSend)
    await store.send(.send)
    #expect(!store.state.canSend)
    await store.receive(\.sent)
    #expect(calls.sent.value == ["see you soon"])
    #expect(store.state.draft.isEmpty)
    #expect(store.state.messages.last?.id == "m-9")
    await store.send(.draftChanged(String(repeating: "a", count: ConversationFeature.longestText + 1)))
    #expect(!store.state.canSend)
    await store.send(.draftChanged(String(repeating: "あ", count: ConversationFeature.longestText)))
    #expect(store.state.canSend)
    await store.send(.draftChanged(String(repeating: "😀", count: ConversationFeature.longestText / 2 + 1)))
    #expect(!store.state.canSend)
}

@MainActor @Test func aFailedReplyKeepsTheDraftAndSaysWhy() async {
    let calls = Calls()
    let store = conversationStore(calls: calls, sendFailure: .rejected)
    await store.send(.draftChanged("hello"))
    await store.send(.send)
    await store.receive(\.sent)
    #expect(store.state.sending == .failed(.rejected))
    #expect(store.state.draft == "hello")
    #expect(ConversationView.sendFailure(.rejected) == "PlayStation Network didn't accept this message.")
    await store.send(.draftChanged("hello again"))
    #expect(store.state.sending == .idle)
}

@MainActor @Test func aStaleReadIsIgnored() async {
    let calls = Calls()
    let store = conversationStore(calls: calls)
    await store.send(.read(UUID(42), .success(PSNChatThread(messages: [message("x", 1)], complete: true))))
    #expect(store.state.messages.isEmpty)
    #expect(store.state.reading == .idle)
}

@MainActor @Test func theListOpensAConversationInPlace() async {
    let listed = [
        PSNConversation(id: "g-1", threadID: "t-1", members: ["Friend", "Other"], unread: true),
        PSNConversation(id: "g-2", threadID: "", members: ["Nobody"])
    ]
    let store = TestStore(initialState: ConversationsFeature.State(profile: profile)) {
        ConversationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnMessages.conversations = { _ throws(PSNMessagesFailure) in
            listed
        }
    }
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.receive(\.listed)
    #expect(store.state.conversations == listed)
    #expect(listed[0].title == "Friend and Other")
    #expect(ConversationsView.rows(for: listed).count == 3)
    await store.send(.open("g-2"))
    #expect(store.state.conversation == nil)
    await store.send(.open("g-1"))
    #expect(store.state.conversation?.threadID == "t-1")
    #expect(store.state.conversation?.title == "Friend and Other")
    await store.send(.conversation(.dismiss))
    #expect(store.state.conversation == nil)
}

@MainActor @Test func textTypedWhileSendingIsKept() async {
    let clock = TestClock()
    let calls = Calls()
    let store = conversationStore(calls: calls)
    store.dependencies.psnMessages.send = { _, _, _, text throws(PSNMessagesFailure) in
        try? await clock.sleep(for: .seconds(1))
        return message("m-9", 9, fromUser: true, text: text)
    }
    await store.send(.draftChanged("first"))
    await store.send(.send)
    await store.send(.draftChanged("second"))
    await clock.advance(by: .seconds(1))
    await store.receive(\.sent)
    #expect(store.state.draft == "second")
    #expect(store.state.messages.last?.text == "first")
}

@MainActor @Test func aFailedReadMarkerIsTriedAgainOnTheNextRead() async {
    let calls = Calls()
    let failing = LockIsolated(true)
    let store = conversationStore(calls: calls)
    store.dependencies.psnMessages.markRead = { _, _, _, id throws(PSNMessagesFailure) in
        if failing.value {
            throw .unavailable
        }
        calls.marked.withValue {
            $0.append(id)
        }
    }
    await store.send(.appeared)
    await store.receive(\.read)
    await store.finish()
    #expect(store.state.markedRead == nil)
    failing.setValue(false)
    await store.send(.refresh)
    await store.receive(\.read)
    await store.receive(\.marked)
    #expect(store.state.markedRead == "m-2")
    #expect(calls.marked.value == ["m-2"])
}

@MainActor @Test func aGroupConversationIsNamedAfterItsWriters() async {
    let calls = Calls()
    let store = conversationStore(calls: calls, newest: PSNChatThread(messages: [
        PSNChatMessage(
            id: "a",
            text: "hi",
            sender: "Alice",
            fromUser: false,
            sent: Date(timeIntervalSince1970: 1)
        ),
        PSNChatMessage(
            id: "b",
            text: "yo",
            sender: "Bob",
            fromUser: false,
            sent: Date(timeIntervalSince1970: 2)
        )
    ], complete: true))
    await store.send(.appeared)
    await store.receive(\.read)
    #expect(store.state.title == "Alice and Bob")
}

@MainActor @Test func closingAConversationReadsTheListAgain() async {
    let listings = LockIsolated(0)
    let store = TestStore(initialState: ConversationsFeature.State(profile: profile)) {
        ConversationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnMessages.conversations = { _ throws(PSNMessagesFailure) in
            listings.withValue {
                $0 += 1
            }
            return [PSNConversation(id: "g-1", threadID: "t-1", members: ["Friend"])]
        }
    }
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.receive(\.listed)
    await store.send(.open("g-1"))
    await store.send(.conversation(.dismiss))
    await store.receive(\.listed)
    #expect(listings.value == 2)
}
