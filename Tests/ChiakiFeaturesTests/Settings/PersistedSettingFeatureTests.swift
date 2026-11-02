import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
protocol PersistedSettingCheck {
    func run<Value: PersistedSettingValue>(_ edited: Value) async throws
}

enum PersistedSettingPane: CaseIterable, Sendable {
    case picture
    case cloudPicture
    case sound
    case consolePower
    case internetConnection
    case discovery
    case logging
    case developer
    case interface

    @MainActor
    func run(_ check: some PersistedSettingCheck) async throws {
        switch self {
        case .picture:
            var value = PictureSettings()
            value.fullScreenStreams.toggle()
            try await check.run(value)
        case .cloudPicture:
            var value = CloudPictureSettings()
            value.reduceBanding.toggle()
            try await check.run(value)
        case .sound:
            var value = SoundSettings()
            value.startWithMicrophone.toggle()
            try await check.run(value)
        case .consolePower:
            var value = ConsolePowerSettings()
            value.restOnMacSleep.toggle()
            try await check.run(value)
        case .internetConnection:
            var value = InternetConnectionSettings()
            value.forcePortGuessing.toggle()
            try await check.run(value)
        case .discovery:
            var value = DiscoverySettings()
            value.unicastEnabled.toggle()
            try await check.run(value)
        case .logging:
            var value = LogSettings.defaults
            value.streamerMode.toggle()
            try await check.run(value)
        case .developer:
            var value = DeveloperSettings()
            value[negotiation: .psCloud].toggle()
            try await check.run(value)
        case .interface:
            try await check.run(InterfaceSettings(railEdge: .bottom))
        }
    }
}

@MainActor
@Suite struct PersistedSettingFeatureTests {
    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    struct AutosavesEveryEdit: PersistedSettingCheck {
        let operation: (Int) -> OperationID

        func run<Value: PersistedSettingValue>(_ edited: Value) async throws {
            let settings = SettingsClient.inMemory()
            let store = TestStore(initialState: PersistedSettingFeature<Value>.State()) {
                PersistedSettingFeature<Value>()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.settings = settings
            }
            let defaults = Value.settingKey.defaultValue
            let expected = try #require(try? edited.normalized().validated())
            await store.send(.appeared) {
                $0.setting = .loading(operation(0))
            }
            await store.receive(.loaded(operation(0), .success(defaults))) {
                $0.setting = .ready(saved: defaults)
            }
            await store.receive(.delegate(.loaded(defaults)))
            await store.send(.binding(.set(\.draft, edited))) {
                $0.draft = expected
                $0.setting = .saving(operation(1), saved: defaults, draft: expected)
            }
            await store.receive(.saved(operation(1), .success(expected))) {
                $0.setting = .ready(saved: expected)
            }
            await store.receive(.delegate(.committed(expected)))
            let stored = try await settings.load(Value.self)
            #expect(stored == expected)
        }
    }

    struct RefusesEditsBeforeTheStoredValueLoads: PersistedSettingCheck {
        let operation: (Int) -> OperationID

        func run<Value: PersistedSettingValue>(_ edited: Value) async throws {
            let writes = LockIsolated(0)
            let clock = TestClock()
            let defaults = Value.settingKey.defaultValue
            let store = TestStore(initialState: PersistedSettingFeature<Value>.State()) {
                PersistedSettingFeature<Value>()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.settings = SettingsClient(
                    read: { _ in
                        try? await clock.sleep(for: .seconds(1))
                        return edited
                    },
                    write: { _ in
                        writes.withValue {
                            $0 += 1
                        }
                    }
                )
            }
            await store.send(.binding(.set(\.draft, edited)))
            await store.send(.edit(edited))
            await store.send(.appeared) {
                $0.setting = .loading(operation(0))
            }
            await store.send(.binding(.set(\.draft, defaults)))
            await clock.advance(by: .seconds(1))
            let stored = try #require(try? edited.normalized().validated())
            await store.receive(.loaded(operation(0), .success(stored))) {
                $0.setting = .ready(saved: stored)
                $0.draft = stored
            }
            await store.receive(.delegate(.loaded(stored)))
            #expect(writes.value == 0)
        }
    }

    struct ReadOnlyUntilARetryLoads: PersistedSettingCheck {
        let operation: (Int) -> OperationID

        func run<Value: PersistedSettingValue>(_ edited: Value) async throws {
            let available = LockIsolated(false)
            let defaults = Value.settingKey.defaultValue
            let store = TestStore(initialState: PersistedSettingFeature<Value>.State()) {
                PersistedSettingFeature<Value>()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.settings = SettingsClient(
                    read: { type throws(PersistedSettingFailure) in
                        guard available.value else {
                            throw .unavailable
                        }
                        return type.defaultSetting
                    },
                    write: { _ in
                    }
                )
            }
            await store.send(.appeared) {
                $0.setting = .loading(operation(0))
            }
            await store.receive(.loaded(operation(0), .failure(.unavailable))) {
                $0.setting = .loadFailed(.unavailable)
            }
            await store.send(.binding(.set(\.draft, edited)))
            #expect(!store.state.isEditable)
            available.setValue(true)
            await store.send(.retry) {
                $0.setting = .loading(operation(1))
            }
            await store.receive(.loaded(operation(1), .success(defaults))) {
                $0.setting = .ready(saved: defaults)
            }
            await store.receive(.delegate(.loaded(defaults)))
        }
    }

    struct IgnoresStaleCompletions: PersistedSettingCheck {
        let operation: (Int) -> OperationID

        func run<Value: PersistedSettingValue>(_ edited: Value) async throws {
            let defaults = Value.settingKey.defaultValue
            var initial = PersistedSettingFeature<Value>.State()
            initial.setting = .ready(saved: defaults)
            let store = TestStore(initialState: initial) {
                PersistedSettingFeature<Value>()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.settings = .inMemory()
            }
            store.exhaustivity = .off(showSkippedAssertions: false)
            await store.send(.loaded(operation(9), .success(edited)))
            await store.send(.saved(operation(9), .success(edited)))
            #expect(store.state.setting == .ready(saved: defaults))
            #expect(store.state.draft == defaults)
        }
    }

    @Test(arguments: PersistedSettingPane.allCases)
    func everyPaneAutosavesEachValidEdit(_ pane: PersistedSettingPane) async throws {
        try await pane.run(AutosavesEveryEdit(operation: operation))
    }

    @Test(arguments: PersistedSettingPane.allCases)
    func noPaneSavesDefaultsOverStoredSettingsWhenEditedBeforeLoading(
        _ pane: PersistedSettingPane
    ) async throws {
        try await pane.run(RefusesEditsBeforeTheStoredValueLoads(operation: operation))
    }

    @Test(arguments: PersistedSettingPane.allCases)
    func everyPaneStaysReadOnlyAfterAFailedLoad(_ pane: PersistedSettingPane) async throws {
        try await pane.run(ReadOnlyUntilARetryLoads(operation: operation))
    }

    @Test(arguments: PersistedSettingPane.allCases)
    func everyPaneIgnoresStaleCompletions(_ pane: PersistedSettingPane) async throws {
        try await pane.run(IgnoresStaleCompletions(operation: operation))
    }
}
