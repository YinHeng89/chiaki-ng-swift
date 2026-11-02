#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiFeatures
    import ChiakiModels
    import ChiakiTestSupport
    import ComposableArchitecture
    import Foundation
    import Testing
    private let attemptID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
    private let guest = KakusanFixture.guest(1)
    private let remote = KakusanRemotePlayer(guest: guest, name: nil)

    @MainActor
    private func seatStore(
        _ stage: KakusanHostStage,
        commands: LockIsolated<[KakusanHostCommand]>,
        reply: @escaping @Sendable (KakusanHostCommand) -> KakusanCommandOutcome = { _ in .accepted }
    ) -> TestStoreOf<KakusanHostFeature> {
        TestStore(initialState: armed(hostState([.init(attemptID, 1, stage)]))) {
            KakusanHostFeature()
        } withDependencies: {
            $0.kakusan.nickname = KakusanFixture.nickname
            $0.kakusan.useStunServers = { _ in
                .success(())
            }
            $0.kakusan.disarm = {}
            $0.kakusan.loadSettings = {
                KakusanSettings()
            }
            $0.uuid = .incrementing
            $0.date = .constant(KakusanFixture.now)
            $0.continuousClock = TestClock()
            $0.kakusan.send = { command in
                commands.withValue { $0.append(command) }
                return reply(command)
            }
        }
    }

    @MainActor @Test func hostAsksTheCoreForASeatWithoutChoosingOne() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.admitting, commands: commands)
        await store.send(.localSeatsChanged(3)) {
            $0.localSeats = 3
            $0.followPresented()
        }
        await store.send(.event(.stateChanged(guest, KakusanStateChange(state: .admitting)))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.seat(.joinRequested))
            $0.followPresented()
        }
        await store.receive(.delegate(.claimSeat(remote)))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingConsole))
        #expect(store.state.guests[id: attemptID]?.attempt.seat == nil)
        await store.send(.giveSeat(guest, controllerType: 2, accountID: nil))
        #expect(commands.value == [
            .setLocalSeats(3),
            .giveSeat(guest, preferred: nil, controllerType: 2, accountID: nil)
        ])
    }

    @MainActor @Test func hostShowsTheSeatAndGrantTheCoreReports() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.seating, commands: commands)
        let granted = KakusanSeatGrant(seat: 4, generation: 9)
        let ready = KakusanStateChange(state: .readyWait, seat: 4, generation: 9, consoleSeat: 3)
        await store.send(.event(.stateChanged(guest, ready))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(ready))
            $0.followPresented()
        }
        await store.receive(.delegate(.showSeat(remote, pad: 3)))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .readying(granted, pad: 3))
        let regranted = KakusanSeatGrant(seat: 2, generation: 10)
        let playing = KakusanStateChange(state: .active, seat: 2, generation: 10, consoleSeat: 1)
        await store.send(.event(.stateChanged(guest, playing))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(playing))
            $0.followPresented()
        }
        await store.receive(.delegate(.showSeat(remote, pad: 1)))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .active(regranted, pad: 1))
        #expect(store.state.guests[id: attemptID]?.attempt.seat == regranted)
        await store.send(.event(.stateChanged(guest, playing)))
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func hostWaitsForTheCoreBeforeCallingAGuestSeated() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.seating, commands: commands)
        await store.send(.event(.stateChanged(guest, KakusanStateChange(state: .readyWait))))
        await store.send(.event(.stateChanged(guest, KakusanStateChange(state: .active, seat: 3))))
        await store.send(.event(.stateChanged(
            guest,
            KakusanStateChange(state: .active, seat: 3, generation: 7)
        )))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingConsole))
        #expect(store.state.guests[id: attemptID]?.attempt.pad == nil)
    }

    @MainActor @Test func hostFollowsTheConsoleJoiningAndDroppingAGuest() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.seating, commands: commands)
        await store.send(.event(.consoleSeated(guest, pad: 2))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.seat(.consoleJoined(pad: 2)))
            $0.followPresented()
        }
        await store.receive(.delegate(.showSeat(remote, pad: 2)))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .admitting(.consoleJoined(pad: 2)))
        await store.send(.event(.consoleSeated(guest, pad: 2)))
        await store.send(.event(.stateChanged(guest, KakusanFixture.seated(.active)))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(KakusanFixture.seated(.active)))
            $0.followPresented()
        }
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .active(KakusanFixture.grant, pad: 2))
        await store.send(.event(.consoleUnseated(guest, pad: 3)))
        await store.send(.event(.consoleUnseated(guest, pad: 2))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.seat(.consoleLeft(pad: 2)))
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(guest)))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .closing(.closed(.source, byPeer: false)))
        await store.send(.event(.stateChanged(guest, KakusanStateChange(state: .closed, reason: .source)))) {
            $0.guests = []
            $0.followPresented()
        }
        await store.receive(.delegate(.notice(.ended(name: nil, .closed(.source, byPeer: false)))))
        await store.send(.event(.consoleUnseated(guest, pad: 2)))
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func hostFreesTheCouchWhenTheCoreRefusesTheSeat() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.seating, commands: commands) { _ in
            .rejected(.noCapacity)
        }
        await store.send(.giveSeat(guest, controllerType: 6, accountID: nil))
        let refused = KakusanHostCommand.giveSeat(guest, preferred: nil, controllerType: 6, accountID: nil)
        await store.receive(.commandFailed(refused, .noCapacity)) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.seat(.consoleJoinFailed))
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(guest)))
        await store.receive(.delegate(.notice(.commandFailed(.noCapacity))))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .admitting(.awaitingSeat))
    }

    @MainActor @Test func hostShowsTheSeatTheCoreReservedBeforeTheConsoleJoins() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.seating, commands: commands)
        let held = KakusanFixture.reserved()
        await store.send(.event(.stateChanged(guest, held))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(held))
            $0.followPresented()
        }
        await store.receive(.delegate(.reserveSeat(remote, pad: 2)))
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .admitting(
            .reserved(KakusanFixture.grant, pad: 2)
        ))
        #expect(store.state.guests[id: attemptID]?.attempt.seat == KakusanFixture.grant)
        #expect(store.state.guests[id: attemptID]?.attempt.pad == nil)
        await store.send(.event(.stateChanged(guest, held)))
        let moved = KakusanFixture.reserved(pad: 3)
        await store.send(.event(.stateChanged(guest, moved))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(moved))
            $0.followPresented()
        }
        await store.receive(.delegate(.reserveSeat(remote, pad: 3)))
        await store.send(.event(.consoleSeated(guest, pad: 3))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.seat(.consoleJoined(pad: 3)))
            $0.followPresented()
        }
        await store.receive(.delegate(.showSeat(remote, pad: 3)))
        let playing = KakusanFixture.seated(.active, pad: 3)
        await store.send(.event(.stateChanged(guest, playing))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(playing))
            $0.followPresented()
        }
        #expect(store.state.guests[id: attemptID]?.attempt.phase == .active(KakusanFixture.grant, pad: 3))
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func hostFreesTheReservedSeatWhenTheConsoleRefusesIt() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = seatStore(.seating, commands: commands)
        let held = KakusanFixture.reserved()
        await store.send(.event(.stateChanged(guest, held))) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.state(held))
            $0.followPresented()
        }
        await store.receive(.delegate(.reserveSeat(remote, pad: 2)))
        await store.send(.seatDeclined(guest))
        #expect(store.state.guests[id: attemptID]?.attempt.reservedPad == 2)
        let refused = KakusanStateChange(state: .closed, error: .sourceJoinFailed)
        await store.send(.event(.stateChanged(guest, refused))) {
            $0.guests = []
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(guest)))
        await store.receive(.delegate(.notice(.ended(name: nil, .failed(.sourceJoinFailed)))))
        #expect(commands.value.isEmpty)
    }
#endif
