@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import MenuFocus
import SwiftUI
import Testing

extension MenuFocusTests {
    @Test func theNatTypeCheckIsAFocusStopThatConfirmRuns() async {
        let store = Store(initialState: NatTypeFeature.State()) {
            NatTypeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.network = NetworkClient(natType: { () throws(NatTypeFailure) in
                .type3
            })
        }
        let harness = MenuFocusHarness(width: 600, height: 300) { _ in
            MenuFocusHostingView(rootView: NatTypeSettingsView(store: store).padding())
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.send(.down)
        await harness.pause(150)
        #expect(harness.focusedFrame != .zero)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.check == .found(.type3)
        }
        #expect(store.check == .found(.type3))
        #expect(String(localized: NatTypeSettingsView.detail(store.check)).contains("strict router"))
    }
}
