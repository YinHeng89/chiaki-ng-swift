#if CHIAKI_KAKUSAN
    import ChiakiModels
    import ComposableArchitecture
    import PlatformUI
    import SwiftUI
    import Testing
    @testable import ChiakiFeatures
    import MenuFocus
    import ChiakiTestSupport

    private let modalAttempt = UUID(uuidString: "00000000-0000-0000-0000-00000000B0B0")!

    extension MenuFocusTests {
        private func invitationCard() -> (StoreOf<KakusanHostFeature>, MenuFocusHarness) {
            var state = KakusanHostFeature.State()
            state.guests = [KakusanHostFeature.Guest(attempt: KakusanFixture.attempt(
                modalAttempt,
                through: .invitation
            ))]
            state.destination = .invite(KakusanInviteFeature.State(guest: modalAttempt))
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
            return (store, harness)
        }

        private func invitationControls(_ store: StoreOf<KakusanHostFeature>) -> KakusanControlGrid? {
            guard case .invite(let invite) = store.destination else {
                return nil
            }
            return invite.controls
        }

        private func select(
            _ target: KakusanControl,
            in store: StoreOf<KakusanHostFeature>,
            harness: MenuFocusHarness
        ) async {
            for _ in 0 ..< 12 {
                guard let grid = invitationControls(store), let current = grid.selection, current != target,
                      let row = grid.rows.firstIndex(where: { $0.contains(target) }),
                      let currentRow = grid.rows.firstIndex(where: { $0.contains(current) }) else {
                    return
                }
                if row != currentRow {
                    await harness.send(
                        row < currentRow
                            ? .up
                            : .down
                    )
                } else {
                    let column = grid.rows[row].firstIndex(of: target) ?? 0
                    let currentColumn = grid.rows[row].firstIndex(of: current) ?? 0
                    await harness.send(
                        column < currentColumn
                            ? .left
                            : .right
                    )
                }
            }
        }

        @Test func backLeavesAKakusanModalFromEveryControl() async throws {
            let (probe, probeHarness) = invitationCard()
            await probeHarness.open()
            await probeHarness.pause(200)
            let controls = try #require(invitationControls(probe)).rows.flatMap(\.self)
            #expect(invitationControls(probe)?.selection == .copy)
            probeHarness.close()
            #expect(controls.count > 4)
            for control in controls {
                let (store, harness) = invitationCard()
                await harness.open()
                await harness.pause(200)
                await select(control, in: store, harness: harness)
                #expect(invitationControls(store)?.selection == control, "\(control)")
                await harness.send(.back)
                await harness.pause(100)
                #expect(store.presented == nil, "Back from \(control)")
                harness.close()
            }
        }
    }
#endif
