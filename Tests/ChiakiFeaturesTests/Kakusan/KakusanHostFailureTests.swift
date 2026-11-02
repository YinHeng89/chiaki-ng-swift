#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiFeatures
    import ChiakiModels
    import ChiakiTestSupport
    import ComposableArchitecture
    import Foundation
    import Testing
    private let first = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-00000000F002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-00000000F003")!

    private func isRemove(_ command: KakusanHostCommand) -> Bool {
        if case .remove = command {
            return true
        }
        return false
    }

    private func operation(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    @MainActor
    private func store(
        _ initial: KakusanHostFeature.State,
        commands: LockIsolated<[KakusanHostCommand]>,
        clock: TestClock<Duration> = TestClock(),
        reply: @escaping @Sendable (KakusanHostCommand) -> KakusanCommandOutcome = { _ in .accepted }
    ) -> TestStoreOf<KakusanHostFeature> {
        TestStore(initialState: armed(initial)) {
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
            $0.continuousClock = clock
            $0.kakusan.invite = { .success(KakusanFixture.guest(1)) }
            $0.kakusan.send = { command in
                commands.withValue { $0.append(command) }
                return reply(command)
            }
        }
    }

    @MainActor @Test func wrongCodesEndEachAttemptAndThreeStartACooldown() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let clock = TestClock()
        let initial = hostState(
            [.init(first, 1, .verifying), .init(second, 2, .verifying), .init(third, 3, .verifying)],
            presented: first
        )
        let host = store(initial, commands: commands, clock: clock) { command in
            if case .enterCode = command {
                return .rejected(.pairingFailed)
            }
            return .accepted
        }
        await host.send(.submitCode(first, "1111")) {
            _ = $0.guests[id: first]?.attempt.apply(.code(.submit(operation(0))))
            $0.followPresented()
        }
        await host.receive(.codeResult(first, operation: operation(0), .rejected(.pairingFailed))) {
            _ = $0.guests[id: first]?.attempt.apply(.code(.result(operation(0), .pairingFailed)))
            $0.pairingFailures = [KakusanFixture.now]
            $0.followPresented()
        }
        #expect(host.state.guests[id: first]?.attempt.outcome == .failed(.pairingFailed))
        await host.send(.submitCode(second, "2222")) {
            _ = $0.guests[id: second]?.attempt.apply(.code(.submit(operation(1))))
            $0.followPresented()
        }
        await host.receive(.codeResult(second, operation: operation(1), .rejected(.pairingFailed))) {
            $0.guests.remove(id: second)
            $0.pairingFailures = [KakusanFixture.now, KakusanFixture.now]
            $0.followPresented()
        }
        await host.receive(.delegate(.notice(.ended(name: nil, .failed(.pairingFailed)))))
        await host.send(.event(.stateChanged(
            KakusanFixture.guest(3),
            KakusanStateChange(state: .closed, error: .pairingFailed)
        ))) {
            $0.guests.remove(id: third)
            $0.pairingFailures = []
            $0.cooldownUntil = KakusanFixture.now.addingTimeInterval(300)
            $0.followPresented()
        }
        await host.receive(.delegate(.notice(.ended(name: nil, .failed(.pairingFailed)))))
        await host.send(.invite)
        #expect(commands.value.filter(isRemove) == [
            .remove(KakusanFixture.guest(1)), .remove(KakusanFixture.guest(2))
        ])
        await host.send(.submitCode(first, "3333"))
        await clock.advance(by: .seconds(300))
        await host.receive(.cooldownEnded) {
            $0.cooldownUntil = nil
            $0.followPresented()
        }
    }

    @MainActor @Test func noDirectPathKeepsThePresentedFailureUntilDismissed() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let host = store(hostState([.init(first, 1, .connecting)], presented: first), commands: commands)
        let failure = KakusanStateChange(state: .closed, error: .noPath)
        await host.send(.event(.stateChanged(KakusanFixture.guest(1), failure))) {
            _ = $0.guests[id: first]?.attempt.apply(.state(failure))
            $0.followPresented()
        }
        #expect(host.state.presentedGuest?.attempt.outcome == .failed(.noPath))
        #expect(KakusanAttemptOutcome.failed(.noPath).title == "A direct path wasn’t available")
        await host.send(.dismiss(first)) {
            $0.guests = []
            $0.destination = nil
            $0.followPresented()
        }
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func unpresentedInvitationExpiresWithANotice() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let clock = TestClock()
        let host = store(hostState([.init(first, 1, .preparing)]), commands: commands, clock: clock)
        let deadline = KakusanFixture.now.addingTimeInterval(600)
        await host.send(.inviteResult(
            first,
            operation: KakusanFixture.operation,
            .success(KakusanFixture.guest(1))
        )) {
            _ = $0.guests[id: first]?.attempt.apply(.invitation(.invited(
                KakusanFixture.operation,
                KakusanFixture.guest(1)
            )))
            $0.followPresented()
        }
        await host.send(.event(.invitationReady(
            KakusanFixture.guest(1),
            KakusanFixture.invitation,
            expiresAt: deadline
        ))) {
            _ = $0.guests[id: first]?.attempt.apply(.invitation(.ready(KakusanInvitation(
                block: KakusanFixture.invitation, expiresAt: deadline
            ))))
            $0.followPresented()
        }
        await clock.advance(by: .seconds(599))
        await clock.advance(by: .seconds(1))
        await host.receive(.expire(first)) {
            $0.guests = []
            $0.followPresented()
        }
        await host.receive(.delegate(.notice(.invitationEnded(.failed(.expired)))))
        #expect(commands.value == [.remove(KakusanFixture.guest(1))])
    }

    @MainActor @Test func hostingUnavailableEndsAttemptsAndBlocksInvites() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let host = store(hostState([.init(first, 1, .invitation)], presented: first), commands: commands)
        let change = KakusanStateChange(state: .closed, error: .noPath)
        await host.send(.event(.unavailable(.noPath))) {
            $0.hosting = .unavailable(.noPath)
            _ = $0.guests[id: first]?.attempt.apply(.state(change))
            $0.followPresented()
        }
        await host.send(.invite)
        #expect(!host.state.canInvite(now: KakusanFixture.now))
        #expect(!host.state.invitesOpen)
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func consoleJoinFailureIsReportedToTheEngine() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let host = store(hostState([.init(first, 1, .seating)]), commands: commands)
        await host.send(.seatDeclined(KakusanFixture.guest(1))) {
            _ = $0.guests[id: first]?.attempt.apply(.seat(.consoleJoinFailed))
            $0.followPresented()
        }
        await host.receive(.delegate(.releaseSeat(KakusanFixture.guest(1))))
        await host.send(.event(.consoleSeated(KakusanFixture.guest(7), pad: 3)))
        #expect(commands.value.isEmpty)
        let failure = KakusanStateChange(state: .closed, error: .sourceJoinFailed)
        await host.send(.event(.stateChanged(KakusanFixture.guest(1), failure))) {
            $0.guests = []
            $0.followPresented()
        }
        await host.receive(.delegate(.notice(.ended(name: nil, .failed(.sourceJoinFailed)))))
    }

    @MainActor @Test func leavingGuestReleasesTheirSeat() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let host = store(hostState([.init(first, 1, .active)]), commands: commands)
        let left = KakusanStateChange(state: .closed, reason: .user, byPeer: true)
        await host.send(.event(.stateChanged(KakusanFixture.guest(1), left))) {
            $0.guests = []
            $0.followPresented()
        }
        await host.receive(.delegate(.releaseSeat(KakusanFixture.guest(1))))
        await host.receive(.delegate(.notice(.ended(name: nil, .closed(.user, byPeer: true)))))
        #expect(commands.value.isEmpty)
    }
#endif
