#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiModels
    import ChiakiTestSupport
    import Foundation
    import Testing
    import ComposableArchitecture
    @testable import ChiakiFeatures

    func guestUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    let guestSummary = KakusanInvitationSummary(
        invitation: KakusanFixture.invitation,
        preview: KakusanFixture.preview()
    )

    @MainActor
    func guestStore(
        _ state: KakusanGuestFeature.State = KakusanGuestFeature.State(),
        clock: TestClock<Duration> = TestClock(),
        stops: LockIsolated<Int> = LockIsolated(0),
        played: LockIsolated<[KakusanGuestConfiguration]> = LockIsolated([]),
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<KakusanGuestFeature> {
        TestStore(initialState: following(state)) {
            KakusanGuestFeature()
        } withDependencies: {
            $0.kakusan.nickname = KakusanFixture.nickname
            $0.kakusan.useStunServers = { _ in
                .success(())
            }
            $0.kakusan.disarm = {}
            $0.kakusan.recognize = { _, _ in
                .unknown
            }
            $0.kakusan.loadSettings = {
                KakusanSettings()
            }
            $0.uuid = .incrementing
            $0.date = .constant(KakusanFixture.now)
            $0.continuousClock = clock
            $0.kakusan.preview = { _ in .success(KakusanFixture.preview()) }
            $0.kakusan.playGuest = { _, configuration, _ in
                played.withValue { $0.append(configuration) }
                try await Task.never()
            }
            $0.kakusan.enterCode = { _ in .accepted }
            $0.kakusan.stopGuest = {
                stops.withValue { $0 += 1 }
            }
            $0.kakusan.loadSettings = { KakusanSettings(stunServers: []) }
            $0.kakusan.peers = { [] }
            configure(&$0)
        }
    }

    @MainActor
    func previewInvitation(_ store: TestStoreOf<KakusanGuestFeature>) async {
        await store.send(.open) {
            _ = $0.join.apply(.open)
            $0.joinID = guestUUID(0)
            $0.followPhase()
        }
        await store.send(.submitInvitation("\n RCP1:\(KakusanFixture.invitation.text.dropFirst(5))  ")) {
            _ = $0.join.apply(.preview(.request(guestUUID(1))))
            $0.followPhase()
        }
        await store.receive(.previewResult(
            guestUUID(1),
            KakusanFixture.invitation,
            .success(KakusanFixture.preview())
        )) {
            _ = $0.join.apply(.preview(.succeeded(guestUUID(1), guestSummary)))
            $0.host = .claimed(name: nil)
            $0.followPhase()
        }
    }

    @MainActor
    func startReply(_ store: TestStoreOf<KakusanGuestFeature>) async {
        await store.send(.createReply)
        await store.send(.setDisclosure(true)) {
            _ = $0.join.apply(.setDisclosure(true))
            $0.followPhase()
        }
        await store.send(.createReply) {
            _ = $0.join.apply(.start(guestUUID(2)))
            $0.followPhase()
        }
        await store.send(.event(guestUUID(2), .replyReady(KakusanFixture.reply))) {
            _ = $0.join.apply(.session(guestUUID(2), .replyReady(KakusanFixture.reply)))
            $0.followPhase()
        }
    }

    @MainActor
    private func verifyAsGuest(_ store: TestStoreOf<KakusanGuestFeature>) async {
        let session = guestUUID(2)
        await store.send(.event(session, .stateChanged(KakusanStateChange(state: .connecting)))) {
            _ = $0.join.apply(.session(session, .state(KakusanStateChange(state: .connecting))))
            $0.followPhase()
        }
        await store.send(.event(session, .hostIdentified(KakusanFixture.peer(1)))) {
            $0.host = .proven(KakusanFixture.peer(1))
            $0.followPhase()
        }
        await store.receive(.recognised(KakusanFixture.key(1), .unknown)) {
            $0.recognition = .unknown
            $0.followPhase()
        }
        await store.send(.event(session, .hostIdentified(KakusanFixture.peer(2))))
        await store.send(.event(session, .codeReady(KakusanFixture.code("7306")))) {
            _ = $0.join.apply(.session(session, .codeReady(KakusanFixture.code("7306"))))
            $0.followPhase()
        }
        await store.send(.submitCode("4821")) {
            _ = $0.join.apply(.session(session, .submitCode(guestUUID(3))))
            $0.followPhase()
        }
        await store.receive(.codeResult(session, operation: guestUUID(3), .accepted)) {
            _ = $0.join.apply(.session(session, .codeResult(guestUUID(3), nil)))
            $0.followPhase()
        }
        await store.send(.event(session, .stateChanged(KakusanStateChange(state: .admitting)))) {
            _ = $0.join.apply(.session(session, .state(KakusanStateChange(state: .admitting))))
            $0.verifiedHost = KakusanFixture.peer(1)
            $0.followPhase()
        }
    }

    @MainActor @Test func guestHappyPathStreamsAndReturnsToTheLibrary() async {
        let stops = LockIsolated(0)
        let played = LockIsolated<[KakusanGuestConfiguration]>([])
        let store = guestStore(stops: stops, played: played)
        let session = guestUUID(2)
        await previewInvitation(store)
        await startReply(store)
        await verifyAsGuest(store)
        await store.send(.event(session, .stateChanged(KakusanStateChange(state: .readyWait, seat: 3)))) {
            _ = $0.join.apply(.session(session, .state(KakusanStateChange(state: .readyWait, seat: 3))))
            $0.followPhase()
        }
        await store.send(.event(session, .stateChanged(KakusanStateChange(state: .active, seat: 3)))) {
            _ = $0.join.apply(.session(session, .state(KakusanStateChange(state: .active, seat: 3))))
            $0.streamMenu = StreamMenuReducer.State(context: .guest)
            $0.followPhase()
        }
        await store.send(.event(session, .streamReady(fps: 60))) {
            _ = $0.join.apply(.session(session, .streamReady(fps: 60)))
            $0.followPhase()
        }
        await store.send(.event(session, .firstFrame)) {
            _ = $0.join.apply(.session(session, .firstFrame))
            $0.followPhase()
        }
        #expect(store.state.playing)
        #expect(played.value == [KakusanGuestConfiguration(
            invitation: KakusanFixture.invitation
        )])
        await store.send(.leave) {
            _ = $0.join.apply(.leave)
            $0.streamMenu = nil
            $0.followPhase()
        }
        await store.receive(.stopped(session)) {
            _ = $0.join.apply(.session(session, .stopped))
            $0.host = .unknown
            $0.recognition = nil
            $0.verifiedHost = nil
            $0.followPhase()
        }
        #expect(stops.value == 1)
        #expect(!store.state.presented)
        await store.send(.event(session, .firstFrame))
        await store.send(.codeResult(session, operation: guestUUID(3), .rejected(.pairingFailed)))
        await store.send(.stopped(session))
    }

    @MainActor @Test func guestStreamMenuStopLeavesTheGame() async {
        let stops = LockIsolated(0)
        var initial = KakusanGuestFeature.State()
        initial.join.phase = .streaming(guestUUID(7), KakusanGuestStream(seat: 3, video: .playing(fps: 60)))
        initial.streamMenu = StreamMenuReducer.State(context: .guest)
        let store = guestStore(initial, stops: stops)
        await store.send(.streamMenu(.delegate(.stopRequested(.disconnect))))
        await store.receive(.leave) {
            $0.join.phase = .leaving(guestUUID(7))
            $0.streamMenu = nil
            $0.followPhase()
        }
        await store.receive(.stopped(guestUUID(7))) {
            $0.join.phase = .idle
            $0.followPhase()
        }
        #expect(stops.value == 1)
    }

    @MainActor @Test func theUsersOwnStunServersReachTheCoreBeforeTheGuestJoins() async {
        let order = LockIsolated<[String]>([])
        let store = guestStore {
            $0.kakusan.loadSettings = {
                KakusanSettings(stunServers: ["stun.example.com:3478"])
            }
            $0.kakusan.useStunServers = { servers in
                order.withValue { $0.append("stun " + servers.joined(separator: " ")) }
                return .success(())
            }
            $0.kakusan.playGuest = { _, _, _ in
                order.withValue { $0.append("play") }
                try await Task.never()
            }
        }
        await previewInvitation(store)
        await startReply(store)
        await settle {
            order.value.count == 2
        }
        #expect(order.value == ["stun stun.example.com:3478", "play"])
        await store.send(.leave) {
            _ = $0.join.apply(.leave)
            $0.followPhase()
        }
        await store.receive(.stopped(guestUUID(2))) {
            _ = $0.join.apply(.session(guestUUID(2), .stopped))
            $0.host = .unknown
            $0.followPhase()
        }
    }

    @MainActor @Test func withoutTheirOwnServersTheGuestHandsTheChoiceBackToTheCore() async {
        let chosen = LockIsolated<[[String]]>([])
        let store = guestStore {
            $0.kakusan.useStunServers = { servers in
                chosen.withValue { $0.append(servers) }
                return .success(())
            }
        }
        await previewInvitation(store)
        await startReply(store)
        await settle {
            !chosen.value.isEmpty
        }
        #expect(chosen.value == [[]])
        await store.send(.leave) {
            _ = $0.join.apply(.leave)
            $0.followPhase()
        }
        await store.receive(.stopped(guestUUID(2))) {
            _ = $0.join.apply(.session(guestUUID(2), .stopped))
            $0.host = .unknown
            $0.followPhase()
        }
    }

    @MainActor @Test func aRefusedServerListFailsTheJoinWithoutPlaying() async {
        let played = LockIsolated<[KakusanGuestConfiguration]>([])
        let store = guestStore(played: played) {
            $0.kakusan.useStunServers = { _ in
                .failure(.internal)
            }
        }
        await previewInvitation(store)
        await store.send(.setDisclosure(true)) {
            _ = $0.join.apply(.setDisclosure(true))
            $0.followPhase()
        }
        await store.send(.createReply) {
            _ = $0.join.apply(.start(guestUUID(2)))
            $0.followPhase()
        }
        await store.receive(.playFailed(guestUUID(2), .internal)) {
            _ = $0.join.apply(.session(guestUUID(2), .failed(.internal)))
            $0.followPhase()
        }
        #expect(played.value.isEmpty)
    }

    private func settle(until done: @Sendable () -> Bool) async {
        for _ in 0 ..< 1000 where !done() {
            await Task.yield()
        }
    }

    private func following(_ state: KakusanGuestFeature.State) -> KakusanGuestFeature.State {
        var state = state
        state.followPhase()
        return state
    }
#endif
