@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@Test func settingsShowEveryTabOnlyWithASignedInAccount() {
    var state = SettingsFeature.State()
    #expect(state.psnReach == .localOnly)
    #expect(!state.tabs.contains(.entitlements))
    #expect(!state.tabs.contains(.tokens))
    #expect(!state.tabs.contains(.accessibility))
    #expect(state.tabs.contains(.network))
    #expect(state.tabs.contains(.remotePlayers) == KakusanBuild.included)
    state.psnReach = .signedIn
    #expect(state.tabs == SettingsRoute.allCases.filter(\.isBuilt))
    #expect(state.tabs.contains(.accessibility))
}

@MainActor @Test func losingTheLastSignedInAccountLeavesAPSNOnlyTab() async {
    var state = SettingsFeature.State()
    state.psnReach = .signedIn
    state.route = .tokens
    let store = TestStore(initialState: state) {
        SettingsFeature()
    } withDependencies: {
        $0.logSettings = .testValue
        $0.controllers = .testValue
        $0.uuid = .incrementing
    }
    store.exhaustivity = .off
    await store.send(.psnReach(.localOnly)) {
        $0.psnReach = .localOnly
    }
    await store.receive(.select(.picture)) {
        $0.route = .picture
    }
}

@MainActor @Test func signingInKeepsTheCurrentTab() async {
    var state = SettingsFeature.State()
    state.route = .network
    let store = TestStore(initialState: state) {
        SettingsFeature()
    }
    await store.send(.psnReach(.signedIn)) {
        $0.psnReach = .signedIn
    }
}
