#if CHIAKI_KAKUSAN
    import ChiakiModels
    import PlatformUI
    import ComposableArchitecture
    import SwiftUI
    import Testing
    @testable import ChiakiFeatures
    import ChiakiTestSupport
    import MenuFocus

    extension MenuFocusTests {
        @Test func renameAndForgetKeepFocusOnTheRememberedDevice() async {
            let store = remotePlayersStore()
            let key = KakusanFixture.key(1)
            let harness = MenuFocusHarness(width: 900, height: 900) { _ in
                MenuFocusHostingView(rootView: ScrollView {
                    KakusanSettingsView(store: store)
                        .padding(24)
                })
            }
            defer {
                harness.close()
            }
            await harness.open()
            await harness.pause(300)
            store.send(.startRename(key))
            await harness.pause(300)
            #expect(AppKitMenuNavigator.acceptsTextInput(harness.window.firstResponder))
            store.send(.rename(.dismiss))
            await harness.pause(300)
            await harness.send(.confirm)
            await harness.pause(200)
            #expect(store.rename?.subject.publicKey == key)
            store.send(.rename(.dismiss))
            await harness.pause(300)
            store.send(.requestForget(key))
            await harness.pause(300)
            await harness.send(.confirm)
            await harness.pause(300)
            #expect(store.forget == nil)
            await harness.send(.confirm)
            await harness.pause(200)
            #expect(store.forget == .confirming(KakusanFixture.remembered(1, "Mika")))
        }

        @Test func backCancelsRenameAndForgetAndReturnsToTheirButtons() async {
            let store = remotePlayersStore()
            let key = KakusanFixture.key(1)
            let harness = MenuFocusHarness(width: 900, height: 900) { _ in
                MenuFocusHostingView(rootView: ScrollView {
                    KakusanSettingsView(store: store)
                        .padding(24)
                })
            }
            defer {
                harness.close()
            }
            await harness.open()
            await harness.pause(300)
            store.send(.startRename(key))
            await harness.pause(300)
            await harness.send(.back)
            await harness.pause(300)
            #expect(store.rename == nil)
            await harness.send(.confirm)
            await harness.pause(200)
            #expect(store.rename?.subject.publicKey == key)
            store.send(.rename(.dismiss))
            await harness.pause(300)
            store.send(.requestForget(key))
            await harness.pause(300)
            await harness.send(.back)
            await harness.pause(300)
            #expect(store.forget == nil)
            await harness.send(.confirm)
            await harness.pause(200)
            #expect(store.forget != nil)
        }
    }

    @MainActor
    private func remotePlayersStore() -> StoreOf<KakusanSettingsFeature> {
        var state = KakusanSettingsFeature.State()
        let peers = [KakusanFixture.remembered(1, "Mika"), KakusanFixture.remembered(2, "Rin")]
        state.peers = .ready(peers)
        return Store(initialState: state) {
            Reduce<KakusanSettingsFeature.State, KakusanSettingsFeature.Action> { state, action in
                switch action {
                case .startRename(let key):
                    if let peer = peers.first(where: { $0.publicKey == key }) {
                        state.rename = .init(
                            subject: .remembered(peer),
                            name: peer.nickname,
                            normalised: peer.nickname
                        )
                    }
                case .rename(.dismiss), .rename(.presented(.view(.backPressed))):
                    state.rename = nil
                case .requestForget(let key):
                    if let peer = peers.first(where: { $0.publicKey == key }) {
                        state.forget = .confirming(peer)
                    }
                case .cancelForget:
                    state.forget = nil
                default:
                    break
                }
                return .none
            }
        }
    }
#endif
