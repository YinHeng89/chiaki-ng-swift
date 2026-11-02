import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let player = ProfileID(uuid: UUID(5))
private let open = OwnGameSession(id: "session-1", players: 1, maxPlayers: 4, openToAnyone: true)
private let friendsOnly = OwnGameSession(id: "session-2", players: 1, maxPlayers: 4, openToAnyone: false)
private let friend = PSNFriend(id: "222", onlineID: "Friend", online: true)
private let other = PSNFriend(id: "333", onlineID: "Other")

private func picker() -> InviteFriendsFeature.State {
    InviteFriendsFeature.State(profile: player, titleID: "PPSA01234_00", platform: "PS5")
}

@MainActor @Test func openingThePickerFindsTheSessionAndTheFriends() async {
    let store = TestStore(initialState: picker()) {
        InviteFriendsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.ownGameSession = { _, _, _ throws(CloudInvitationFailure) in
            open
        }
        $0.streamSession.friends = { _ throws(CloudInvitationFailure) in
            [friend, other]
        }
    }
    await store.send(.appeared) {
        $0.session = .finding(UUID(0))
        $0.friends = .loading(UUID(1))
    }
    await store.receive(.sessionFound(UUID(0), .success(open))) {
        $0.session = .found(open)
    }
    await store.receive(.friendsListed(UUID(1), .success([friend, other]))) {
        $0.friends = .loaded([friend, other])
    }
    #expect(store.state.canShare)
    #expect(!store.state.canSend)
}

@MainActor @Test func theSessionIsLookedUpAgainUntilTheGameCreatesIt() async {
    let clock = TestClock()
    let lookups = LockIsolated(0)
    let store = TestStore(initialState: picker()) {
        InviteFriendsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.streamSession.ownGameSession = { _, _, _ throws(CloudInvitationFailure) in
            lookups.withValue {
                $0 += 1
            }
            guard lookups.value > 1 else {
                return nil
            }
            return open
        }
        $0.streamSession.friends = { _ throws(CloudInvitationFailure) in
            [friend]
        }
    }
    await store.send(.appeared) {
        $0.session = .finding(UUID(0))
        $0.friends = .loading(UUID(1))
    }
    await store.receive(.sessionFound(UUID(0), .success(nil))) {
        $0.session = .none
    }
    await store.receive(.friendsListed(UUID(1), .success([friend]))) {
        $0.friends = .loaded([friend])
    }
    await store.send(.toggled(friend.id)) {
        $0.selected = [friend.id]
    }
    #expect(!store.state.canSend)
    await clock.advance(by: InviteFriendsFeature.lookAgainAfter - .milliseconds(1))
    #expect(lookups.value == 1)
    await clock.advance(by: .milliseconds(1))
    await store.receive(.sessionWaitEnded) {
        $0.session = .finding(UUID(2))
    }
    await store.receive(.sessionFound(UUID(2), .success(open))) {
        $0.session = .found(open)
    }
    #expect(store.state.canSend)
    await clock.advance(by: .seconds(30))
    #expect(lookups.value == 2)
}

@MainActor @Test func stoppingEndsTheWaitForASession() async {
    let clock = TestClock()
    let lookups = LockIsolated(0)
    let store = TestStore(initialState: picker()) {
        InviteFriendsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.streamSession.ownGameSession = { _, _, _ throws(CloudInvitationFailure) in
            lookups.withValue {
                $0 += 1
            }
            return nil
        }
        $0.streamSession.friends = { _ throws(CloudInvitationFailure) in
            []
        }
    }
    await store.send(.appeared) {
        $0.session = .finding(UUID(0))
        $0.friends = .loading(UUID(1))
    }
    await store.receive(.sessionFound(UUID(0), .success(nil))) {
        $0.session = .none
    }
    await store.receive(.friendsListed(UUID(1), .success([]))) {
        $0.friends = .loaded([])
    }
    await store.send(.stopped)
    await clock.advance(by: .seconds(30))
    #expect(lookups.value == 1)
}

@MainActor @Test func closingThePickerEndsTheWaitForASession() async {
    let clock = TestClock()
    let lookups = LockIsolated(0)
    var initial = CloudInvitationsFeature.State(
        profile: player,
        product: ProductID(rawValue: "EP0000-PPSA01234_00-GAME000000000000")!
    )
    initial.invite = picker()
    initial.invite?.session = .finding(UUID(0))
    let store = TestStore(initialState: initial) {
        CloudInvitationsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.streamSession.ownGameSession = { _, _, _ throws(CloudInvitationFailure) in
            lookups.withValue {
                $0 += 1
            }
            return nil
        }
    }
    await store.send(.invite(.sessionFound(UUID(0), .success(nil)))) {
        $0.invite?.session = .none
    }
    await store.send(.inviteClosed) {
        $0.invite = nil
    }
    await clock.advance(by: .seconds(30))
    #expect(lookups.value == 0)
}

@MainActor @Test func pickedFriendsAreInvitedToTheSession() async {
    let sent = LockIsolated<[[String]]>([])
    var initial = picker()
    initial.session = .found(open)
    initial.friends = .loaded([friend, other])
    let store = TestStore(initialState: initial) {
        InviteFriendsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.inviteFriends = { _, target, ids throws(CloudInvitationFailure) in
            #expect(target == .game(open.id))
            sent.withValue {
                $0.append(ids)
            }
        }
    }
    await store.send(.toggled(other.id)) {
        $0.selected = [other.id]
    }
    await store.send(.toggled("nobody"))
    await store.send(.send) {
        $0.sending = .sending(UUID(0), count: 1)
    }
    await store.receive(.sent(UUID(0), nil)) {
        $0.sending = .sent(1)
        $0.selected = []
    }
    #expect(sent.value == [[other.id]])
    await store.send(.sent(UUID(9), .rejected))
}

@MainActor @Test func aFailedSendKeepsThePickedFriends() async {
    var initial = picker()
    initial.session = .found(open)
    initial.friends = .loaded([friend])
    initial.selected = [friend.id]
    let store = TestStore(initialState: initial) {
        InviteFriendsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.inviteFriends = { _, _, _ throws(CloudInvitationFailure) in
            throw .rejected
        }
    }
    await store.send(.send) {
        $0.sending = .sending(UUID(0), count: 1)
    }
    await store.receive(.sent(UUID(0), .rejected)) {
        $0.sending = .failed(.rejected)
    }
    #expect(store.state.selected == [friend.id])
}

@MainActor @Test func aShareLinkIsOnlyAskedForASessionAnyoneMayJoin() async {
    let link = SessionLink(url: URL(string: "https://example.invalid/join")!)
    var initial = picker()
    initial.session = .found(friendsOnly)
    let store = TestStore(initialState: initial) {
        InviteFriendsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.shareLink = { _, session throws(CloudInvitationFailure) in
            #expect(session == open.id)
            return link
        }
    }
    await store.send(.share)
    store.exhaustivity = .off
    await store.send(.sessionFound(UUID(7), .success(open)))
    #expect(store.state.session == .found(friendsOnly))
}

@MainActor @Test func stoppingEndsEveryRequest() async {
    var initial = picker()
    initial.session = .finding(UUID(0))
    initial.friends = .loading(UUID(1))
    let store = TestStore(initialState: initial) {
        InviteFriendsFeature()
    }
    await store.send(.stopped) {
        $0.session = .none
        $0.friends = .loaded([])
    }
    await store.send(.sessionFound(UUID(0), .success(open)))
}

@MainActor @Test func onlyAPS5GameOffersInvitingFriends() async {
    var ps5 = CloudInvitationsFeature.State(
        profile: player,
        product: ProductID(rawValue: "EP0000-PPSA01234_00-GAME000000000000")!
    )
    #expect(ps5.invitableTitle == "PPSA01234_00")
    let ps4 = CloudInvitationsFeature.State(
        profile: player,
        product: ProductID(rawValue: "EP0000-CUSA01234_00-GAME000000000000")!
    )
    #expect(ps4.invitableTitle == nil)
    let store = TestStore(initialState: ps4) {
        CloudInvitationsFeature()
    }
    await store.send(.inviteOpened)
    ps5.invite = nil
    #expect(StreamMenuInvitationsControls.controls(for: ps5).last == .invitationsInvite)
}
