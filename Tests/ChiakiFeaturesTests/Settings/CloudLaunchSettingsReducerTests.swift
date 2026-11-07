import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

@MainActor @Test func selectDatacenterAtLaunchLoadsAndPersistsThroughTheClient() async {
    let first = UUID(0)
    let second = UUID(1)
    let stored = LockIsolated(CloudDatacenterSettings())
    let store = TestStore(initialState: CloudLaunchSettingsReducer.State()) { CloudLaunchSettingsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.cloud.loadDatacenters = {
            stored.value
        }
        $0.cloud.setSelectAtLaunch = { enabled in
            stored.withValue { $0 = $0.selectingAtLaunch(enabled) }
            return stored.value
        }
    }
    #expect(store.state.displayedValue)
    await store.send(.setSelectAtLaunch(true))
    await store.send(.load) { $0.phase = .loading(first) }
    await store.receive(.loaded(first, CloudDatacenterSettings())) { $0.phase = .ready }
    await store.send(.setSelectAtLaunch(false)) { $0.phase = .saving(second, false) }
    #expect(!store.state.displayedValue)
    await store.receive(.saved(second, CloudDatacenterSettings().selectingAtLaunch(false))) {
        $0.selectsAtLaunch = false
        $0.phase = .ready
    }
    #expect(!stored.value.selectsAtLaunch)
    await store.send(.setSelectAtLaunch(false))
    #expect(String(localized: CloudLaunchSettingsReducer.title) == "Select datacenter at launch")
    #expect(
        String(localized: CloudLaunchSettingsReducer.detail) == "After the datacenters are measured, choose "
            + "one before the stream starts. The lowest ping is chosen automatically after 15 seconds."
    )
}

@MainActor @Test func selectDatacenterAtLaunchReportsASaveFailure() async {
    struct Failure: Error {}
    let store = TestStore(initialState: CloudLaunchSettingsReducer.State()) { CloudLaunchSettingsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.cloud.setSelectAtLaunch = { _ in
            throw Failure()
        }
    }
    await store.send(.load) { $0.phase = .loading(UUID(0)) }
    await store.receive(.loaded(UUID(0), CloudDatacenterSettings())) { $0.phase = .ready }
    await store.send(.setSelectAtLaunch(false)) { $0.phase = .saving(UUID(1), false) }
    await store.receive(.failed(UUID(1))) {
        $0.phase = .failed(.settingsNetworkCloudLaunchFailed)
    }
    #expect(store.state.displayedValue)
}
