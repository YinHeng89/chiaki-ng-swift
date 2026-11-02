#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiFeatures
    import ChiakiModels
    import ChiakiTestSupport
    import ComposableArchitecture
    import Foundation
    import Testing
    private let attemptID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
    private let otherID = UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!

    private func zeroUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    @MainActor
    private func sessionStore(
        _ state: KakusanHostFeature.State,
        commands: LockIsolated<[KakusanHostCommand]>,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<KakusanHostFeature> {
        TestStore(initialState: armed(state)) {
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
                return .accepted
            }
            configure(&$0)
        }
    }

    @MainActor @Test func staleHostEventsAreIgnoredAndEarlyOnesReplayed() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = sessionStore(hostState([.init(attemptID, 1, .connecting)]), commands: commands)
        await store.send(.event(.codeReady(KakusanFixture.guest(9), KakusanFixture.code("1234"))))
        await store.send(.replyResult(attemptID, operation: zeroUUID(99), .success(KakusanFixture.guest(1))))
        await store.send(.approvalResult(attemptID, operation: zeroUUID(98), .accepted))
        await store.send(.codeResult(attemptID, operation: zeroUUID(97), .rejected(.pairingFailed)))
        await store.send(.expire(attemptID))
        await store.send(.recognised(attemptID, KakusanFixture.key(42), .unknown))
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func earlyInvitationEventsWaitForTheInviteResult() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        var initial = KakusanHostFeature.State()
        initial.guests = [KakusanHostFeature.Guest(attempt: KakusanHostAttempt(
            id: otherID,
            operation: KakusanFixture.operation
        ))]
        let store = sessionStore(initial, commands: commands)
        let deadline = KakusanFixture.now.addingTimeInterval(600)
        let early = KakusanHostEvent.invitationReady(
            KakusanFixture.guest(5),
            KakusanFixture.invitation,
            expiresAt: deadline
        )
        await store.send(.event(early)) {
            $0.early = [KakusanFixture.guest(5): [early]]
            $0.followPresented()
        }
        await store.send(.inviteResult(
            otherID,
            operation: KakusanFixture.operation,
            .success(KakusanFixture.guest(5))
        )) {
            $0.early = [:]
            _ = $0.guests[id: otherID]?.attempt.apply(.invitation(.invited(
                KakusanFixture.operation,
                KakusanFixture.guest(5)
            )))
            _ = $0.guests[id: otherID]?.attempt.apply(.invitation(.ready(KakusanInvitation(
                block: KakusanFixture.invitation, expiresAt: deadline
            ))))
            $0.followPresented()
        }
        await store.send(.cancel(otherID)) {
            $0.guests = []
            $0.followPresented()
        }
        #expect(commands.value == [.remove(KakusanFixture.guest(5))])
    }

    @MainActor @Test func hostRemovingASeatedGuestReleasesTheSeat() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = sessionStore(hostState([.init(attemptID, 1, .active)]), commands: commands)
        await store.send(.removeGuest(KakusanFixture.guest(1))) {
            $0.guests = []
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(KakusanFixture.guest(1))))
        #expect(commands.value == [.remove(KakusanFixture.guest(1))])
        let left = KakusanStateChange(state: .closed, reason: .user, byPeer: false)
        await store.send(.event(.stateChanged(KakusanFixture.guest(1), left)))
        await store.send(.removeGuest(KakusanFixture.guest(1)))
    }

    @MainActor @Test func aReplyForAnotherInvitationMovesToThatAttempt() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        var initial = hostState([.init(attemptID, 1, .invitation), .init(otherID, 2, .invitation)])
        initial.destination = .invite(KakusanInviteFeature.State(guest: attemptID))
        let store = sessionStore(initial, commands: commands) {
            $0.kakusan.importReply = { _ in .success(KakusanFixture.guest(2)) }
        }
        await store.send(.submitReply(attemptID, KakusanFixture.reply.text)) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.reply(.submit(zeroUUID(0))))
            $0.guests[id: attemptID]?.replyOperation = zeroUUID(0)
            $0.followPresented()
        }
        await store.receive(.replyResult(
            attemptID,
            operation: zeroUUID(0),
            .success(KakusanFixture.guest(2))
        )) {
            $0.guests[id: attemptID]?.replyOperation = nil
            _ = $0.guests[id: attemptID]?.attempt.apply(.reply(.redirected(zeroUUID(0))))
            _ = $0.guests[id: otherID]?.attempt.apply(.reply(.imported(nil)))
            _ = $0.guests[id: otherID]?.attempt.apply(.approval(.request(zeroUUID(1))))
            $0.destination = .invite(KakusanInviteFeature.State(guest: otherID))
            $0.followPresented()
        }
        await store.receive(.approvalResult(otherID, operation: zeroUUID(1), .accepted)) {
            _ = $0.guests[id: otherID]?.attempt.apply(.approval(.result(zeroUUID(1), nil)))
            $0.followPresented()
        }
        await store.send(.submitReply(attemptID, "hello")) {
            _ = $0.guests[id: attemptID]?.attempt.apply(.reply(.submit(zeroUUID(2))))
            _ = $0.guests[id: attemptID]?.attempt.apply(.reply(.rejected(zeroUUID(2), .invalidBlock)))
            $0.followPresented()
        }
        #expect(commands.value.isEmpty)
    }

    @MainActor @Test func localSeatChangesReachTheEngineAndSurfaceNoFreeSeat() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = sessionStore(hostState([.init(attemptID, 1, .invitation)]), commands: commands) {
            $0.kakusan.send = { command in
                commands.withValue { $0.append(command) }
                return command == .setLocalSeats(4)
                    ? .rejected(.noCapacity)
                    : .accepted
            }
        }
        await store.send(.localSeatsChanged(1))
        await store.send(.localSeatsChanged(2)) {
            $0.localSeats = 2
            $0.followPresented()
        }
        await store.send(.localSeatsChanged(4)) {
            $0.localSeats = 4
            $0.followPresented()
        }
        await store.receive(.commandFailed(.setLocalSeats(4), .noCapacity))
        await store.receive(.delegate(.notice(.noFreeSeat)))
        #expect(commands.value == [.setLocalSeats(2), .setLocalSeats(4)])
    }

    @MainActor @Test func verifiedGuestsCanBeRememberedWithoutReplacingAnotherKey() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let holder = KakusanFixture.remembered(9, "Alex")
        var initial = hostState([.init(attemptID, 1, .active)])
        initial.guests[id: attemptID]?.expected = "Alex"
        let saved = KakusanFixture.remembered(2, "Alex")
        let store = sessionStore(initial, commands: commands) {
            $0.kakusan.remember = { _, _, replacing in
                replacing
                    ? .saved(saved)
                    : .nicknameTaken(holder)
            }
            $0.kakusan.peers = { [saved] }
        }
        await store.send(.startRemembering(attemptID)) {
            $0.destination = .remember(KakusanRememberFeature.State(
                subject: .verified(KakusanFixture.peer(2)),
                name: "Alex",
                normalised: "Alex"
            ))
            $0.followPresented()
        }
        await store.send(.destination(.presented(.remember(.view(.controlActivated(.save)))))) {
            $0.destination?.modify(\.remember) {
                $0.phase = .saving(zeroUUID(0))
                $0.controls.select(.save)
            }
            $0.followPresented()
        }
        await store.receive(.destination(.presented(.remember(.saved(
            zeroUUID(0),
            .nicknameTaken(holder)
        ))))) {
            $0.destination?.modify(\.remember) {
                $0.phase = .conflict(holder)
            }
            $0.destination?.modify(\.remember) {
                $0.controls.show([[.name], [.cancel, .replace, .save]], preferring: .replace)
            }
            $0.followPresented()
        }
        await store.send(.destination(.presented(.remember(.view(.controlActivated(.replace)))))) {
            $0.destination?.modify(\.remember) {
                $0.controls.select(.replace)
            }
            $0.destination?.modify(\.remember) {
                $0.phase = .saving(zeroUUID(1))
            }
            $0.followPresented()
        }
        await store.receive(.destination(.presented(.remember(.saved(zeroUUID(1), .saved(saved))))))
        await store.receive(.destination(.presented(.remember(.delegate(.finished(saved)))))) {
            $0.destination = nil
            $0.guests[id: attemptID]?.recognition = .recognised(saved)
            $0.followPresented()
        }
        await store.receive(.peersLoaded([saved])) {
            $0.peers = [saved]
            $0.followPresented()
        }
    }
#endif
