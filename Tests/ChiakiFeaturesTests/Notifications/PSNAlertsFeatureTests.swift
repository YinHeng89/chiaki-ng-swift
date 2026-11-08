import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let profile = ProfileID(uuid: UUID(100))
private let now = Date(timeIntervalSince1970: 2_000_000)

private func invitation(_ id: String, from inviter: String = "Friend",
                        unread: Bool = true) -> CloudGameInvitation {
    CloudGameInvitation(
        id: id,
        invitationID: "invite-\(id)",
        notificationIDs: ["n-\(id)"],
        inviter: inviter,
        sessionName: "Lobby",
        titleIDs: ["PPSA01234_00"],
        sent: now,
        unread: unread,
        players: 1,
        maxPlayers: 4,
        joining: .joinable
    )
}

private final class Pushes: Sendable {
    let stream: AsyncStream<PSNAlert>
    let continuation: AsyncStream<PSNAlert>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }
}

private final class Posted: Sendable {
    let titles = LockIsolated<[String]>([])
}

@MainActor private func store(
    pushes: Pushes,
    posted: Posted,
    listed: [CloudGameInvitation] = [],
    clock: some Clock<Duration> = ImmediateClock(),
    dismissed: LockIsolated<[String]> = LockIsolated([]),
    parties: LockIsolated<[String]> = LockIsolated([]),
    partyFailure: CloudInvitationFailure? = nil
) -> TestStoreOf<PSNAlertsFeature> {
    let store = TestStore(initialState: PSNAlertsFeature.State()) {
        PSNAlertsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.date.now = now
        $0.continuousClock = clock
        $0.settings = .inMemory()
        $0.platform.notificationPermission = {
            .allowed
        }
        $0.streamSession.invitations = { _ throws(CloudInvitationFailure) in
            listed
        }
        $0.streamSession.joinParty = { _, session, console throws(CloudInvitationFailure) in
            parties.withValue {
                $0.append("\(session) on \(console.hex)")
            }
            if let partyFailure {
                throw partyFailure
            }
        }
        $0.streamSession.dismissNotifications = { _, ids throws(CloudInvitationFailure) in
            dismissed.withValue {
                $0.append(contentsOf: ids)
            }
        }
        $0.streamSession.psnAlerts = { _ in
            pushes.stream
        }
        $0.platform.postNotification = { _, title, _ in
            posted.titles.withValue {
                $0.append(title)
            }
        }
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func anArrivingInvitationIsListedCountedAndAlerted() async {
    let pushes = Pushes()
    let posted = Posted()
    let store = store(pushes: pushes, posted: posted)
    await store.send(.watch(profile))
    #expect(store.state.watch == .watching(profile, UUID(0)))
    pushes.continuation.yield(.invitation(invitation("s-1")))
    await store.receive(\.arrived)
    await store.receive(\.delegate)
    #expect(store.state.items.map(\.id) == ["invitation:s-1"])
    #expect(store.state.unseen == 1)
    pushes.continuation.yield(.message(PSNMessageAlert(sender: "Other", groupID: "g-1")))
    await store.receive(\.arrived)
    await store.receive(\.delegate)
    #expect(store.state.items.count == 2)
    #expect(store.state.unseen == 2)
    await store.send(.watch(nil))
    #expect(store.state.watch == .off)
    #expect(store.state.items.isEmpty)
    #expect(posted.titles.value == ["Friend invited you to play", "Other sent you a message"])
}

@MainActor @Test func aPartyInvitationIsListedAndAlertedOnce() async {
    let pushes = Pushes()
    let posted = Posted()
    let store = store(pushes: pushes, posted: posted)
    await store.send(.watch(profile))
    let party = PSNPartyAlert(sender: "Host", sessionID: "p-1")
    pushes.continuation.yield(.party(party))
    await store.receive(\.arrived)
    await store.receive(\.delegate)
    pushes.continuation.yield(.party(party))
    await store.receive(\.arrived)
    #expect(store.state.items.map(\.id) == ["party:p-1"])
    #expect(store.state.items.first?.isInvitation == true)
    #expect(store.state.unseen == 1)
    #expect(posted.titles.value == ["Host invited you to a party"])
    await store.send(.setInvitations(false))
    await store.skipReceivedActions()
    pushes.continuation.yield(.party(PSNPartyAlert(sender: "Other", sessionID: "p-2")))
    await store.receive(\.arrived)
    #expect(store.state.items.count == 2)
    #expect(posted.titles.value == ["Host invited you to a party"])
    await store.send(.watch(nil))
}

@MainActor @Test func aSendersRepeatedInvitationsCollapseIntoOneEntryWithoutAnotherAlert() async {
    let pushes = Pushes()
    let posted = Posted()
    let store = store(pushes: pushes, posted: posted)
    await store.send(.watch(profile))
    for session in ["s-1", "s-2", "s-3"] {
        pushes.continuation.yield(.invitation(invitation(session, from: "Spammer")))
        await store.receive(\.arrived)
    }
    #expect(store.state.items.count == 1)
    #expect(store.state.items.first?.id == "invitation:s-3")
    #expect(store.state.items.first?.repeats == 3)
    #expect(store.state.unseen == 3)
    #expect(posted.titles.value.count == 1)
    await store.send(.watch(nil))
}

@MainActor @Test func aStaleWatchCannotAddEntries() async {
    let pushes = Pushes()
    let store = store(pushes: pushes, posted: Posted())
    await store.send(.watch(profile))
    await store.send(.arrived(UUID(99), .invitation(invitation("s-1"))))
    #expect(store.state.items.isEmpty)
    await store.send(.watch(nil))
}

@MainActor @Test func openingThePanelClearsTheCountAndListsInvitationsThePushMissed() async {
    let pushes = Pushes()
    let store = store(
        pushes: pushes,
        posted: Posted(),
        listed: [invitation("ps4-np-session", from: "OldFriend"), invitation("s-1")]
    )
    await store.send(.watch(profile))
    pushes.continuation.yield(.invitation(invitation("s-1")))
    await store.receive(\.arrived)
    await store.send(.opened) {
        $0.unseen = 0
        $0.panel = .open
    }
    await store.receive(\.refresh)
    await store.receive(\.listed)
    #expect(Set(store.state.items.map(\.id)) == ["invitation:s-1", "invitation:ps4-np-session"])
    pushes.continuation.yield(.message(PSNMessageAlert(sender: "Other", groupID: "g-1")))
    await store.receive(\.arrived)
    #expect(store.state.unseen == 0)
    await store.send(.closed)
    pushes.continuation.yield(.message(PSNMessageAlert(sender: "Third", groupID: "g-2")))
    await store.receive(\.arrived)
    #expect(store.state.unseen == 1)
    await store.send(.watch(nil))
}

@MainActor @Test func mutingASenderStoresIt() async {
    let store = store(pushes: Pushes(), posted: Posted())
    await store.send(.settings(.appeared))
    await store.skipReceivedActions()
    await store.send(.setMuted("Pest", true))
    await store.skipReceivedActions()
    #expect(store.state.alertSettings.isMuted("Pest"))
    await store.send(.setInvitations(false))
    await store.skipReceivedActions()
    #expect(store.state.alertSettings.invitations == false)
}

@MainActor @Test func heldBackMessagesAlertOnceTheSendersWindowEnds() async {
    let pushes = Pushes()
    let posted = Posted()
    let clock = TestClock()
    let store = store(pushes: pushes, posted: posted, clock: clock)
    await store.send(.watch(profile))
    for _ in 0..<3 {
        pushes.continuation.yield(.message(PSNMessageAlert(sender: "Chatty", groupID: "g-1")))
        await store.receive(\.arrived)
    }
    #expect(store.state.unseen == 3)
    #expect(store.state.heldMessages == ["Chatty": 2])
    #expect(posted.titles.value == ["Chatty sent you a message"])
    await clock.advance(by: PSNAlertGate.messageWindow)
    await store.receive(\.messageWindowEnded)
    await store.receive(\.delegate)
    #expect(store.state.heldMessages.isEmpty)
    #expect(posted.titles.value == ["Chatty sent you a message", "Chatty sent you 3 messages"])
    await store.send(.watch(nil))
}

@MainActor @Test func openingThePanelCancelsTheCatchUpAlert() async {
    let pushes = Pushes()
    let posted = Posted()
    let clock = TestClock()
    let store = store(pushes: pushes, posted: posted, clock: clock)
    await store.send(.watch(profile))
    for _ in 0..<2 {
        pushes.continuation.yield(.message(PSNMessageAlert(sender: "Chatty", groupID: "g-1")))
        await store.receive(\.arrived)
    }
    await store.send(.opened)
    #expect(store.state.heldMessages.isEmpty)
    await clock.advance(by: PSNAlertGate.messageWindow)
    #expect(posted.titles.value == ["Chatty sent you a message"])
    await store.send(.watch(nil))
}

@MainActor @Test func clearingTheListDeletesItsInvitationsNotifications() async {
    let pushes = Pushes()
    let dismissed = LockIsolated<[String]>([])
    let store = store(pushes: pushes, posted: Posted(), dismissed: dismissed)
    await store.send(.watch(profile))
    pushes.continuation.yield(.invitation(invitation("s-1")))
    await store.receive(\.arrived)
    pushes.continuation.yield(.message(PSNMessageAlert(sender: "Other", groupID: "g-1")))
    await store.receive(\.arrived)
    await store.send(.clearAll)
    #expect(store.state.items.isEmpty)
    #expect(store.state.unseen == 0)
    await store.receive(\.cleared)
    #expect(store.state.clearing == .idle)
    #expect(dismissed.value == ["n-s-1"])
    await store.send(.watch(nil))
}

@MainActor @Test func signingInAgainMovesThatAccountsWatchToTheNextGeneration() async {
    let store = store(pushes: Pushes(), posted: Posted())
    await store.send(.watch(profile))
    let first = store.state.watch
    await store.send(.restart(ProfileID(uuid: UUID(7))))
    #expect(store.state.watch == first)
    #expect(store.state.generation == 0)
    await store.send(.restart(profile))
    #expect(store.state.generation == 1)
    #expect(store.state.watch == .ended(profile))
    await store.send(.watch(profile))
    #expect(store.state.watch != first)
    #expect(store.state.watch.profile == profile)
    await store.send(.watch(nil))
}

@MainActor @Test func openingThePanelChecksWhetherMacOSShowsAlerts() async {
    let store = store(pushes: Pushes(), posted: Posted())
    store.dependencies.platform.notificationPermission = {
        .denied
    }
    await store.send(.watch(profile))
    await store.send(.opened)
    await store.receive(\.systemAlertsChecked)
    #expect(store.state.systemAlerts == .denied)
    #expect(PSNAlertsPanel.systemAlertsNote(.denied) != nil)
    #expect(PSNAlertsPanel.systemAlertsNote(.allowed) == nil)
    await store.send(.watch(nil))
}

@MainActor @Test func anEndedWatchMovesToTheNextGenerationAfterAPause() async {
    let pushes = Pushes()
    let clock = TestClock()
    let store = store(pushes: pushes, posted: Posted(), clock: clock)
    await store.send(.watch(profile))
    pushes.continuation.finish()
    await store.receive(\.watchEnded)
    #expect(store.state.watch == .ended(profile))
    await clock.advance(by: PSNAlertsFeature.rewatchPause)
    await store.receive(\.restart)
    #expect(store.state.generation == 1)
    await store.send(.watch(nil))
}

private func party(_ id: String, from inviter: String = "Host") -> CloudGameInvitation {
    CloudGameInvitation(
        id: id,
        notificationIDs: ["n-\(id)"],
        inviter: inviter,
        sessionName: "",
        titleIDs: [],
        sent: now,
        unread: true,
        players: 0,
        maxPlayers: 0,
        joining: .joinable,
        kind: .party
    )
}

private let den = HardwareID(hex: "0123456789AB")!

@MainActor @Test func aListedPartyJoinsItsPushedEntryAndIsCleared() async {
    let pushes = Pushes()
    let dismissed = LockIsolated<[String]>([])
    let store = store(
        pushes: pushes,
        posted: Posted(),
        listed: [party("p-1"), party("p-2", from: "Other")],
        dismissed: dismissed
    )
    await store.send(.watch(profile))
    pushes.continuation.yield(.party(PSNPartyAlert(sender: "Host", sessionID: "p-1")))
    await store.receive(\.arrived)
    await store.send(.opened)
    await store.receive(\.refresh)
    await store.receive(\.listed)
    #expect(Set(store.state.items.map(\.id)) == ["party:p-1", "party:p-2"])
    let ids = store.state.items.flatMap { item -> [String] in
        guard case .party(let party) = item.kind else {
            return []
        }
        return party.notificationIDs
    }
    #expect(Set(ids) == ["n-p-1", "n-p-2"])
    await store.send(.clearAll)
    await store.receive(\.cleared)
    #expect(Set(dismissed.value) == ["n-p-1", "n-p-2"])
    await store.send(.watch(nil))
}

@MainActor @Test func aHomePS5JoinsAPartyAndAStaleAnswerIsIgnored() async {
    let parties = LockIsolated<[String]>([])
    let store = store(pushes: Pushes(), posted: Posted(), parties: parties)
    await store.send(.joinParty("p-1", den))
    #expect(store.state.homeJoin == .idle)
    await store.send(.watch(profile))
    await store.send(.joinParty("p-1", den))
    await store.receive(\.homeJoinFinished)
    #expect(store.state.homeJoin == .joined(session: "p-1", console: den))
    await store.send(.homeJoinFinished(UUID(99), .failed))
    #expect(store.state.homeJoin == .joined(session: "p-1", console: den))
    #expect(parties.value == ["p-1 on 0123456789ab"])
    #expect(PSNAlertsPanel.joinNote(
        store.state.homeJoin,
        session: "p-1",
        game: false,
        consoles: [PSNAlertsFeature.PartyConsole(hardwareID: den, name: "Den")]
    ).map { String(localized: $0) }?.hasPrefix("Den joined the party") == true)
    #expect(PSNAlertsPanel.joinNote(store.state.homeJoin, session: "p-2", game: false, consoles: []) == nil)
    await store.send(.watch(nil))
    #expect(store.state.homeJoin == .idle)
}

@MainActor @Test func aFailedPartyJoinSaysWhy() async {
    let store = store(pushes: Pushes(), posted: Posted(), partyFailure: .timedOut)
    await store.send(.watch(profile))
    await store.send(.joinParty("p-1", den))
    await store.receive(\.homeJoinFinished)
    #expect(store.state.homeJoin == .failed(session: "p-1", console: den, .timedOut))
    #expect(PSNAlertsPanel.joinNote(store.state.homeJoin, session: "p-1", game: false, consoles: [])
        .map { String(localized: $0) } == "Your PS5 didn't answer in time. Try again.")
    await store.send(.watch(nil))
}

@MainActor @Test func aClearedPartyOnlyPushedStaysClearedWhenTheListIsReadAgain() async {
    let pushes = Pushes()
    let store = store(pushes: pushes, posted: Posted(), listed: [party("p-1")])
    await store.send(.watch(profile))
    pushes.continuation.yield(.party(PSNPartyAlert(sender: "Host", sessionID: "p-1")))
    await store.receive(\.arrived)
    await store.send(.clearAll)
    await store.receive(\.cleared)
    await store.send(.refresh)
    await store.receive(\.listed)
    #expect(store.state.items.isEmpty)
    await store.send(.watch(nil))
}

@MainActor @Test func anEntryFoldedIntoARepeatIsDeletedWithTheNextClear() async {
    let pushes = Pushes()
    let dismissed = LockIsolated<[String]>([])
    let later = CloudGameInvitation(
        id: "p-1",
        notificationIDs: ["n-p-1"],
        inviter: "Host",
        sessionName: "",
        titleIDs: [],
        sent: now.addingTimeInterval(60),
        unread: true,
        players: 0,
        maxPlayers: 0,
        joining: .joinable,
        kind: .party
    )
    let store = store(pushes: pushes, posted: Posted(), listed: [later], dismissed: dismissed)
    await store.send(.watch(profile))
    pushes.continuation.yield(.party(PSNPartyAlert(sender: "Host", sessionID: "p-2")))
    await store.receive(\.arrived)
    await store.send(.refresh)
    await store.receive(\.listed)
    #expect(store.state.items.map(\.id) == ["party:p-1", "party:p-2"])
    pushes.continuation.yield(.party(PSNPartyAlert(sender: "Host", sessionID: "p-3")))
    await store.receive(\.arrived)
    #expect(store.state.items.map(\.id) == ["party:p-3", "party:p-2"])
    await store.send(.refresh)
    await store.receive(\.listed)
    #expect(store.state.items.map(\.id) == ["party:p-3", "party:p-2"])
    await store.send(.clearAll)
    await store.receive(\.cleared)
    #expect(dismissed.value == ["n-p-1"])
    await store.send(.watch(nil))
}

@MainActor @Test func aJoinOnAnotherConsoleReplacesTheOneUnderWay() async {
    let attic = HardwareID(hex: "ba9876543210")!
    let parties = LockIsolated<[String]>([])
    let store = store(pushes: Pushes(), posted: Posted(), parties: parties)
    store.dependencies.streamSession.joinParty = { _, session, console throws(CloudInvitationFailure) in
        parties.withValue {
            $0.append("\(session) on \(console.hex)")
        }
        if console == den {
            try? await Task.sleep(for: .seconds(60))
        }
    }
    await store.send(.watch(profile))
    await store.send(.joinParty("p-1", den))
    await store.send(.joinParty("p-1", den))
    await store.send(.joinParty("p-1", attic))
    await store.receive(\.homeJoinFinished)
    #expect(store.state.homeJoin == .joined(session: "p-1", console: attic))
    #expect(parties.value.last == "p-1 on ba9876543210")
    #expect(parties.value.filter { $0.hasSuffix("0123456789ab") }.count <= 1)
    await store.send(.watch(nil))
}

@MainActor @Test func replyOpensTheMessagesConversationAndANewMessageInItRefreshesIt() async {
    let pushes = Pushes()
    let posted = Posted()
    let store = store(pushes: pushes, posted: posted)
    store.dependencies.psnMessages.thread = { _, _, _, _ throws(PSNMessagesFailure) in
        PSNChatThread(messages: [], complete: true)
    }
    await store.send(.watch(profile))
    pushes.continuation.yield(.message(PSNMessageAlert(sender: "Friend", groupID: "g-1", threadID: "t-1")))
    await store.receive(\.arrived)
    let entry = store.state.items[0]
    #expect(PSNAlertsPanel.replies(entry))
    await store.send(.reply(entry.id))
    guard case .conversation(let conversation) = store.state.destination else {
        Issue.record("the conversation did not open")
        return
    }
    #expect(conversation.groupID == "g-1" && conversation.threadID == "t-1" && conversation.title == "Friend")
    pushes.continuation.yield(.message(PSNMessageAlert(sender: "Friend", groupID: "g-1", threadID: "t-1")))
    await store.receive(\.arrived)
    await store.receive(\.destination)
    #expect(store.state.items.count == 1)
    #expect(posted.titles.value == ["Friend sent you a message"])
    await store.send(.closed)
    #expect(store.state.destination != nil)
    await store.send(.watch(nil))
    #expect(store.state.destination == nil)
}

@MainActor @Test func messagesOpenTheConversationsAndAnAccountChangeClosesThem() async {
    let store = store(pushes: Pushes(), posted: Posted())
    await store.send(.openConversations)
    #expect(store.state.destination == nil)
    await store.send(.watch(profile))
    await store.send(.openConversations)
    guard case .conversations(let list) = store.state.destination else {
        Issue.record("the conversations did not open")
        return
    }
    #expect(list.profile == profile)
    #expect(!PSNAlertsPanel.replies(PSNAlertsFeature.Item(
        id: "message:x",
        kind: .message(PSNMessageAlert(sender: "Friend", groupID: "g-1")),
        arrived: now
    )))
    await store.send(.watch(ProfileID(uuid: UUID(5))))
    #expect(store.state.destination == nil)
    await store.send(.watch(nil))
}
