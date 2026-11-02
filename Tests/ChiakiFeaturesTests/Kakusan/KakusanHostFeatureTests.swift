#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiFeatures
    import ChiakiModels
    import ChiakiTestSupport
    import ComposableArchitecture
    import Foundation
    import Testing
    private let guestA = KakusanFixture.guest(1)
    private let alex = KakusanFixture.remembered(9, "Alex")

    @MainActor
    private func hostStore(
        _ state: KakusanHostFeature.State = KakusanHostFeature.State(),
        commands: LockIsolated<[KakusanHostCommand]>,
        peers: [KakusanPeer] = [],
        clock: TestClock<Duration> = TestClock(),
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
            $0.continuousClock = clock
            $0.kakusan.invite = { .success(guestA) }
            $0.kakusan.importReply = { _ in .success(guestA) }
            $0.kakusan.send = { command in
                commands.withValue { $0.append(command) }
                return .accepted
            }
            $0.kakusan.peers = { peers }
            $0.kakusan.recognize = { key, nickname in
                if let nickname,
                   let named = peers.first(where: { $0.nickname.lowercased() == nickname.lowercased() }) {
                    return named.publicKey == key
                        ? .recognised(named)
                        : .changedKey(named)
                }
                return peers.first { $0.publicKey == key }.map { .recognised($0) } ?? .unknown
            }
            configure(&$0)
        }
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    @MainActor
    private func phase(_ store: TestStoreOf<KakusanHostFeature>, _ id: UUID) -> KakusanHostPhase? {
        store.state.guests[id: id]?.attempt.phase
    }

    @MainActor
    private func invite(_ store: TestStoreOf<KakusanHostFeature>, peers: [KakusanPeer] = []) async {
        await store.send(.invite) {
            $0.guests = [KakusanHostFeature.Guest(attempt: KakusanHostAttempt(
                id: uuid(0),
                operation: uuid(1)
            ))]
            $0.destination = .invite(KakusanInviteFeature.State(guest: uuid(0)))
            $0.followPresented()
        }
        if peers.isEmpty {
            await store.receive(.peersLoaded(peers))
        } else {
            await store.receive(.peersLoaded(peers)) {
                $0.peers = peers
                $0.followPresented()
            }
        }
        var invited = KakusanHostAttempt(id: uuid(0), operation: uuid(1))
        _ = invited.apply(.invitation(.invited(uuid(1), guestA)))
        await store.receive(.inviteResult(uuid(0), operation: uuid(1), .success(guestA))) {
            $0.guests[id: uuid(0)]?.attempt = invited
            $0.followPresented()
        }
        await store.send(.event(.invitationReady(
            guestA,
            KakusanFixture.invitation,
            expiresAt: KakusanFixture.now + 600
        ))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.invitation(.ready(
                KakusanInvitation(block: KakusanFixture.invitation, expiresAt: KakusanFixture.now + 600)
            )))
            $0.followPresented()
        }
    }

    @MainActor
    private func connect(_ store: TestStoreOf<KakusanHostFeature>) async {
        await store.send(.submitReply(uuid(0), "  \(KakusanFixture.reply.text)\n")) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.reply(.submit(uuid(2))))
            $0.guests[id: uuid(0)]?.replyOperation = uuid(2)
            $0.followPresented()
        }
        await store.receive(.replyResult(uuid(0), operation: uuid(2), .success(guestA))) {
            $0.guests[id: uuid(0)]?.replyOperation = nil
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.reply(.imported(uuid(2))))
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.approval(.request(uuid(3))))
            $0.followPresented()
        }
        await store.receive(.approvalResult(uuid(0), operation: uuid(3), .accepted)) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.approval(.result(uuid(3), nil)))
            $0.followPresented()
        }
    }

    @MainActor
    private func verify(_ store: TestStoreOf<KakusanHostFeature>, recognition: KakusanRecognition) async {
        let peer = KakusanFixture.peer(2)
        await store.send(.event(.replyBound(guestA, peer.publicKey, peer.fingerprint))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.reply(.bound(peer)))
            $0.followPresented()
        }
        await store.receive(.recognised(uuid(0), peer.publicKey, recognition)) {
            $0.guests[id: uuid(0)]?.recognition = recognition
            $0.followPresented()
        }
        await store.send(.event(.stateChanged(guestA, KakusanStateChange(state: .connecting))))
        await store.send(.event(.codeReady(guestA, KakusanFixture.code("4821")))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.code(.ready(KakusanFixture.code("4821"))))
            $0.followPresented()
        }
        await store.send(.submitCode(uuid(0), "12"))
        await store.send(.submitCode(uuid(0), "7306")) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.code(.submit(uuid(4))))
            $0.followPresented()
        }
        await store.receive(.codeResult(uuid(0), operation: uuid(4), .accepted)) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.code(.result(uuid(4), nil)))
            $0.followPresented()
        }
    }

    @MainActor @Test func hostHappyPathSeatsAVerifiedGuest() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = hostStore(commands: commands)
        await invite(store)
        await store.send(.expect(uuid(0), "Alex")) {
            $0.guests[id: uuid(0)]?.expected = "Alex"
            $0.followPresented()
        }
        await connect(store)
        await verify(store, recognition: .unknown)
        let grant = KakusanFixture.grant
        let account = Data(repeating: 4, count: 8)
        let remote = KakusanRemotePlayer(guest: guestA, name: nil)
        await store.send(.event(.stateChanged(guestA, KakusanStateChange(state: .admitting)))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.state(KakusanStateChange(state: .admitting)))
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.seat(.joinRequested))
            $0.destination = nil
            $0.followPresented()
        }
        await store.receive(.delegate(.claimSeat(remote)))
        #expect(store.state.guests[id: uuid(0)]?.attempt.seat == nil)
        #expect(store.state.guests[id: uuid(0)]?.attempt.pad == nil)
        await store.send(.giveSeat(guestA, controllerType: 6, accountID: account))
        await store.send(.event(.consoleSeated(guestA, pad: 2))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.seat(.consoleJoined(pad: 2)))
            $0.followPresented()
        }
        await store.receive(.delegate(.showSeat(remote, pad: 2)))
        await store.send(.event(.stateChanged(guestA, KakusanFixture.seated(.readyWait)))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.state(KakusanFixture.seated(.readyWait)))
            $0.followPresented()
        }
        await store.send(.event(.stateChanged(guestA, KakusanFixture.seated(.active)))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.state(KakusanFixture.seated(.active)))
            $0.followPresented()
        }
        #expect(store.state.guests[id: uuid(0)]?.attempt.milestone == .seated)
        #expect(store.state.guests[id: uuid(0)]?.attempt.phase == .active(grant, pad: 2))
        #expect(commands.value == [
            .setTuning(KakusanMediaTuning()), .setLocalSeats(1),
            .enterCode(guestA, KakusanFixture.code("7306")),
            .giveSeat(guestA, preferred: nil, controllerType: 6, accountID: account)
        ])
        await store.send(.event(.stateChanged(
            guestA,
            KakusanStateChange(state: .closed, reason: .user, byPeer: true)
        ))) {
            $0.guests = []
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(guestA)))
        await store.receive(.delegate(.notice(.ended(name: nil, .closed(.user, byPeer: true)))))
    }

    @MainActor @Test func hostDoesNotRecogniseAChangedKeyForARememberedName() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let store = hostStore(commands: commands, peers: [alex])
        await invite(store, peers: [alex])
        await store.send(.expect(uuid(0), "Alex")) {
            $0.guests[id: uuid(0)]?.expected = "Alex"
            $0.followPresented()
        }
        await connect(store)
        await verify(store, recognition: .changedKey(alex))
        #expect(store.state.guests[id: uuid(0)]?.name == nil)
        await store.send(.event(.stateChanged(guestA, KakusanStateChange(state: .admitting)))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.state(KakusanStateChange(state: .admitting)))
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.seat(.joinRequested))
            $0.destination = nil
            $0.followPresented()
        }
        await store.receive(.delegate(.claimSeat(KakusanRemotePlayer(guest: guestA, name: nil))))
        await store.send(.cancel(uuid(0))) {
            $0.guests = []
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(guestA)))
    }

    @MainActor @Test func hostRecognisesARememberedKeyAfterVerification() async {
        let commands = LockIsolated<[KakusanHostCommand]>([])
        let known = KakusanFixture.remembered(2, "Alex")
        let store = hostStore(commands: commands, peers: [known])
        await invite(store, peers: [known])
        await connect(store)
        await verify(store, recognition: .recognised(known))
        await store.send(.event(.stateChanged(guestA, KakusanStateChange(state: .admitting)))) {
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.state(KakusanStateChange(state: .admitting)))
            _ = $0.guests[id: uuid(0)]?.attempt.apply(.seat(.joinRequested))
            $0.destination = nil
            $0.followPresented()
        }
        await store.receive(.delegate(.claimSeat(KakusanRemotePlayer(guest: guestA, name: "Alex"))))
        #expect(store.state.guests[id: uuid(0)]?.name == "Alex")
        await store.send(.cancel(uuid(0))) {
            $0.guests = []
            $0.followPresented()
        }
        await store.receive(.delegate(.releaseSeat(guestA)))
    }
#endif
