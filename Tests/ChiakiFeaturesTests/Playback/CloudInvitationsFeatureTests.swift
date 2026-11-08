import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let product = ProductID(rawValue: "EP0000-PPSA01234_00-GAME000000000000")!

private func invitation(
    _ id: String,
    title: String = "PPSA01234_00",
    joining: CloudGameInvitation.Joining = .joinable
) -> CloudGameInvitation {
    CloudGameInvitation(
        id: id,
        inviter: "Friend",
        sessionName: "",
        titleIDs: [title],
        sent: nil,
        unread: false,
        players: 1,
        maxPlayers: 4,
        joining: joining
    )
}

private let session = "0B7E3C5A-1F2D-4C6B-9A8E-2D4F6A8C0E1B"

private func state() -> CloudInvitationsFeature.State {
    CloudInvitationsFeature.State(profile: ProfileID(uuid: UUID(0)), product: product)
}

@MainActor @Test func onlyInvitationsToTheStreamedGameAreShown() {
    var invitations = state()
    invitations.listing = .loaded([invitation("a"), invitation("b", title: "PPSA09999_00")])
    #expect(invitations.shown.map(\.id) == ["a"])
}

@MainActor @Test func aStaleListingIsIgnored() async {
    let store = TestStore(initialState: state()) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.invitations = { _ throws(CloudInvitationFailure) in
            while !Task.isCancelled {
                await Task.yield()
            }
            return []
        }
    }
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.send(.refresh)
    await store.send(.listed(UUID(0), .success([invitation("old")])))
    #expect(store.state.listing == .loading(UUID(1), kept: []))
    await store.send(.listed(UUID(1), .success([invitation("new")])))
    #expect(store.state.listing == .loaded([invitation("new")]))
    await store.skipInFlightEffects()
}

@MainActor @Test func aJoinTheConsoleAcceptsClosesTheMenu() async {
    var initial = state()
    initial.listing = .loaded([invitation(session)])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { profile, joined throws(CloudInvitationFailure) in
            #expect(profile == ProfileID(uuid: UUID(0)))
            #expect(joined == session)
        }
    }
    store.exhaustivity = .off
    await store.send(.join(session))
    await store.receive(\.joinFinished)
    await store.receive(.delegate(.joined))
    #expect(store.state.joining == .joined(session))
    #expect(store.state.invitations.isEmpty)
}

@MainActor @Test func aJoinedInvitationsNotificationsAreCleared() async {
    let cleared = LockIsolated<[String]>([])
    var initial = state()
    initial.listing = .loaded([CloudGameInvitation(
        id: session,
        notificationIDs: ["n-1", "n-2"],
        inviter: "Friend",
        sessionName: "",
        titleIDs: ["PPSA01234_00"],
        sent: nil,
        unread: false,
        players: 1,
        maxPlayers: 4,
        joining: .joinable
    )])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, _ throws(CloudInvitationFailure) in
        }
        $0.streamSession.dismissNotifications = { _, ids throws(CloudInvitationFailure) in
            cleared.withValue {
                $0 += ids
            }
        }
    }
    store.exhaustivity = .off
    await store.send(.join(session))
    await store.receive(\.joinFinished)
    await store.receive(.delegate(.joined))
    await store.finish()
    #expect(cleared.value == ["n-1", "n-2"])
}

@MainActor @Test func reopeningThePanelReadsTheListAgain() async {
    var initial = state()
    initial.listing = .loaded([invitation("old")])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.invitations = { _ throws(CloudInvitationFailure) in
            [invitation("new")]
        }
    }
    await store.send(.appeared) {
        $0.listing = .loading(UUID(0), kept: [invitation("old")])
    }
    await store.receive(.listed(UUID(0), .success([invitation("new")]))) {
        $0.listing = .loaded([invitation("new")])
    }
}

@MainActor @Test func onlyAJoinableShownInvitationIsJoined() async {
    var initial = state()
    initial.listing = .loaded([invitation(session), invitation("full", joining: .full)])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, _ throws(CloudInvitationFailure) in
            throw .rejected
        }
    }
    store.exhaustivity = .off
    await store.send(.join("full"))
    #expect(store.state.joining == .idle)
    await store.send(.join(session))
    #expect(store.state.joining == .joining(invitation: session, operation: UUID(0)))
    await store.send(.join(session))
    await store.receive(\.joinFinished)
    #expect(store.state.joining == .failed(invitation: session, .rejected))
}

/// A pending cloud command cannot close the menu before its own completion arrives.
@MainActor @Test func aCloudJoinWaitsForCompletionAndIgnoresStaleResults() async {
    let clock = TestClock()
    var initial = state()
    initial.listing = .loaded([invitation(session)])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, _ throws(CloudInvitationFailure) in
            do {
                try await clock.sleep(for: .seconds(1))
            } catch {
                throw .cancelled
            }
        }
    }
    await store.send(.join(session)) {
        $0.joining = .joining(invitation: session, operation: UUID(0))
    }
    await store.send(.joinFinished(UUID(9), nil))
    await store.send(.join(session))
    await clock.advance(by: .seconds(1))
    await store.receive(.joinFinished(UUID(0), nil)) {
        $0.joining = .joined(session)
        $0.listing = .loaded([])
    }
    await store.receive(.delegate(.joined))
}

/// Ending the stream invalidates the join operation even when a late success arrives.
@MainActor @Test func aCloudJoinCannotCompleteAfterTheStreamStops() async {
    let clock = TestClock()
    var initial = state()
    initial.listing = .loaded([invitation(session)])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, _ throws(CloudInvitationFailure) in
            do {
                try await clock.sleep(for: .seconds(30))
            } catch {
                throw .cancelled
            }
        }
    }
    await store.send(.join(session)) {
        $0.joining = .joining(invitation: session, operation: UUID(0))
    }
    await store.send(.streamEnded) {
        $0.joining = .idle
    }
    await store.send(.joinFinished(UUID(0), nil))
    await store.finish()
}

@MainActor @Test func aPSNowJoinSendsTheStreamInviteDeepLinkInsteadOfAGameIntent() async {
    var initial = state()
    initial.listing = .loaded([
        CloudGameInvitation(
            id: "session-1",
            invitationID: "invite-1",
            inviter: "Friend",
            sessionName: "",
            titleIDs: ["PPSA01234_00"],
            sent: nil,
            unread: false,
            players: 1,
            maxPlayers: 4,
            joining: .joinable
        )
    ])
    let sent = LockIsolated<[String]>([])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, _ throws(CloudInvitationFailure) in
            Issue.record("A PS Now join must not send a game intent")
        }
        $0.streamSession.joinInvitation = { invitation, session in
            sent.withValue {
                $0.append("\(invitation) \(session)")
            }
            return true
        }
    }
    store.exhaustivity = .off
    await store.send(.join("session-1"))
    await store.receive(\.joinFinished)
    await store.receive(.delegate(.joined))
    #expect(sent.value == ["invite-1 session-1"])
    #expect(store.state.joining == .joined("session-1"))
}

@MainActor @Test func aPSNowJoinFailsWhenNoStreamTakesTheDeepLinkOrTheInvitationHasNoID() async {
    var initial = state()
    initial.listing = .loaded([
        invitation("a"),
        CloudGameInvitation(
            id: "b",
            invitationID: "invite-b",
            inviter: "Friend",
            sessionName: "",
            titleIDs: ["PPSA01234_00"],
            sent: nil,
            unread: false,
            players: 1,
            maxPlayers: 4,
            joining: .joinable
        )
    ])
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinInvitation = { _, _ in
            false
        }
    }
    store.exhaustivity = .off
    await store.send(.join("a"))
    await store.receive(\.joinFinished)
    #expect(store.state.joining == .failed(invitation: "a", .cannotJoin))
    await store.send(.join("b"))
    await store.receive(\.joinFinished)
    #expect(store.state.joining == .failed(invitation: "b", .failed))
}

@MainActor @Test func invitationsToTheOtherVersionOfTheStreamedGameAreShown() {
    var streaming = CloudInvitationsFeature.State(
        profile: ProfileID(uuid: UUID(0)),
        product: ProductID(rawValue: "UP9000-CUSA18886_00-SACKBOYADVENTURE")!,
        otherVersion: ProductID(rawValue: "UP9000-PPSA01289_00-SACKBOYADVENTURE")!
    )
    streaming.listing = .loaded([
        invitation("ps5", title: "PPSA01289_00"),
        invitation("ps4", title: "CUSA18886_00"),
        invitation("elsewhere", title: "PPSA09999_00")
    ])
    #expect(streaming.shown.map(\.id) == ["ps5", "ps4"])
    streaming.otherVersion = nil
    #expect(streaming.shown.map(\.id) == ["ps4"])
}

@Test func onlySessionManagerInvitationsJoinByGameIntent() {
    #expect(CloudInvitationsFeature.joinsByGameIntent(invitation("0B7E3C5A-1F2D-4C6B-9A8E-2D4F6A8C0E1B")))
    #expect(!CloudInvitationsFeature.joinsByGameIntent(invitation("a")))
}

private func partyInvitation(_ id: String) -> CloudGameInvitation {
    CloudGameInvitation(
        id: id,
        inviter: "Host",
        sessionName: "",
        titleIDs: [],
        sent: nil,
        unread: true,
        players: 0,
        maxPlayers: 0,
        joining: .joinable,
        kind: .party
    )
}

@MainActor @Test func partyInvitationsAreLeftOutOfTheStream() {
    var cloud = state()
    cloud.listing = .loaded([partyInvitation(session), invitation("a")])
    #expect(cloud.shown.map(\.id) == ["a"])
}

@MainActor @Test func aStreamStartedToAcceptAnInvitationJoinsItOnceItPlays() async {
    let joined = LockIsolated<[String]>([])
    let pending = invitation(session)
    var initial = state()
    initial.pendingJoin = pending
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, id throws(CloudInvitationFailure) in
            joined.withValue {
                $0.append(id)
            }
        }
    }
    store.exhaustivity = .off
    await store.send(.streamStarted)
    #expect(store.state.pendingJoin == nil)
    #expect(store.state.invitations == [pending])
    await store.receive(\.joinFinished)
    await store.receive(.delegate(.joined))
    #expect(joined.value == [session])
    await store.send(.streamStarted)
    #expect(joined.value == [session])
}

@MainActor @Test func aCloudLaunchCarriesTheInvitationIntoTheStream() throws {
    let pending = invitation(session)
    let request = CloudStreamRequest(
        profile: ProfileID(uuid: UUID(0)),
        title: CloudStreamTitle(product: product, name: "Game", service: .psCloud),
        joining: pending
    )
    let panel = try #require(StreamFeature.invitations(for: .cloud(request)))
    #expect(panel.pendingJoin == pending)
}

@MainActor @Test func aFailedAutomaticJoinIsAnnouncedButAPlayersJoinIsNot() async {
    let pending = invitation(session)
    var initial = state()
    initial.pendingJoin = pending
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.joinOnCloud = { _, _ throws(CloudInvitationFailure) in
            throw .full
        }
    }
    store.exhaustivity = .off
    await store.send(.streamStarted)
    #expect(store.state.automaticJoin == session)
    await store.receive(\.joinFinished)
    await store.receive(.delegate(.automaticJoinFailed(.full)))
    #expect(store.state.automaticJoin == nil)
    #expect(store.state.joining == .failed(invitation: session, .full))
    await store.send(.join(session))
    await store.receive(\.joinFinished)
    #expect(store.state.joining == .failed(invitation: session, .full))
    await store.finish()
}

@MainActor @Test func anAutomaticJoinThatCannotStartIsAnnounced() async {
    var initial = state()
    initial.pendingJoin = invitation(session, joining: .full)
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
    }
    store.exhaustivity = .off
    await store.send(.streamStarted)
    await store.receive(.delegate(.automaticJoinFailed(.cannotJoin)))
    #expect(store.state.automaticJoin == nil)
    #expect(!store.state.isJoining)
}

@Test func aFailedJoinNoticeSaysWhy() {
    let notice = CloudSystemNotice(
        kind: .invitationJoinFailed,
        detail: String(localized: StreamMenuInvitationsControls.message(.full))
    )
    #expect(notice.headline == "Couldn't join the invitation")
    #expect(notice.lines == ["This game group is already full."])
    #expect(notice.shownFor == .seconds(6))
}
