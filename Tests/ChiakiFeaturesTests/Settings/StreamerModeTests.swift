import ChiakiModels
import ChiakiDiagnostics
@testable import ChiakiFeatures
import ChiakiClients
import ComposableArchitecture
import Foundation
import Testing
import DesignSystem

@MainActor @Test func streamerModeDefaultsOffAndTurnsOnOnlyAfterSettingsSave() async {
    let id = UUID()
    var initial = SettingsFeature.State()
    initial.logging.setting = .ready(saved: .defaults)
    let store = TestStore(initialState: initial) {
        SettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.settings = .inMemory()
    }
    #expect(!store.state.logSettings.streamerMode)
    var expected = LogSettings.defaults
    expected.streamerMode = true
    await store.send(.logging(.binding(.set(\.draft, expected)))) {
        $0.logging.draft = expected
        $0.logging.setting = .saving(OperationID(uuid: id), saved: .defaults, draft: expected)
    }
    #expect(!store.state.logSettings.streamerMode)
    await store.receive(.logging(.saved(OperationID(uuid: id), .success(expected)))) {
        $0.logging.setting = .ready(saved: expected)
    }
    await store.receive(.logging(.delegate(.committed(expected))))
    #expect(store.state.logSettings.streamerMode)
}

@Test func savedLogSettingsWithoutStreamerModeLoadWithItOff() throws {
    let saved = Data(#"{"directory":"/tmp/logs","level":"info"}"#.utf8)
    let settings = try JSONDecoder().decode(LogSettings.self, from: saved)
    #expect(!settings.streamerMode)
    #expect(settings.redactIdentifiers)
}

@Test func streamerModeHidesIdentifiersOnlyWhileItIsOn() {
    #expect(StreamerMode.identifier("192.168.1.27", enabled: true) == "Hidden")
    #expect(StreamerMode.identifier("192.168.1.27", enabled: false) == "192.168.1.27")
}
