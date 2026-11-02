#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiModels
    import ChiakiTestSupport
    import Foundation
    import Testing
    import ComposableArchitecture
    @testable import ChiakiFeatures

    private let session = UUID(uuidString: "00000000-0000-0000-0000-00000000B0B0")!

    private func phaseState(_ phase: KakusanGuestPhase) -> KakusanGuestFeature.State {
        var state = KakusanGuestFeature.State()
        state.join.phase = phase
        state.host = .proven(KakusanFixture.peer(1))
        return state
    }

    @MainActor @Test func invalidOrExpiredInvitationsStayOnThePasteScreen() async {
        let previews = LockIsolated(0)
        var initial = KakusanGuestFeature.State()
        initial.join.phase = .entering(nil)
        let store = guestStore(initial) {
            $0.kakusan.preview = { _ in
                previews.withValue { $0 += 1 }
                return previews.value == 1
                    ? .failure(.version)
                    : .success(KakusanFixture.preview(expiresIn: 0))
            }
        }
        await store.send(.submitInvitation("Here you go RCP1:abc")) {
            $0.join.phase = .entering(.invalidBlock)
            $0.followPhase()
        }
        await store.send(.submitInvitation(KakusanFixture.invitation.text)) {
            $0.join.phase = .previewing(guestUUID(1))
            $0.followPhase()
        }
        await store.receive(.previewResult(guestUUID(1), KakusanFixture.invitation, .failure(.version))) {
            $0.join.phase = .entering(.version)
            $0.followPhase()
        }
        await store.send(.submitInvitation(KakusanFixture.invitation.text)) {
            $0.join.phase = .previewing(guestUUID(2))
            $0.followPhase()
        }
        await store.receive(.previewResult(
            guestUUID(2),
            KakusanFixture.invitation,
            .success(KakusanFixture.preview(expiresIn: 0))
        )) {
            $0.join.phase = .entering(.expired)
            $0.followPhase()
        }
        #expect(previews.value == 2)
    }

    @MainActor @Test func wrongGuestCodeEndsTheSessionAndStopsIt() async {
        let stops = LockIsolated(0)
        let initial = phaseState(.verifying(
            session,
            KakusanVerification(ownCode: KakusanFixture.code("7306"))
        ))
        let store = guestStore(initial, stops: stops) {
            $0.kakusan.enterCode = { _ in .rejected(.pairingFailed) }
        }
        await store.send(.submitCode("0000")) {
            $0.join.phase = .verifying(session, KakusanVerification(
                ownCode: KakusanFixture.code("7306"), entry: .submitting(guestUUID(0))
            ))
            $0.followPhase()
        }
        await store.receive(.codeResult(session, operation: guestUUID(0), .rejected(.pairingFailed))) {
            $0.join.phase = .ended(.failed(.pairingFailed))
            $0.followPhase()
        }
        #expect(stops.value == 1)
        #expect(KakusanGuestOutcome.failed(.pairingFailed).title == "This invitation is closed")
        await store.send(.back) {
            $0.join.phase = .entering(nil)
            $0.host = .unknown
            $0.followPhase()
        }
    }

    @MainActor @Test func noDirectPathAndNoCapacityEndTheJoin() async {
        for (phase, error) in [
            (KakusanGuestPhase.connecting(session), KakusanError.noPath),
            (.admitting(session), .noCapacity)
        ] {
            let stops = LockIsolated(0)
            let store = guestStore(phaseState(phase), stops: stops)
            let change = KakusanStateChange(state: .closed, error: error)
            await store.send(.event(session, .stateChanged(change))) {
                $0.join.phase = .ended(.failed(error))
                if error == .noCapacity {
                    $0.verifiedHost = nil
                }
                $0.followPhase()
            }
            #expect(stops.value == 1)
            await store.send(.leave) {
                $0.join.phase = .idle
                $0.host = .unknown
                $0.followPhase()
            }
        }
    }

    @MainActor @Test func invitationExpiryWhileWaitingForTheHostEndsTheJoin() async {
        let clock = TestClock()
        let stops = LockIsolated(0)
        var initial = phaseState(.disclosureAccepted(guestSummary))
        initial.recognition = .unknown
        let store = guestStore(initial, clock: clock, stops: stops)
        await store.send(.createReply) {
            $0.join.phase = .preparingReply(guestUUID(0), guestSummary)
            $0.followPhase()
        }
        await store.send(.event(guestUUID(0), .replyReady(KakusanFixture.reply))) {
            $0.join.phase = .waitingForHost(guestUUID(0), reply: KakusanFixture.reply, guestSummary)
            $0.followPhase()
        }
        await clock.advance(by: .seconds(599))
        await clock.advance(by: .seconds(1))
        await store.receive(.expired(guestUUID(0))) {
            $0.join.phase = .ended(.failed(.expired))
            $0.followPhase()
        }
        #expect(stops.value == 1)
    }

    @MainActor @Test func missingFirstFrameTimesOut() async {
        let clock = TestClock()
        let initial = phaseState(.streaming(session, KakusanGuestStream(seat: 2, video: .awaitingStream)))
        let store = guestStore(initial, clock: clock)
        await store.send(.event(session, .streamReady(fps: 30))) {
            $0.join.phase = .streaming(session, KakusanGuestStream(seat: 2, video: .awaitingFrame(fps: 30)))
            $0.streamMenu = StreamMenuReducer.State(context: .guest)
            $0.followPhase()
        }
        await clock.advance(by: KakusanGuestFeature.firstFrameDeadline)
        await store.receive(.firstFrameTimedOut(session)) {
            $0.join.phase = .ended(.failed(.timeout))
            $0.streamMenu = nil
            $0.followPhase()
        }
    }

    @MainActor @Test func hostRemovalSourceEndAndPlaybackFailuresGetLabels() async {
        let cases: [(KakusanGuestAction, KakusanGuestOutcome)] = [
            (.event(session, .stateChanged(KakusanStateChange(state: .closed, reason: .user, byPeer: true))),
             .closed(.user, byPeer: true)),
            (.event(session, .streamStopped), .closed(.source, byPeer: true)),
            (.playFailed(session, .codec), .failed(.codec)),
            (.playEnded(session), .closed(.source, byPeer: true))
        ]
        for (action, outcome) in cases {
            var initial = phaseState(.streaming(
                session,
                KakusanGuestStream(seat: 2, video: .playing(fps: 60))
            ))
            initial.streamMenu = StreamMenuReducer.State(context: .guest)
            let store = guestStore(initial)
            await store.send(action) {
                $0.join.phase = .ended(outcome)
                $0.streamMenu = nil
                $0.followPhase()
            }
            #expect(!outcome.label.isEmpty)
        }
        #expect(KakusanGuestOutcome.closed(.user, byPeer: true).label == "The host removed you")
        #expect(KakusanGuestOutcome.closed(.source, byPeer: true).title == "The game ended")
    }

    @MainActor @Test func eventsFromAnotherSessionAreIgnored() async {
        let store = guestStore(phaseState(.connecting(session)))
        let stale = UUID()
        await store.send(.event(stale, .stateChanged(KakusanStateChange(state: .closed, error: .noPath))))
        await store.send(.event(stale, .codeReady(KakusanFixture.code("1111"))))
        await store.send(.playFailed(stale, .internal))
        await store.send(.expired(stale))
        await store.send(.stopped(stale))
        await store.send(.firstFrameTimedOut(session))
        #expect(store.state.join.phase == .connecting(session))
    }

    @MainActor @Test func verifiedHostsCanBeRemembered() async {
        let saved = KakusanFixture.remembered(1, "Sam")
        var initial = phaseState(.admitting(session))
        initial.verifiedHost = KakusanFixture.peer(1)
        initial.recognition = .unknown
        let store = guestStore(initial) {
            $0.kakusan.remember = { _, _, _ in .saved(saved) }
        }
        await store.send(.startRemembering) {
            $0.remember = KakusanRememberFeature.State(subject: .verified(KakusanFixture.peer(1)))
            $0.followPhase()
        }
        await store.send(.remember(.presented(.view(.controlActivated(.save))))) {
            $0.remember?.controls.select(.save)
            $0.followPhase()
        }
        await store.send(.remember(.presented(.binding(.set(\.name, "Sam"))))) {
            $0.remember?.name = "Sam"
            $0.remember?.normalised = "Sam"
            $0.followPhase()
        }
        await store.send(.remember(.presented(.view(.controlActivated(.save))))) {
            $0.remember?.phase = .saving(guestUUID(0))
            $0.followPhase()
        }
        await store.receive(.remember(.presented(.saved(guestUUID(0), .saved(saved)))))
        await store.receive(.remember(.presented(.delegate(.finished(saved))))) {
            $0.remember = nil
            $0.recognition = .recognised(saved)
            $0.followPhase()
        }
        await store.send(.startRemembering)
    }

    @MainActor @Test func aClaimedHostNameLastsOnlyUntilTheHostIsProven() {
        var state = KakusanGuestFeature.State()
        #expect(state.hostName == nil)
        state.host = .claimed(name: "Sam")
        #expect(state.hostName == "Sam")
        #expect(state.hostPeer == nil)
        state.host = .proven(KakusanFixture.peer(1))
        #expect(state.hostName == nil)
        #expect(state.hostPeer == KakusanFixture.peer(1))
        state.recognition = .recognised(KakusanFixture.remembered(1, "Pat"))
        #expect(state.hostName == "Pat")
    }

    typealias KakusanGuestAction = KakusanGuestFeature.Action
#endif
