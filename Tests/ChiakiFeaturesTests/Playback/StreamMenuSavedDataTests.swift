@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func savedDataManagementIsOfferedForAPS4GameOnPSNowOnly() async {
    let opened = LockIsolated(0)
    var state = StreamMenuReducer.State(context: .cloud("psnow"))
    state.offersSavedData = true
    let store = TestStore(initialState: state) {
        StreamMenuReducer()
    } withDependencies: {
        $0.streamSession.openSavedData = {
            opened.withValue {
                $0 += 1
            }
            return true
        }
    }
    await store.send(.openSavedData)
    await store.finish()
    #expect(opened.value == 1)
    let refused = TestStore(initialState: StreamMenuReducer.State(context: .cloud("pscloud"))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.streamSession.openSavedData = {
            Issue.record("Only a PS4 game on PS Now offers saved data management")
            return false
        }
    }
    await refused.send(.openSavedData)
}
