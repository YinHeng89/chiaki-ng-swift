#if CHIAKI_KAKUSAN
    @testable import ChiakiModels
    import PlatformUI
    import ComposableArchitecture
    import SwiftUI
    import Testing
    @testable import ChiakiFeatures
    import MenuFocus
    import ChiakiTestSupport

    extension MenuFocusTests {
        @Test func backWhileJoiningAsksBeforeLeavingTheGame() async {
            var state = KakusanGuestFeature.State()
            state.join.phase = .connecting(UUID())
            state.followPhase()
            let leaves = LockIsolated(0)
            let store: StoreOf<KakusanGuestFeature> = Store(initialState: state) {
                Reduce<KakusanGuestFeature.State, KakusanGuestFeature.Action> { _, action in
                    if case .view(.leaveConfirmed) = action {
                        leaves.withValue { $0 += 1 }
                    }
                    return .none
                }
                KakusanGuestFeature()
            } withDependencies: {
                $0.kakusan.stopGuest = {
                }
            }
            let harness = MenuFocusHarness(width: 1000, height: 820) { _ in
                MenuFocusHostingView(rootView: KakusanGuestView(store: store))
            }
            defer {
                harness.close()
            }
            await harness.open()
            await harness.pause(300)
            await harness.send(.back)
            await harness.pause(300)
            #expect(leaves.value == 0)
            #expect(testNavigator.inputGate.isPrompting)
            await harness.send(.confirm)
            await harness.pause(300)
            #expect(leaves.value == 0)
            #expect(!testNavigator.inputGate.isPrompting)
            await harness.send(.back)
            await harness.pause(300)
            await harness.send([MenuCommand.right, .confirm])
            await harness.pause(300)
            #expect(leaves.value == 1)
        }
    }
#endif
