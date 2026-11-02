@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

private let chatProfile = ProfileID(uuid: UUID(3))

private func chatMessages() -> PSNMessagesClient {
    PSNMessagesClient(
        conversations: { _ throws(PSNMessagesFailure) in
            [
                PSNConversation(id: "g-1", threadID: "t-1", members: ["Friend"]),
                PSNConversation(id: "g-2", threadID: "t-2", members: ["Other"])
            ]
        },
        thread: { _, _, _, _ throws(PSNMessagesFailure) in
            PSNChatThread(
                messages: [
                    PSNChatMessage(id: "m-1", text: "hi", sender: "Friend", fromUser: false, sent: nil),
                    PSNChatMessage(id: "m-2", text: "hello", sender: "player", fromUser: true, sent: nil)
                ],
                complete: true
            )
        },
        send: { _, _, _, text throws(PSNMessagesFailure) in
            PSNChatMessage(id: "m-3", text: text, sender: "player", fromUser: true, sent: nil)
        }
    )
}

@MainActor private func chatPanel() -> StoreOf<PSNAlertsFeature> {
    var state = PSNAlertsFeature.State()
    state.watch = .watching(chatProfile, UUID(0))
    state.items = [
        PSNAlertsFeature.Item(
            id: "message:1",
            kind: .message(PSNMessageAlert(sender: "Friend", groupID: "g-1", threadID: "t-1")),
            arrived: Date(timeIntervalSince1970: 0)
        )
    ]
    let store = Store(initialState: state) {
        PSNAlertsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory()
        $0.platform.notificationPermission = {
            .allowed
        }
        $0.psnMessages = chatMessages()
    }
    store.send(.settings(.appeared))
    return store
}

@MainActor private func sendsFromTheReplyField(
    _ store: StoreOf<PSNAlertsFeature>,
    _ harness: MenuFocusHarness
) async {
    let count = {
        store.destination?.conversations?.conversation?.messages.count
    }
    await waitUntil(harness) {
        count() == 2
    }
    await harness.pause(300)
    store.send(.destination(.presented(.conversations(.conversation(.presented(.draftChanged("hey")))))))
    await harness.send(.down)
    await harness.send(.confirm)
    await waitUntil(harness) {
        count() == 3
    }
    #expect(count() == 3)
}

private final class ChatCloses: @unchecked Sendable {
    var count = 0
}

extension MenuFocusTests {
    @Test func replyOpensTheConversationOnItsFieldAndBackReturnsToReply() async {
        let store = chatPanel()
        let closes = ChatCloses()
        let harness = MenuFocusHarness(width: 600, height: 760) { _ in
            MenuFocusHostingView(rootView: PSNAlertsPanel(store: store) {
                closes.count += 1
            })
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(300)
        await harness.send(.down)
        await harness.send(.down)
        let reply = harness.focusedFrame
        await harness.send(.right)
        let mute = harness.focusedFrame
        #expect(mute.minX > reply.maxX)
        await harness.send(.left)
        #expect(harness.focusedFrame == reply)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination?.conversation?.messages.count == 2
        }
        await harness.pause(300)
        store.send(.destination(.presented(.conversation(.draftChanged("on my way")))))
        await harness.send(.down)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination?.conversation?.messages.count == 3
        }
        #expect(store.destination?.conversation?.messages.last?.text == "on my way")
        await harness.pause(300)
        for _ in 0..<4 {
            await harness.send(.up)
        }
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination == nil
        }
        #expect(store.destination == nil)
        await harness.pause(300)
        #expect(closes.count == 0)
        await harness.send(.right)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.alertSettings.isMuted("Friend")
        }
        #expect(store.alertSettings.isMuted("Friend"))
        await harness.send(.back)
        await waitUntil(harness) {
            closes.count == 1
        }
        #expect(closes.count == 1)
    }

    @Test func messagesListOpensAConversationAndBackStepsOutOneLevelAtATime() async {
        let store = chatPanel()
        let closes = ChatCloses()
        let harness = MenuFocusHarness(width: 600, height: 760) { _ in
            MenuFocusHostingView(rootView: PSNAlertsPanel(store: store) {
                closes.count += 1
            })
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(300)
        await harness.send(.down)
        let messagesRow = harness.focusedFrame
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination?.conversations?.conversations.count == 2
        }
        await harness.pause(300)
        await harness.send(.down)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination?.conversations?.conversation?.groupID == "g-2"
        }
        #expect(store.destination?.conversations?.conversation?.groupID == "g-2")
        await sendsFromTheReplyField(store, harness)
        await harness.send(.back)
        await waitUntil(harness) {
            store.destination?.conversations?.conversation == nil
        }
        await harness.pause(300)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination?.conversations?.conversation?.groupID == "g-2"
        }
        #expect(store.destination?.conversations?.conversation?.groupID == "g-2")
        await harness.pause(300)
        await harness.send(.back)
        await waitUntil(harness) {
            store.destination?.conversations?.conversation == nil
        }
        await harness.pause(300)
        await harness.send(.back)
        await waitUntil(harness) {
            store.destination == nil
        }
        await harness.pause(300)
        #expect(store.destination == nil)
        #expect(messagesRow != .zero)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.destination?.conversations != nil
        }
        #expect(store.destination?.conversations != nil)
        #expect(closes.count == 0)
    }
}

extension MenuFocusTests {
    @Test func aWindowThatClaimsInputReceivesCommandsUntilItReleasesThem() async {
        let harness = MenuFocusHarness(width: 200, height: 200) { _ in
            NSView()
        }
        defer {
            WindowFocus(harness.window).releaseInput()
            harness.close()
        }
        await harness.open()
        let before = WindowFocus.activeWindow
        WindowFocus(harness.window).claimInput()
        #expect(WindowFocus.activeWindow === harness.window)
        WindowFocus(harness.window).releaseInput()
        #expect(WindowFocus.activeWindow === before)
    }
}
