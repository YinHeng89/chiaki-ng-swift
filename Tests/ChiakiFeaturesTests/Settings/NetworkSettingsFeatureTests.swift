@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func networkSettingsHoldInvalidSubnetsAndSaveThemOnceValid() async throws {
    let settings = SettingsClient.inMemory()
    let coreChecked = SettingsClient(read: settings.read) { value throws(PersistedSettingFailure) in
        if let discovery = value as? DiscoverySettings, discovery.subnets.contains("192.168.1.0/16") {
            throw .invalid
        }
        try await settings.write(value)
    }
    var initial = NetworkSettingsFeature.State()
    initial.discovery.setting = .ready(saved: DiscoverySettings())
    let store = TestStore(initialState: initial) {
        NetworkSettingsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = coreChecked
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.binding(.set(\.subnets, "192.168.1.0/16")))
    await store.receive(\.discovery.edit)
    await store.receive(\.discovery.saved)
    var invalid = DiscoverySettings()
    invalid.subnets = ["192.168.1.0/16"]
    #expect(store.state.discovery.setting == .saveFailed(
        saved: DiscoverySettings(),
        draft: invalid,
        failure: .invalid
    ))
    #expect(store.state.subnets == "192.168.1.0/16")
    #expect(store.state.subnetsRejected)
    await store.send(.appeared)
    #expect(store.state.subnets == "192.168.1.0/16")
    #expect(store.state.subnetsRejected)
    await store.send(.binding(.set(\.subnets, "192.168.2.42/24")))
    await store.receive(\.discovery.edit)
    await store.receive(\.discovery.delegate.committed)
    let stored = try await settings.load(DiscoverySettings.self)
    #expect(stored.subnets == ["192.168.2.42/24"])
    #expect(store.state.discovery.setting == .ready(saved: stored))
    #expect(!store.state.subnetsRejected)
}

@MainActor @Test func networkSubnetsTypedBeforeLoadingAreReplacedByTheStoredOnes() async {
    var stored = DiscoverySettings()
    stored.subnets = ["10.0.0.0/24"]
    let store = TestStore(initialState: NetworkSettingsFeature.State()) {
        NetworkSettingsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory([stored])
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.binding(.set(\.subnets, "192.168.2.0/24"))) {
        $0.subnets = ""
    }
    await store.send(.appeared)
    await store.receive(\.discovery.delegate.loaded) {
        $0.subnets = "10.0.0.0/24"
    }
}
