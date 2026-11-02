#if CHIAKI_KAKUSAN
    import ChiakiClients
    import ChiakiModels
    import ChiakiTestSupport
    import Foundation
    import Testing
    import ComposableArchitecture
    @testable import ChiakiFeatures

    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private let stream = StreamSessionID(uuid: sessionID)
    private let attemptID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
    private let mika = AccountProfile(
        id: UUID(),
        name: "Mika",
        method: .npsso,
        accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(4))
    )
    private let console = RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5)

    @MainActor @Test func consoleStreamArmsHostingAndReportsUnavailability() async {
        let armed = LockIsolated<KakusanHostConfiguration?>(nil)
        let servers = LockIsolated<[String]?>(nil)
        let disarmed = LockIsolated(0)
        let store = StreamSessionCalls().store {
            $0.kakusan.nickname = KakusanFixture.nickname
            $0.kakusan.useStunServers = { list in
                servers.setValue(list)
                return .success(())
            }
            $0.kakusan.loadSettings = { KakusanSettings(stunServers: ["stun.example:3478"]) }
            $0.kakusan.arm = { configuration, events in
                armed.setValue(configuration)
                await events(.unavailable(.noPath))
            }
            $0.kakusan.disarm = {
                disarmed.withValue { $0 += 1 }
            }
        }
        await store.send(.startConsole(account: UUID(), console: console, route: .local))
        await store.receive(.kakusan(.event(.unavailable(.noPath)))) {
            $0.kakusan.hosting = .unavailable(.noPath)
        }
        #expect(armed.value == KakusanHostConfiguration(
            capacity: 4, localSeats: 1
        ))
        #expect(servers.value == ["stun.example:3478"])
        await store.send(.stop) {
            $0.kakusan = KakusanHostFeature.State()
        }
        await store.receive(.stopped(stream, .left))
        #expect(disarmed.value == 1)
        #expect(store.state.status == .idle)
    }

    @MainActor
    private func playingStore(
        _ stage: KakusanHostStage,
        couch: LockIsolated<[CouchCommand]>,
        host: LockIsolated<[KakusanHostCommand]>,
        kind: CouchConsole = .ps5
    ) -> TestStoreOf<StreamFeature> {
        var state = StreamFeature.State()
        state.session = .playing(stream)
        state.source = .console(
            ConsoleStreamTarget(
                profile: ProfileID(uuid: UUID()),
                console: nil,
                address: console.address,
                kind: kind == .ps4
                    ? .ps4
                    : .ps5,
                name: nil,
                remoteDeviceID: nil
            ),
            route: .home
        )
        state.couch.begin(kind, hostAccount: nil, session: stream)
        state.couch.accounts = [mika]
        state.kakusan.guests = [KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
            attemptID,
            through: stage
        ))]
        return StreamSessionCalls().store(initial: state) {
            $0.kakusan.nickname = KakusanFixture.nickname
            $0.date = .constant(KakusanFixture.now)
            $0.streamSession.runCouchCommand = { command in
                couch.withValue { $0.append(command) }
                return true
            }
            $0.kakusan.send = { command in
                host.withValue { $0.append(command) }
                return .accepted
            }
        }
    }

    @MainActor
    private func phase(_ store: TestStoreOf<StreamFeature>) -> KakusanHostPhase? {
        store.state.kakusan.guests[id: attemptID]?.attempt.phase
    }

    @MainActor @Test func anAdmittedGuestIsSeatedWithTheAccountTheHostChose() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host)
        let guest = KakusanFixture.guest(1)
        let admitted = KakusanStateChange(state: .admitting)
        await store.send(.kakusan(.event(.stateChanged(guest, admitted))))
        await store.skipReceivedActions(strict: false)
        let remote = CouchRemoteInput(guest: guest, name: nil)
        #expect(store.state.couch.seats.pad(for: guest) == nil)
        #expect(store.state.couch.choosing == .remote(guest))
        #expect(host.value.isEmpty)
        await store.send(.couch(.chooseRemoteAccount(guest: guest, account: mika.id)))
        await store.skipReceivedActions(strict: false)
        #expect(host.value == [.giveSeat(
            guest,
            preferred: nil,
            controllerType: 6,
            accountID: mika.accountID.data
        )])
        #expect(couch.value.isEmpty)
        await store.send(.event(stream, .couch(.confirmed(pad: 2, color: 0x3bc77a))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.pad == nil)
        #expect(store.state.couch.seats.pad(for: guest) == nil)
        await store.send(.kakusan(.event(.consoleSeated(guest, pad: 2))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .admitting(.consoleJoined(pad: 2)))
        #expect(store.state.couch.seats[1] == .open)
        #expect(store.state.couch.seats[2] == .ready(
            CouchPlayer(input: .remote(remote), account: mika),
            color: 0x3bc77a
        ))
        let playing = KakusanFixture.seated(.active)
        await store.send(.kakusan(.event(.stateChanged(guest, playing))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .active(KakusanFixture.grant, pad: 2))
        #expect(store.state.couch.seats.pad(for: guest) == 2)
        #expect(couch.value.isEmpty)
        #expect(host.value.count == 1)
    }

    @MainActor @Test func theCoreCanSeatAGuestAwayFromTheFirstOpenSeat() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host, kind: .ps4)
        let guest = KakusanFixture.guest(1)
        let remote = CouchRemoteInput(guest: guest, name: nil)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        #expect(host.value == [.giveSeat(guest, preferred: nil, controllerType: 2, accountID: nil)])
        #expect(store.state.couch.seats.waiting == [.joining(remote, account: nil)])
        await store.send(.kakusan(.event(.stateChanged(
            guest,
            KakusanFixture.seated(.readyWait, pad: 3)
        ))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .readying(KakusanFixture.grant, pad: 3))
        #expect(store.state.couch.seats[1] == .open)
        #expect(store.state.couch.seats[3] == .ready(CouchPlayer(input: .remote(remote)), color: nil))
        #expect(store.state.couch.seats.waiting.isEmpty)
        await store.send(.kakusan(.event(.consoleSeated(guest, pad: 1))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .readying(KakusanFixture.grant, pad: 1))
        #expect(store.state.couch.seats[3] == .open)
        #expect(store.state.couch.seats.pad(for: guest) == 1)
    }

    @MainActor @Test func theConsoleDroppingAGuestIsTakenFromTheCore() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.seating, couch: couch, host: host, kind: .ps4)
        let guest = KakusanFixture.guest(1)
        await store.send(.couch(.claimRemote(CouchRemoteInput(guest: guest, name: nil))))
        await store.skipReceivedActions(strict: false)
        await store.send(.kakusan(.event(.consoleSeated(guest, pad: 1))))
        await store.skipReceivedActions(strict: false)
        let playing = KakusanFixture.seated(.active, pad: 1)
        await store.send(.kakusan(.event(.stateChanged(guest, playing))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.pad(for: guest) == 1)
        await store.send(.event(stream, .couch(.dropped(pad: 1))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.pad(for: guest) == 1)
        #expect(phase(store) == .active(KakusanFixture.grant, pad: 1))
        await store.send(.kakusan(.event(.consoleUnseated(guest, pad: 1))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats[1] == .open)
        #expect(phase(store) == .closing(.closed(.source, byPeer: false)))
        let ended = KakusanStateChange(state: .closed, reason: .source)
        await store.send(.kakusan(.event(.stateChanged(guest, ended))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests.isEmpty)
        #expect(!host.value.contains(.remove(guest)))
        #expect(couch.value.isEmpty)
    }

    @MainActor @Test func removingTheRemoteSeatCardRemovesTheGuest() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host, kind: .ps4)
        let guest = KakusanFixture.guest(1)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        #expect(host.value == [.giveSeat(guest, preferred: nil, controllerType: 2, accountID: nil)])
        await store.send(.event(stream, .couch(.confirmed(pad: 1, color: 0))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.pad(for: guest) == nil)
        await store.send(.kakusan(.event(.consoleSeated(guest, pad: 1))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.pad(for: guest) == 1)
        await store.send(.couch(.cancel(pad: 1)))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests.isEmpty)
        #expect(host.value.contains(.remove(guest)))
        #expect(couch.value.isEmpty)
    }

    @MainActor @Test func aConsoleRefusalEndsTheGuestWhenTheCoreReportsIt() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host, kind: .ps4)
        let guest = KakusanFixture.guest(1)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        await store.send(.event(stream, .couch(.joinFailed(pad: 1, failure: .refused(5)))))
        await store.skipReceivedActions(strict: false)
        #expect(host.value == [.giveSeat(guest, preferred: nil, controllerType: 2, accountID: nil)])
        #expect(couch.value.isEmpty)
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingConsole))
        #expect(store.state.couch.seats.wait(for: guest) != nil)
        #expect(store.state.couch.notices.isEmpty)
        let refused = KakusanStateChange(state: .closed, error: .sourceJoinFailed)
        await store.send(.kakusan(.event(.stateChanged(guest, refused))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests.isEmpty)
        #expect(store.state.couch.seats.waiting.isEmpty)
        let notices = store.state.couch.notices.map(\.notice)
        #expect(notices.contains(.remote(.ended(name: nil, .failed(.sourceJoinFailed)))))
    }

    @MainActor @Test func aConsoleRefusalOfAReservedSeatIsNoticedAndClearsTheCardWhenTheCoreEndsIt() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host, kind: .ps4)
        let guest = KakusanFixture.guest(1)
        let remote = CouchRemoteInput(guest: guest, name: nil)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        #expect(host.value == [.giveSeat(guest, preferred: nil, controllerType: 2, accountID: nil)])
        await store.send(.kakusan(.event(.stateChanged(
            guest,
            KakusanFixture.reserved(pad: 1)
        ))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .admitting(.reserved(KakusanFixture.grant, pad: 1)))
        #expect(store.state.couch.seats[1] == .joining(CouchPlayer(input: .remote(remote))))
        #expect(store.state.couch.seats.waiting.isEmpty)
        await store.send(.event(stream, .couch(.joinFailed(pad: 1, failure: .refused(5)))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.notices.map(\.notice) == [.joinFailed(pad: 1, failure: .refused(5))])
        #expect(store.state.couch.seats.pad(for: guest) == 1)
        #expect(phase(store) == .admitting(.reserved(KakusanFixture.grant, pad: 1)))
        let refused = KakusanStateChange(state: .closed, error: .sourceJoinFailed)
        await store.send(.kakusan(.event(.stateChanged(guest, refused))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests.isEmpty)
        #expect(store.state.couch.seats[1] == .open)
        #expect(store.state.couch.seats.waiting.isEmpty)
        #expect(store.state.couch.notices.map(\.notice) == [
            .joinFailed(pad: 1, failure: .refused(5)),
            .remote(.ended(name: nil, .failed(.sourceJoinFailed)))
        ])
        #expect(host.value.count == 1)
        #expect(couch.value.isEmpty)
    }

    @MainActor @Test func aReservedGuestIsShownOnTheSeatTheCoreNamedThenJoins() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host)
        let guest = KakusanFixture.guest(1)
        let remote = CouchRemoteInput(guest: guest, name: nil)
        let player = CouchPlayer(input: .remote(remote), account: mika)
        await store.send(.kakusan(.event(.stateChanged(
            guest,
            KakusanStateChange(state: .admitting)
        ))))
        await store.skipReceivedActions(strict: false)
        await store.send(.couch(.chooseRemoteAccount(guest: guest, account: mika.id)))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.pad(for: guest) == nil)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanFixture.reserved()))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .admitting(.reserved(KakusanFixture.grant, pad: 2)))
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.seat == KakusanFixture.grant)
        #expect(store.state.couch.seats.pad(for: guest) == 2)
        #expect(store.state.couch.seats[1] == .open)
        #expect(store.state.couch.seats[2] == .joining(player))
        #expect(store.state.couch.seats.heldForRemote(2))
        #expect(store.state.couch.seats.waiting.isEmpty)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanFixture.reserved()))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats[2] == .joining(player))
        await store.send(.event(stream, .couch(.confirmed(pad: 2, color: 0x3bc77a))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.pad == nil)
        #expect(store.state.couch.seats[2] == .joining(player))
        await store.send(.kakusan(.event(.consoleSeated(guest, pad: 2))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .admitting(.consoleJoined(pad: 2)))
        #expect(store.state.couch.seats[2] == .ready(player, color: 0x3bc77a))
        #expect(!store.state.couch.seats.heldForRemote(2))
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanFixture.seated(.active)))))
        await store.skipReceivedActions(strict: false)
        #expect(phase(store) == .active(KakusanFixture.grant, pad: 2))
        #expect(host.value == [.giveSeat(
            guest,
            preferred: nil,
            controllerType: 6,
            accountID: mika.accountID.data
        )])
        #expect(couch.value.isEmpty)
    }

    @MainActor @Test func aPasscodeForAReservedSeatNamesTheWaitingGuest() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host)
        let guest = KakusanFixture.guest(1)
        let remote = CouchRemoteInput(guest: guest, name: nil)
        let player = CouchPlayer(input: .remote(remote), account: mika)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        await store.send(.couch(.chooseRemoteAccount(guest: guest, account: mika.id)))
        await store.skipReceivedActions(strict: false)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanFixture.reserved()))))
        await store.skipReceivedActions(strict: false)
        await store.send(.event(stream, .accessRequested(.controllerPasscode(pad: 2, retry: false))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.access.passcodePad == 2)
        #expect(store.state.couch.seats[2] == .passcode(player, retry: false))
        #expect(store.state.couch.accountName(for: 2) == "Mika")
        #expect(store.state.couch.seats.pad(for: guest) == 2)
        await store.send(.event(stream, .couch(.confirmed(pad: 2, color: 0x3bc77a))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.access.passcodePad == nil)
        await store.send(.kakusan(.event(.consoleSeated(guest, pad: 2))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats[2] == .ready(player, color: 0x3bc77a))
    }

    @MainActor @Test func anAccountTheConsoleCannotResolveIsMarkedAndNoticedForTheWaitingGuest() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host)
        let guest = KakusanFixture.guest(1)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        await store.send(.couch(.chooseRemoteAccount(guest: guest, account: mika.id)))
        await store.skipReceivedActions(strict: false)
        await store.send(.event(stream, .couch(.accountUnresolvable(pad: 2))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.availability(of: mika, for: nil) == .joiningRemote)
        #expect(store.state.couch.notices.isEmpty)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanFixture.reserved()))))
        await store.skipReceivedActions(strict: false)
        await store.send(.event(stream, .couch(.accountUnresolvable(pad: 2))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats.availability(of: mika, for: nil) == .unrecognised)
        #expect(store.state.couch.notices.map(\.notice) == [.joinFailed(
            pad: 2,
            failure: .accountUnresolvable
        )])
        #expect(store.state.couch.seats.pad(for: guest) == 2)
        let refused = KakusanStateChange(state: .closed, error: .sourceJoinFailed)
        await store.send(.kakusan(.event(.stateChanged(guest, refused))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests.isEmpty)
        #expect(store.state.couch.seats[2] == .open)
        #expect(store.state.couch.seats.availability(of: mika, for: nil) == .unrecognised)
        #expect(store.state.couch.notices.map(\.notice).first == .joinFailed(
            pad: 2,
            failure: .accountUnresolvable
        ))
        #expect(host.value == [.giveSeat(
            guest,
            preferred: nil,
            controllerType: 6,
            accountID: mika.accountID.data
        )])
        #expect(couch.value.isEmpty)
    }

    @MainActor @Test func decliningTheAccountChoiceLeavesTheGuestWaitingForASeat() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host)
        let guest = KakusanFixture.guest(1)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingConsole))
        await store.send(.couch(.cancelRemote(guest)))
        await store.skipReceivedActions(strict: false)
        #expect(host.value.isEmpty)
        #expect(couch.value.isEmpty)
        #expect(store.state.couch.seats.waiting.isEmpty)
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingSeat))
    }

    @MainActor @Test func aRefusedSeatRequestLeavesTheGuestWaitingForASeat() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.admitting, couch: couch, host: host, kind: .ps4)
        store.dependencies.kakusan.send = { command in
            host.withValue { $0.append(command) }
            return .rejected(.noCapacity)
        }
        let guest = KakusanFixture.guest(1)
        await store.send(.kakusan(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))))
        await store.skipReceivedActions(strict: false)
        #expect(host.value == [.giveSeat(guest, preferred: nil, controllerType: 2, accountID: nil)])
        #expect(store.state.couch.seats.waiting.isEmpty)
        #expect(store.state.kakusan.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingSeat))
    }

    @MainActor @Test func localPlayersAreReportedAndReservedSeatsHeldBack() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.invitation, couch: couch, host: host, kind: .ps4)
        await store.send(.kakusan(.event(.seatsChanged(KakusanSeatSnapshot(
            capacity: 4,
            local: 1,
            remote: 0,
            reserved: 2
        )))))
        #expect(store.state.couch.seats.heldForRemote == 2)
        let device = ControllerDevice(
            id: 31, preferenceKey: "unit:31", name: "DualShock 4", transport: "USB", individual: true,
            rumble: true, lights: true, motion: true, touchpad: true
        )
        await store.send(.couch(.event(.controllerClaimed(device))))
        await store.skipReceivedActions(strict: false)
        #expect(store.state.couch.seats[1].device == device)
        #expect(host.value == [.setLocalSeats(2)])
        await store.send(.kakusan(.event(.seatsChanged(KakusanSeatSnapshot(
            capacity: 4,
            local: 2,
            remote: 0,
            reserved: 2
        )))))
        #expect(store.state.couch.seats.lowestOpenPad == nil)
    }

    @MainActor @Test func stoppingTheStreamEndsEveryRemoteGuest() async {
        let couch = LockIsolated<[CouchCommand]>([])
        let host = LockIsolated<[KakusanHostCommand]>([])
        let store = playingStore(.active, couch: couch, host: host)
        await store.send(.stop) {
            $0.kakusan = KakusanHostFeature.State()
        }
        await store.skipReceivedActions(strict: false)
        await store.send(.kakusan(.event(.stateChanged(
            KakusanFixture.guest(1),
            KakusanStateChange(state: .closed)
        ))))
        #expect(store.state.kakusan.guests.isEmpty)
    }
#endif
