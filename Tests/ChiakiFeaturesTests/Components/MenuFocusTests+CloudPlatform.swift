import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test(arguments: [1000.0, 1100.0, 1300.0, 1600.0])
    func cloudPlatformChipsAreWalkedFromTheControlsRow(width: Double) async throws {
        let games = (0..<12).map { index in
            """
            {"productId":"game-\(index)","name":"Game \(index)","platform":"ps5",
            "category":"owned","isOwned":true,"plusCatalog":true,
            "streamServiceType":"pscloud","streamIdentifier":"game-\(index)"}
            """
        }.joined(separator: ",")
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[\(games)]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = fixedDatacenterStore(state)
        let harness = MenuFocusHarness(width: width, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(100)
        let filters = CloudLibraryFeature.State().filters.count
        await harness.send([.up] + Array(repeating: .right, count: filters + 2))
        let all = harness.window.firstResponder
        #expect(harness.focusedFrame.width > 30 && harness.focusedFrame.width < 120)
        await harness.send(.right)
        let ps5 = harness.window.firstResponder
        #expect(ps5 !== all)
        #expect(harness.focusedFrame.width > 30 && harness.focusedFrame.width < 120)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.platform == .ps5)
        await harness.send([.right, .right, .right])
        #expect(harness.window.firstResponder !== ps5)
        await harness.send([.left, .left, .left])
        #expect(harness.window.firstResponder === all)
        await harness.send(.left)
        await harness.pause(200)
        #expect(harness.window.firstResponder !== all)
        #expect(harness.focusedFrame.width < 60)
    }
}

@MainActor
private func fixedDatacenterStore(_ state: CloudLibraryFeature.State) -> StoreOf<CloudLibraryFeature> {
    Store(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.cloud.loadDatacenters = {
            CloudDatacenterSettings().selectingAtLaunch(false)
        }
    }
}
