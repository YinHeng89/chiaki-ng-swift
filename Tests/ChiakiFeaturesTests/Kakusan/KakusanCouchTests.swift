#if CHIAKI_KAKUSAN
    @testable import ChiakiFeatures
    import ChiakiModels
    import ChiakiTestSupport
    import Foundation
    import Testing
    import ComposableArchitecture

    private let remote = CouchRemoteInput(guest: KakusanFixture.guest(1), name: "Alex")
    private let mika = AccountProfile(
        id: UUID(),
        name: "Mika",
        method: .npsso,
        accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(4))
    )
    private let pad = ControllerDevice(
        id: 5, preferenceKey: "unit:5", name: "DualSense Wireless Controller", transport: "USB",
        individual: true,
        rumble: true, lights: true, motion: true, touchpad: true, adaptiveTriggers: true
    )

    @Test func remoteSeatsTakeTheSeatTheCoreReportsAndSkipInputRouting() {
        var seats = CouchSeats(console: .ps5)
        let (claimed, outcome) = seats.claimRemote(remote)
        #expect(claimed)
        #expect(outcome.commands.isEmpty)
        #expect(outcome.remote.isEmpty)
        #expect(seats.waiting == [.choosingAccount(remote)])
        #expect(seats.choosing == .remote(remote.guest))
        #expect(CouchSeats.pads.allSatisfy { seats[$0] == .open })
        #expect(seats.pad(for: remote.guest) == nil)
        let duplicate = seats.claimRemote(remote)
        #expect(!duplicate.claimed)
        let joining = seats.chooseAccount(mika, forRemote: remote.guest)
        #expect(joining.commands.isEmpty)
        #expect(joining.remote == [.seat(remote, controllerType: 6, accountID: mika.accountID.data)])
        #expect(seats.waiting == [.joining(remote, account: mika)])
        #expect(seats.availability(of: mika, for: 1) == .joiningRemote)
        #expect(seats.pad(for: remote.guest) == nil)
        let ready = seats.seatRemote(remote, at: 2)
        #expect(ready.commands.isEmpty)
        #expect(ready.notice.map { String(localized: $0.title) } == "Alex joined as Player 3")
        #expect(seats.waiting.isEmpty)
        #expect(seats[2] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: nil))
        #expect(seats[2].device == nil)
        #expect(seats.pad(for: remote.guest) == 2)
        let coloured = seats.apply(.confirmed(pad: 2, color: 0x00ff00))
        #expect(coloured.commands.isEmpty)
        #expect(seats[2] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: 0x00ff00))
        #expect(seats.remoteCount == 1)
        #expect(seats.localCount == 0)
        let switched = seats.setController(2, to: pad)
        #expect(!switched)
        let replaced = seats.replaceController(2, with: pad)
        #expect(replaced.commands.isEmpty)
        let removed = seats.cancel(2)
        #expect(removed.commands.isEmpty)
        #expect(removed.remote == [.removed(remote)])
        #expect(seats[2] == .open)
    }

    @Test func remoteSeatsFollowTheCoreToAnotherSeat() {
        var seats = CouchSeats(console: .ps5)
        _ = seats.apply(.confirmed(pad: 3, color: 0x112233))
        _ = seats.claimRemote(remote)
        _ = seats.chooseAccount(mika, forRemote: remote.guest)
        let seated = seats.seatRemote(remote, at: 3)
        #expect(seated.notice.map { String(localized: $0.title) } == "Alex joined as Player 4")
        #expect(seats[1] == .open)
        #expect(seats[3] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: 0x112233))
        let repeated = seats.seatRemote(remote, at: 3)
        #expect(repeated == CouchOutcome())
        let moved = seats.seatRemote(remote, at: 1)
        #expect(moved.notice.map { String(localized: $0.title) } == "Alex joined as Player 2")
        #expect(seats[3] == .open)
        #expect(seats[1] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: nil))
        #expect(seats.remoteCount == 1)
        let outside = seats.seatRemote(remote, at: 4)
        #expect(outside == CouchOutcome())
        #expect(seats.pad(for: remote.guest) == 1)
        let unknown = CouchRemoteInput(guest: KakusanFixture.guest(9), name: nil)
        _ = seats.seatRemote(unknown, at: 2)
        #expect(seats[2] == .ready(CouchPlayer(input: .remote(unknown)), color: nil))
    }

    @Test func consoleEventsOnARemoteSeatWaitForTheCore() {
        var seats = CouchSeats(console: .ps5)
        _ = seats.claimRemote(remote)
        _ = seats.chooseAccount(mika, forRemote: remote.guest)
        let asked = seats.apply(.passcodeRequested(pad: 1, retry: false))
        #expect(asked == CouchOutcome())
        #expect(seats.awaitsPasscode(1))
        #expect(seats[1] == .open)
        _ = seats.apply(.confirmed(pad: 1, color: 0x445566))
        #expect(!seats.awaitsPasscode(1))
        _ = seats.seatRemote(remote, at: 1)
        #expect(seats[1] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: 0x445566))
        for event in [
            CouchSessionEvent.joinFailed(pad: 1, failure: .refused(3)),
            .dropped(pad: 1),
            .accountUnresolvable(pad: 1)
        ] {
            #expect(seats.apply(event) == CouchOutcome())
            #expect(seats.pad(for: remote.guest) == 1)
        }
        #expect(seats.availability(of: mika, for: 2) == .seated(1))
        let released = seats.releaseRemote(remote.guest)
        #expect(released.pad == 1)
        #expect(seats[1] == .open)
        _ = seats.apply(.passcodeRequested(pad: 2, retry: false))
        _ = seats.cancel(2)
        #expect(!seats.awaitsPasscode(2))
    }

    @Test func remoteSeatsAskTheCoreAtOnceOnPS4AndRespectLimits() {
        var seats = CouchSeats(console: .ps4)
        _ = seats.claim(pad)
        _ = seats.apply(.confirmed(pad: 1, color: 0))
        let elsewhere = CouchRemoteInput(guest: KakusanFixture.guest(2), name: nil)
        let (claimed, outcome) = seats.claimRemote(elsewhere)
        #expect(claimed)
        #expect(outcome.commands.isEmpty)
        #expect(outcome.remote == [.seat(elsewhere, controllerType: 2, accountID: nil)])
        #expect(seats.waiting == [.joining(elsewhere, account: nil)])
        let early = seats.apply(.joinFailed(pad: 2, failure: .refused(3)))
        #expect(early == CouchOutcome())
        #expect(seats.waiting == [.joining(elsewhere, account: nil)])
        let held = seats.reserveRemote(elsewhere, at: 2)
        #expect(held == CouchOutcome())
        #expect(seats.waiting.isEmpty)
        #expect(seats[2] == .joining(CouchPlayer(input: .remote(elsewhere))))
        _ = seats.apply(.announced(pad: 2))
        #expect(seats[2] == .pickingOnConsole(CouchPlayer(input: .remote(elsewhere))))
        let failed = seats.apply(.joinFailed(pad: 2, failure: .refused(3)))
        #expect(failed.commands.isEmpty)
        #expect(failed.notice == .joinFailed(pad: 2, failure: .refused(3)))
        #expect(seats.pad(for: elsewhere.guest) == 2)
        let released = seats.releaseRemote(elsewhere.guest)
        #expect(released.pad == 2)
        #expect(seats[2] == .open)
        #expect(seats.waiting.isEmpty)
        var cloud = CouchSeats(console: .cloud)
        let unsupported = cloud.claimRemote(remote)
        #expect(!unsupported.claimed)
    }

    @Test func heldRemoteSeatsAreNotOfferedToLocalPlayers() {
        var seats = CouchSeats(console: .ps4)
        seats.heldForRemote = 3
        #expect(seats.lowestOpenPad == nil)
        let refused = seats.claim(pad)
        #expect(refused.commands.isEmpty)
        #expect(seats[1] == .open)
        #expect(CouchSeats.pads.allSatisfy { !seats.heldForRemote($0) })
        seats.heldForRemote = 1
        #expect(seats.lowestOpenPad == 1)
        let held = seats.claimRemote(remote)
        #expect(held.claimed)
        #expect(seats.waiting == [.joining(remote, account: nil)])
        #expect(CouchSeats.pads.allSatisfy { !seats.heldForRemote($0) })
        _ = seats.reserveRemote(remote, at: 1)
        #expect(seats.heldForRemote(1))
        #expect(!seats.heldForRemote(2))
        #expect(!seats.heldForRemote(3))
        #expect(seats.lowestOpenPad == 2)
        _ = seats.seatRemote(remote, at: 1)
        #expect(CouchSeats.pads.allSatisfy { !seats.heldForRemote($0) })
    }

    @Test func aReservedSeatShowsTheGuestUntilTheConsoleJoins() {
        var seats = CouchSeats(console: .ps5)
        _ = seats.claimRemote(remote)
        _ = seats.chooseAccount(mika, forRemote: remote.guest)
        let held = seats.reserveRemote(remote, at: 2)
        #expect(held == CouchOutcome())
        #expect(seats.waiting.isEmpty)
        #expect(seats[1] == .open)
        #expect(seats[2] == .joining(CouchPlayer(input: .remote(remote), account: mika)))
        #expect(seats.pad(for: remote.guest) == 2)
        #expect(seats.heldForRemote(2))
        #expect(seats.remoteCount == 1)
        #expect(seats.availability(of: mika, for: 1) == .seated(2))
        #expect(seats.reserveRemote(remote, at: 2) == CouchOutcome())
        let confirmed = seats.apply(.confirmed(pad: 2, color: 0x00ff00))
        #expect(confirmed == CouchOutcome())
        #expect(seats[2] == .joining(CouchPlayer(input: .remote(remote), account: mika)))
        let joined = seats.seatRemote(remote, at: 2)
        #expect(joined.commands.isEmpty)
        #expect(joined.notice.map { String(localized: $0.title) } == "Alex joined as Player 3")
        #expect(seats[2] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: 0x00ff00))
        #expect(!seats.heldForRemote(2))
        #expect(seats.reserveRemote(remote, at: 2) == CouchOutcome())
        #expect(seats[2] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: 0x00ff00))
        let moved = seats.reserveRemote(remote, at: 3)
        #expect(moved == CouchOutcome())
        #expect(seats[2] == .open)
        #expect(seats[3] == .joining(CouchPlayer(input: .remote(remote), account: mika)))
        #expect(seats.reserveRemote(remote, at: 4) == CouchOutcome())
        #expect(seats.pad(for: remote.guest) == 3)
    }

    @Test func aPasscodeOnAReservedSeatBelongsToTheWaitingGuest() {
        var seats = CouchSeats(console: .ps5)
        _ = seats.claimRemote(remote)
        _ = seats.chooseAccount(mika, forRemote: remote.guest)
        _ = seats.reserveRemote(remote, at: 2)
        let asked = seats.apply(.passcodeRequested(pad: 2, retry: false))
        #expect(asked == CouchOutcome())
        #expect(seats[2] == .passcode(CouchPlayer(input: .remote(remote), account: mika), retry: false))
        #expect(seats.awaitsPasscode(2))
        #expect(seats.heldForRemote(2))
        _ = seats.apply(.passcodeRequested(pad: 2, retry: true))
        #expect(seats[2] == .passcode(CouchPlayer(input: .remote(remote), account: mika), retry: true))
        _ = seats.apply(.confirmed(pad: 2, color: 0x445566))
        #expect(!seats.awaitsPasscode(2))
        #expect(seats[2] == .joining(CouchPlayer(input: .remote(remote), account: mika)))
        _ = seats.seatRemote(remote, at: 2)
        #expect(seats[2] == .ready(CouchPlayer(input: .remote(remote), account: mika), color: 0x445566))
        var early = CouchSeats(console: .ps5)
        _ = early.claimRemote(remote)
        _ = early.chooseAccount(mika, forRemote: remote.guest)
        _ = early.apply(.passcodeRequested(pad: 1, retry: false))
        #expect(early[1] == .open)
        _ = early.reserveRemote(remote, at: 1)
        #expect(early[1] == .passcode(CouchPlayer(input: .remote(remote), account: mika), retry: false))
        #expect(early.awaitsPasscode(1))
        let attempts = early.apply(.joinFailed(pad: 1, failure: .passcodeAttempts))
        #expect(attempts.notice == .joinFailed(pad: 1, failure: .passcodeAttempts))
        #expect(!early.awaitsPasscode(1))
        #expect(early.pad(for: remote.guest) == 1)
    }

    @Test func anAccountTheConsoleCannotResolveIsMarkedForTheWaitingGuest() {
        var seats = CouchSeats(console: .ps5)
        _ = seats.claimRemote(remote)
        _ = seats.chooseAccount(mika, forRemote: remote.guest)
        _ = seats.reserveRemote(remote, at: 2)
        let rejected = seats.apply(.accountUnresolvable(pad: 2))
        #expect(rejected.commands.isEmpty)
        #expect(rejected.remote.isEmpty)
        #expect(rejected.notice == .joinFailed(pad: 2, failure: .accountUnresolvable))
        #expect(rejected.notice.map { String(localized: $0.title) } == "Player 3 couldn’t join")
        #expect(
            rejected.notice?.detail.map { String(
                localized: $0
            ) } == "This PS5 doesn’t recognise that account."
        )
        #expect(seats.unrecognisedAccounts == [mika.accountID.data])
        #expect(seats.availability(of: mika, for: nil) == .unrecognised)
        #expect(seats.pad(for: remote.guest) == 2)
        let released = seats.releaseRemote(remote.guest)
        #expect(released.pad == 2)
        #expect(seats[2] == .open)
        #expect(seats.availability(of: mika, for: nil) == .unrecognised)
        _ = seats.claimRemote(remote)
        #expect(seats.chooseAccount(mika, forRemote: remote.guest) == CouchOutcome())
        #expect(seats.waiting == [.choosingAccount(remote)])
    }

    @MainActor @Test func remoteSeatLifecycleReportsJoinAndLeaveToTheHost() async {
        let commands = LockIsolated<[CouchCommand]>([])
        var initial = CouchReducer.State()
        initial.begin(.ps5, hostAccount: nil)
        initial.accounts = [mika]
        let store = TestStore(initialState: initial) {
            CouchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()
            $0.streamSession.runCouchCommand = { command in
                commands.withValue { $0.append(command) }
                return true
            }
        }
        store.exhaustivity = .off
        await store.send(.claimRemote(remote))
        #expect(store.state.choosing == .remote(remote.guest))
        await store.send(.chooseRemoteAccount(guest: remote.guest, account: mika.id))
        await store.receive(.delegate(.seatRemote(remote, controllerType: 6, accountID: mika.accountID.data)))
        #expect(store.state.choosing == nil)
        await store.send(.event(.confirmed(pad: 2, color: 0x112233)))
        #expect(store.state.seats[2] == .open)
        await store.send(.seatRemote(remote, pad: 2))
        #expect(store.state.seats[2] == .ready(
            CouchPlayer(input: .remote(remote), account: mika),
            color: 0x112233
        ))
        #expect(
            store.state.notices.map { String(localized: $0.notice.title) } == ["Alex joined as Player 3"]
        )
        await store.send(.event(.dropped(pad: 2)))
        #expect(store.state.seats.pad(for: remote.guest) == 2)
        await store.send(.cancel(pad: 2))
        await store.receive(.delegate(.remoteLeft(remote)))
        #expect(commands.value.isEmpty)
        await store.send(.claimRemote(remote))
        await store.send(.releaseRemote(remote.guest))
        #expect(store.state.seats.waiting.isEmpty)
        #expect(store.state.seats[2] == .open)
        await store.send(.claimRemote(remote))
        await store.send(.cancelRemote(remote.guest))
        await store.receive(.delegate(.remoteJoinFailed(remote)))
        #expect(store.state.seats.waiting.isEmpty)
        await store.send(.claimRemote(remote))
        await store.send(.chooseRemoteAccount(guest: remote.guest, account: mika.id))
        await store.receive(.delegate(.seatRemote(remote, controllerType: 6, accountID: mika.accountID.data)))
        await store.send(.cancelRemote(remote.guest))
        await store.receive(.delegate(.remoteLeft(remote)))
    }

    @MainActor @Test func aReservedRemoteSeatFollowsTheConsoleAndTheCore() async {
        let commands = LockIsolated<[CouchCommand]>([])
        var initial = CouchReducer.State()
        initial.begin(.ps5, hostAccount: nil)
        initial.accounts = [mika]
        let store = TestStore(initialState: initial) {
            CouchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()
            $0.streamSession.runCouchCommand = { command in
                commands.withValue { $0.append(command) }
                return true
            }
        }
        store.exhaustivity = .off
        await store.send(.claimRemote(remote))
        await store.send(.chooseRemoteAccount(guest: remote.guest, account: mika.id))
        await store.receive(.delegate(.seatRemote(remote, controllerType: 6, accountID: mika.accountID.data)))
        await store.send(.reserveRemote(remote, pad: 1))
        #expect(store.state.seats[1] == .joining(CouchPlayer(input: .remote(remote), account: mika)))
        #expect(store.state.accountName(for: 1) == "Mika")
        await store.send(.event(.accountUnresolvable(pad: 1)))
        #expect(store.state.notices.last?.notice == .joinFailed(pad: 1, failure: .accountUnresolvable))
        #expect(store.state.seats.pad(for: remote.guest) == 1)
        await store.send(.releaseRemote(remote.guest))
        #expect(store.state.seats[1] == .open)
        #expect(store.state.seats.availability(of: mika, for: nil) == .unrecognised)
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func remoteClaimWithoutAFreePadFailsImmediately() async {
        var initial = CouchReducer.State()
        initial.begin(.ps4, hostAccount: nil)
        initial.seats.heldForRemote = 0
        for index in 0 ..< 3 {
            let device = ControllerDevice(
                id: UInt32(20 + index), preferenceKey: "unit:\(index)", name: "DualShock 4", transport: "USB",
                individual: true, rumble: true, lights: true, motion: true, touchpad: true
            )
            _ = initial.seats.claim(device)
        }
        let store = TestStore(initialState: initial) {
            CouchReducer()
        } withDependencies: {
            $0.streamSession.runCouchCommand = { _ in true }
        }
        await store.send(.claimRemote(remote))
        await store.receive(.delegate(.remoteJoinFailed(remote)))
    }
#endif
