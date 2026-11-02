#if CHIAKI_KAKUSAN
    import ChiakiClients
    @testable import ChiakiModels
    import PlatformUI
    import ComposableArchitecture
    import SwiftUI
    import Testing
    @testable import ChiakiFeatures
    import ChiakiTestSupport
    import MenuFocus

    private let focusAttempt = UUID(uuidString: "00000000-0000-0000-0000-00000000A0A0")!

    extension MenuFocusTests {
        @Test func controllerClosesAFailedInvitationFromTheHostOverlay() async {
            var state = KakusanHostFeature.State()
            state.guests = [KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
                focusAttempt,
                through: .endedNoPath
            ))]
            state.destination = .invite(KakusanInviteFeature.State(guest: focusAttempt))
            state.followPresented()
            let store = Store(initialState: state) {
                KakusanHostFeature()
            }
            let harness = MenuFocusHarness(width: 1000, height: 760) { _ in
                MenuFocusHostingView(rootView: KakusanHostView(store: store))
            }
            defer {
                harness.close()
            }
            await harness.open()
            await harness.send([.up, .confirm])
            await harness.settle()
            #expect(store.presented == nil)
            #expect(store.guests.isEmpty)
        }

        @Test func controllerAcceptsTheDisclosureBeforeCreatingAReply() async {
            var state = KakusanGuestFeature.State()
            state.join.phase = .previewed(guestSummary)
            state.followPhase()
            let played = LockIsolated(0)
            let store = Store(initialState: state) {
                KakusanGuestFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.date = .constant(KakusanFixture.now)
                $0.continuousClock = TestClock()
                $0.kakusan.loadSettings = {
                    KakusanSettings()
                }
                $0.kakusan.useStunServers = { _ in
                    .success(())
                }
                $0.kakusan.playGuest = { _, _, _ in
                    played.withValue { $0 += 1 }
                    try await Task.never()
                }
                $0.kakusan.stopGuest = {}
            }
            let harness = MenuFocusHarness(width: 1000, height: 820) { _ in
                MenuFocusHostingView(rootView: KakusanGuestView(store: store))
            }
            defer {
                store.send(.leave)
                harness.close()
            }
            await harness.open()
            await harness.send([.down, .confirm])
            await harness.settle()
            #expect(store.join.phase == .previewed(guestSummary))
            await harness.send([.up, .confirm])
            await harness.settle()
            #expect(store.join.phase == .disclosureAccepted(guestSummary))
            await harness.send([.down, .confirm])
            await harness.pause(100)
            #expect(store.join.session != nil)
            #expect(played.value == 1)
        }

        @Test func guestInvitationOpensTheOnScreenKeyboard() async {
            var state = KakusanGuestFeature.State()
            state.join.phase = .entering(nil)
            state.followPhase()
            let store = Store(initialState: state) {
                KakusanGuestFeature()
            }
            let harness = MenuFocusHarness(width: 1000, height: 820) { _ in
                MenuFocusHostingView(rootView: KakusanGuestView(store: store))
            }
            defer {
                harness.close()
            }
            await harness.open()
            await harness.send([.up, .confirm])
            await harness.pause(300)
            #expect(harness.window.attachedSheet != nil)
        }

        @Test func hostReplyOpensTheOnScreenKeyboard() async {
            var state = KakusanHostFeature.State()
            state.guests = [KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
                focusAttempt,
                through: .invitation
            ))]
            state.destination = .invite(KakusanInviteFeature.State(guest: focusAttempt))
            state.followPresented()
            let store = Store(initialState: state) {
                KakusanHostFeature()
            } withDependencies: {
                $0.platform.offerFile = { _, _, _ in
                }
            }
            let harness = MenuFocusHarness(width: 1000, height: 900) { _ in
                MenuFocusHostingView(rootView: KakusanHostView(store: store))
            }
            defer {
                harness.close()
            }
            await harness.open()
            await harness.send([.down, .down, .confirm])
            await harness.pause(300)
            #expect(harness.window.attachedSheet != nil)
        }
    }

    @MainActor @Test func playersPanelListsRemoteControlsInReadingOrder() {
        var couch = CouchReducer.State()
        couch.begin(.ps5, hostAccount: nil)
        let seated = CouchRemoteInput(guest: KakusanFixture.guest(1), name: "Alex")
        _ = couch.seats.claimRemote(seated)
        _ = couch.seats.seatRemote(seated, at: 2)
        var host = KakusanHostFeature.State()
        host.guests = [
            KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
                focusAttempt,
                guest: 1,
                through: .seating
            )),
            KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
                guestUUID(5),
                guest: 5,
                through: .invitation
            ))
        ]
        let controls = StreamPlayersPanel.controls(for: couch, kakusan: host)
        #expect(controls.contains(.playerRemove(2)))
        #expect(!controls.contains(.playerControls(2)))
        #expect(Array(controls.suffix(3)) == [
            .remote(.invite),
            .remote(.open(guestUUID(5))),
            .remote(.cancel(guestUUID(5)))
        ])
        host.hosting = .unavailable(.noPath)
        #expect(!StreamPlayersPanel.controls(for: couch, kakusan: host).contains(.remote(.invite)))
        #expect(StreamPlayersPanel.controls(for: couch, kakusan: nil) == StreamPlayersPanel
            .controls(for: couch))
    }

    @MainActor @Test func quittingLeavesAPresentedGuestSession() async {
        var guest = KakusanGuestFeature.State()
        guest.join.phase = .entering(nil)
        let state = RootFeature.State(route: .kakusanGuest(guest))
        let store = TestStore(initialState: state) {
            RootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.platform = PlatformClient(shutdown: {})
            $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
            $0.idleKakusanHosting()
        }
        store.exhaustivity = .off
        await store.send(.terminationRequested)
        await store.receive(.route(.kakusanGuest(.leave)))
        #expect(!store.state.guestPresented)
    }
#endif
