#if CHIAKI_KAKUSAN
    @testable import ChiakiModels
    import ChiakiTestSupport
    import PlatformUI
    import SwiftUI
    import Testing
    import ComposableArchitecture
    @testable import ChiakiFeatures

    private let renderedGuest = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!

    @MainActor private func hostStore(
        _ stage: KakusanHostStage,
        configure: (inout KakusanHostFeature.State) -> Void = { _ in }
    ) -> StoreOf<KakusanHostFeature> {
        var state = KakusanHostFeature.State()
        state.guests = [KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
            renderedGuest,
            through: stage
        ))]
        state.destination = .invite(KakusanInviteFeature.State(guest: renderedGuest))
        state.seats = KakusanSeatSnapshot(capacity: 4, local: 2, remote: 0, reserved: 0)
        configure(&state)
        state.followPresented()
        return Store(initialState: state) {
            KakusanHostFeature()
        } withDependencies: {
            $0.platform.offerFile = { _, _, _ in
            }
        }
    }

    @MainActor private func guestStore(_ phase: KakusanGuestPhase) -> StoreOf<KakusanGuestFeature> {
        var state = KakusanGuestFeature.State()
        state.join.phase = phase
        state.host = .proven(KakusanFixture.peer(1))
        state.code = "73"
        state.followPhase()
        return Store(initialState: state) {
            KakusanGuestFeature()
        } withDependencies: {
            $0.platform.offerFile = { _, _, _ in
            }
        }
    }

    @MainActor private func guestCard(_ store: StoreOf<KakusanGuestFeature>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            KakusanGuestCard(store: store)
        }
        .padding(30)
        .frame(width: 580)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private let summary = KakusanInvitationSummary(
        invitation: KakusanFixture.invitation,
        preview: KakusanInvitationPreview(
            hostHint: KakusanFixture.hint(1),
            claimedHostName: nil,
            capacity: 4,
            expiresAt: Date().addingTimeInterval(540)
        )
    )

    extension MenuFocusTests {
        @Test(arguments: [false, true])
        func kakusanHostOverlaysRender(dark: Bool) async throws {
            let screens: [(String, StoreOf<KakusanHostFeature>)] = [
                ("host-invitation", hostStore(.rejectedReply) { state in
                    state.peers = [
                        KakusanFixture.remembered(2, "Alex"),
                        KakusanFixture.remembered(5, "Sam")
                    ]
                }),
                ("host-connecting-changed", hostStore(.connecting) { state in
                    state.guests[id: renderedGuest]?.recognition = .changedKey(KakusanFixture.remembered(
                        9,
                        "Alex"
                    ))
                }),
                ("host-verification", hostStore(.verifying) { state in
                    state.guests[id: renderedGuest]?.recognition = .recognised(KakusanFixture.remembered(
                        2,
                        "Alex"
                    ))
                }),
                ("host-no-path", hostStore(.endedNoPath)),
                ("host-preparing", hostStore(.preparing))
            ]
            for (name, store) in screens {
                try await KakusanRender(name: name, dark: dark)
                    .render(KakusanHostView(store: store))
                    .expect(above: 0.0008, name)
            }
        }

        @Test(arguments: [false, true])
        func kakusanPlayersPanelRendersRemoteSeats(dark: Bool) async throws {
            var couch = CouchReducer.State()
            couch.begin(.ps5, hostAccount: UUID())
            let remote = CouchRemoteInput(guest: KakusanFixture.guest(1), name: "Alex")
            _ = couch.seats.claimRemote(remote)
            _ = couch.seats.chooseAccount(
                AccountProfile(
                    id: UUID(),
                    name: "Mika",
                    method: .npsso,
                    accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(4))
                ),
                forRemote: remote.guest
            )
            _ = couch.seats.seatRemote(remote, at: 2)
            _ = couch.seats.apply(.confirmed(pad: 2, color: 0x3bc77a))
            couch.seats.heldForRemote = 1
            let host = hostStore(.active) { state in
                state.destination = nil
                state.guests[id: renderedGuest]?.recognition = .recognised(KakusanFixture.remembered(
                    2,
                    "Alex"
                ))
                let pending = UUID()
                state.guests.append(KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
                    pending,
                    guest: 4,
                    through: .invitation
                )))
            }
            let panel = StreamMenuPanelContent(
                panel: .players,
                configuration: .constant(StreamTuningConfiguration()),
                statistics: RenderStatistics(),
                diagnosticsLevel: .constant(.off),
                diagnosticsGlass: .constant(.regular),
                diagnosticsLayout: .constant(.sheet),
                videoAnalysis: .constant(.off),
                troubleshootTopic: .constant(.wifi),
                frameGenerationEligible: false,
                stopTitle: "Disconnect",
                stop: {},
                couch: Store(initialState: couch) { CouchReducer() },
                kakusan: host
            )
            .frame(maxWidth: 700)
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            let capture = try await KakusanRender(name: "players-panel", dark: dark).render(panel)
            #expect(capture.coverage > 0.003, "\(capture.coverage)")
        }

        @Test(arguments: [false, true])
        func kakusanGuestScreensRender(dark: Bool) async throws {
            let session = UUID()
            var remembering = KakusanGuestFeature.State()
            remembering.remember = KakusanRememberFeature.State(
                subject: .verified(KakusanFixture.peer(1)),
                name: "Sam",
                normalised: "Sam"
            )
            let phases: [(String, KakusanGuestPhase)] = [
                ("guest-entering", .entering(.expired)),
                ("guest-preview", .disclosureAccepted(summary)),
                ("guest-reply", .waitingForHost(session, reply: KakusanFixture.reply, summary)),
                (
                    "guest-verification",
                    .verifying(session, KakusanVerification(ownCode: KakusanFixture.code("7306")))
                ),
                ("guest-seat", .admitting(session)),
                ("guest-ended", .ended(.failed(.pairingFailed)))
            ]
            for (name, phase) in phases {
                let capture = try await KakusanRender(name: name, dark: dark)
                    .render(guestCard(guestStore(phase)))
                #expect(capture.coverage > 0.0008, "\(name) rendered almost nothing \(capture.coverage)")
            }
            try await KakusanRender(name: "guest-screen", dark: dark)
                .render(KakusanGuestView(store: guestStore(.previewed(summary))))
                .expect(above: 0.005, "guest-screen")
            try await KakusanRender(name: "remember", dark: dark).render(KakusanRememberCard(
                store: Store(initialState: remembering.remember!) { KakusanRememberFeature() },
                title: "Remember this host"
            ))
            .expect(above: 0.0008, "remember")
        }

        @Test(arguments: [false, true])
        func kakusanSettingsRender(dark: Bool) async throws {
            var state = KakusanSettingsFeature.State()
            state.identity = .ready(KakusanIdentity(
                publicKey: KakusanFixture.key(1),
                fingerprint: KakusanFixture.fingerprint(1)
            ))
            let alex = KakusanFixture.remembered(2, "Alex")
            let sam = KakusanFixture.remembered(3, "Sam")
            state.peers = .ready([alex, sam, KakusanFixture.remembered(4, "Rin")])
            var rename = KakusanRememberFeature.State(
                subject: .remembered(sam),
                name: "Alex",
                normalised: "Alex"
            )
            rename.phase = .conflict(alex)
            state.rename = rename
            state.forget = .confirming(KakusanFixture.remembered(4, "Rin"))
            state.stunDraft = "stun.l.google.com:19302\nnot a server"
            state.stun = .invalid
            state.tuningDraft[.queueAgeMaximumMs] = "5000"
            state.tuningDraft[.queuePackets] = ""
            state.tuning = .invalid
            let view = KakusanSettingsView(store: Store(initialState: state) { KakusanSettingsFeature() })
                .frame(width: 720)
                .padding(28)
            try await KakusanRender(name: "settings", dark: dark)
                .render(view, size: CGSize(width: 1320, height: 1400))
                .expect(above: 0.0008, "settings")
        }
    }
#endif
