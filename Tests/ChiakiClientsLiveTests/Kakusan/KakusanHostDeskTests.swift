@testable import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

@MainActor private final class FakeHostPlayer: KakusanHostPlayer {
    var armResult = KakusanCommandOutcome.accepted
    var armed: [KakusanHostConfiguration] = []
    var disarmed = 0
    var handler: (@MainActor (KakusanStreamEvent) -> Void)?
    var invitation: Result<KakusanGuestID, KakusanError> = .success(KakusanFixture.guest(1))
    var replies: [String] = []
    var commands: [KakusanHostCommand] = []
    var commandResult = KakusanCommandOutcome.accepted

    func rememberKakusan(_ identity: Data, _ nickname: String,
                         _ replacing: Bool) -> Result<KakusanRememberResult, KakusanError> {
        .failure(.sourceEnded)
    }

    func armKakusan(_ configuration: KakusanHostConfiguration) -> KakusanCommandOutcome {
        armed.append(configuration)
        return armResult
    }

    func disarmKakusanHost() {
        disarmed += 1
    }

    func receiveKakusanEvents(_ handler: (@MainActor (KakusanStreamEvent) -> Void)?) {
        self.handler = handler
    }

    func makeKakusanInvitation() -> Result<KakusanGuestID, KakusanError> {
        invitation
    }

    func acceptKakusanReply(_ text: String) -> Result<KakusanGuestID, KakusanError> {
        replies.append(text)
        return invitation
    }

    func sendKakusan(_ command: KakusanHostCommand) -> KakusanCommandOutcome {
        commands.append(command)
        return commandResult
    }

    func emit(_ event: KakusanStreamEvent) {
        handler?(event)
    }
}

private let configuration = KakusanHostConfiguration(capacity: 4, localSeats: 1)

private func seats(_ remote: Int) -> KakusanStreamEvent {
    var event = KakusanStreamEvent(kind: .seatsChanged)
    event.capacity = 4
    event.localSeats = 1
    event.remoteSeats = remote
    return event
}

private func snapshot(_ remote: Int) -> KakusanHostEvent {
    .seatsChanged(KakusanSeatSnapshot(capacity: 4, local: 1, remote: remote, reserved: 0))
}

@MainActor private func arm(_ desk: KakusanHostDesk,
                            into received: LockIsolated<[KakusanHostEvent]>) {
    desk.arm(configuration) { event in
        received.withValue {
            $0.append(event)
        }
    }
}

@MainActor private func binding(_ desk: KakusanHostDesk) throws -> KakusanHostBinding {
    switch desk.phase {
    case .armed(let binding), .hosting(let binding, _, _):
        return binding
    case .idle, .playing:
        throw KakusanError.internal
    }
}

@MainActor private func idle(_ desk: KakusanHostDesk) -> Bool {
    if case .idle = desk.phase {
        return true
    }
    return false
}

@MainActor @Test func anArmingWaitsForThePlayerAndDeliversItsEventsInOrder() async throws {
    let desk = KakusanHostDesk()
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    let pending = try binding(desk)
    let player = FakeHostPlayer()
    #expect(player.armed.isEmpty)
    desk.attach(player) {
        true
    }
    #expect(player.armed == [configuration])
    for remote in 0 ... 3 {
        player.emit(seats(remote))
    }
    desk.detach(player)
    await pending.events.drain()
    #expect(received.value == (0 ... 3).map(snapshot))
    #expect(idle(desk))
}

@MainActor @Test func aPlayerThatAttachesFirstIsArmedWhenTheHostArms() async throws {
    let desk = KakusanHostDesk()
    let player = FakeHostPlayer()
    desk.attach(player) {
        true
    }
    #expect(player.armed.isEmpty)
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    let bound = try binding(desk)
    #expect(player.armed == [configuration])
    player.emit(seats(2))
    #expect(desk.invite() == .success(KakusanFixture.guest(1)))
    desk.detach(player)
    await bound.events.drain()
    #expect(received.value == [snapshot(2)])
}

@MainActor @Test func malformedAndUngatedEventsAreDropped() async throws {
    let desk = KakusanHostDesk()
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    let bound = try binding(desk)
    let player = FakeHostPlayer()
    let leaseActive = LockIsolated(true)
    desk.attach(player) {
        leaseActive.value
    }
    player.emit(KakusanStreamEvent(kind: .streamShared))
    player.emit(seats(1))
    leaseActive.setValue(false)
    player.emit(seats(2))
    await bound.events.drain()
    #expect(received.value == [snapshot(1)])
}

@MainActor @Test func disarmDisarmsTheLivePlayerAndStopsItsEvents() async throws {
    let desk = KakusanHostDesk()
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    let bound = try binding(desk)
    let player = FakeHostPlayer()
    desk.attach(player) {
        true
    }
    desk.disarm()
    #expect(player.disarmed == 1)
    #expect(player.handler == nil)
    await bound.events.drain()
    #expect(received.value.isEmpty)
    #expect(desk.invite() == .failure(.internal))
    #expect(desk.send(.giveSeat(KakusanFixture.guest(1), preferred: 2, controllerType: 6, accountID: nil))
        == .rejected(.internal))
    #expect(player.commands.isEmpty)
    #expect(idle(desk))
}

@MainActor @Test func disarmBeforeAnyPlayerClearsTheArming() throws {
    let desk = KakusanHostDesk()
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    desk.disarm()
    #expect(idle(desk))
    let player = FakeHostPlayer()
    desk.attach(player) {
        true
    }
    #expect(player.armed.isEmpty)
}

@MainActor @Test func aSecondArmingNeverReceivesTheFirstArmingsEvents() async throws {
    let desk = KakusanHostDesk()
    let first = LockIsolated<[KakusanHostEvent]>([])
    let second = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: first)
    let firstBinding = try binding(desk)
    let oldPlayer = FakeHostPlayer()
    desk.attach(oldPlayer) {
        true
    }
    oldPlayer.emit(seats(1))
    desk.detach(oldPlayer)
    arm(desk, into: second)
    let secondBinding = try binding(desk)
    let newPlayer = FakeHostPlayer()
    desk.attach(newPlayer) {
        true
    }
    oldPlayer.emit(seats(2))
    newPlayer.emit(seats(3))
    desk.detach(oldPlayer)
    #expect(newPlayer.handler != nil)
    desk.detach(newPlayer)
    await firstBinding.events.drain()
    await secondBinding.events.drain()
    #expect(first.value == [snapshot(1)])
    #expect(second.value == [snapshot(3)])
}

@MainActor @Test func armingAgainRetiresTheBoundArming() async throws {
    let desk = KakusanHostDesk()
    let first = LockIsolated<[KakusanHostEvent]>([])
    let second = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: first)
    let firstBinding = try binding(desk)
    let player = FakeHostPlayer()
    desk.attach(player) {
        true
    }
    arm(desk, into: second)
    let secondBinding = try binding(desk)
    #expect(player.disarmed == 1)
    #expect(player.armed == [configuration, configuration])
    player.emit(seats(1))
    desk.detach(player)
    await firstBinding.events.drain()
    await secondBinding.events.drain()
    #expect(first.value.isEmpty)
    #expect(second.value == [snapshot(1)])
}

@MainActor @Test func anArmFailureIsReportedOnce() async throws {
    let desk = KakusanHostDesk()
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    let bound = try binding(desk)
    let first = FakeHostPlayer()
    first.armResult = .rejected(.internal)
    desk.attach(first) {
        true
    }
    let retry = FakeHostPlayer()
    retry.armResult = .rejected(.sourceJoinFailed)
    desk.attach(retry) {
        true
    }
    #expect(first.handler == nil)
    #expect(desk.invite() == .failure(.internal))
    desk.detach(retry)
    await bound.events.drain()
    #expect(received.value == [.unavailable(.internal)])
}

@MainActor @Test func commandsGoToTheArmedPlayerAndMapItsResults() throws {
    let desk = KakusanHostDesk()
    let received = LockIsolated<[KakusanHostEvent]>([])
    arm(desk, into: received)
    let player = FakeHostPlayer()
    desk.attach(player) {
        true
    }
    let guest = KakusanFixture.guest(3)
    let commands: [KakusanHostCommand] = [
        .enterCode(guest, KakusanFixture.code("1234")),
        .giveSeat(guest, preferred: 2, controllerType: 6, accountID: nil),
        .remove(guest),
        .setLocalSeats(2),
        .setCapacity(4)
    ]
    for command in commands {
        #expect(desk.send(command) == .accepted)
    }
    #expect(player.commands == commands)
    player.commandResult = .rejected(.sourceEnded)
    #expect(desk
        .send(.giveSeat(guest, preferred: 2, controllerType: 6, accountID: nil)) == .rejected(.sourceEnded))
    player.commandResult = .rejected(.sourceJoinFailed)
    #expect(desk.send(.giveSeat(guest, preferred: 2, controllerType: 6, accountID: nil))
        == .rejected(.sourceJoinFailed))
    #expect(desk.importReply(KakusanFixture.reply) == .success(KakusanFixture.guest(1)))
    #expect(player.replies == [KakusanFixture.reply.text])
    player.invitation = .failure(.sourceEnded)
    #expect(desk.invite() == .failure(.sourceEnded))
    player.invitation = .failure(.internal)
    #expect(desk.invite() == .failure(.internal))
    player.invitation = .failure(.identityChanged)
    #expect(desk.importReply(KakusanFixture.reply) == .failure(.identityChanged))
}
