import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Loads and saves the Controls pane's configuration through the `ChiakiModels/PersistedSetting` machine.
///
/// A save that finishes while another draft waits starts saving that draft, and each finished save is reported
/// to the parent.
struct ControlsSettingsStorage: Reducer {
    /// The Controls pane's state.
    typealias State = ControlsSettingsFeature.State

    /// What the Controls pane reacts to.
    typealias Action = ControlsSettingsFeature.Action

    @Dependency(\.settings) private var settingsStore
    @Dependency(\.uuid) private var uuid

    /// Reacts to the load's and saves' answers and to retries.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .loaded(id, result):
                guard state.setting.finishLoad(id, result), let value = state.setting.value else {
                    return .none
                }
                state.draft = value
                return .none
            case let .saved(id, result):
                return saved(id, result, state: &state)
            case .retry:
                if case .loadFailed = state.setting {
                    return load(&state)
                }
                return commit(&state)
            default:
                return .none
            }
        }
    }

    /// Loads the saved configuration unless it is loaded or loading.
    ///
    /// - Parameter state: The Controls pane's state.
    /// - Returns: The effect that loads it, or none.
    func load(_ state: inout State) -> Effect<Action> {
        if case .ready = state.setting {
            return .none
        }
        let id = OperationID(uuid: uuid())
        guard state.setting.beginLoad(id) else {
            return .none
        }
        return .run { [settingsStore] send in
            do throws(PersistedSettingFailure) {
                await send(.loaded(id, .success(try await settingsStore.load(ControlsConfiguration.self))))
            } catch {
                await send(.loaded(id, .failure(error)))
            }
        }
    }

    /// Saves the draft when nothing is pending and it is a valid change, or holds it when it is invalid.
    ///
    /// - Parameter state: The Controls pane's state.
    /// - Returns: The effect that saves the draft, or none.
    func commit(_ state: inout State) -> Effect<Action> {
        guard state.mode == .idle else {
            return .none
        }
        switch state.setting.edit(state.draft) {
        case .refused:
            state.draft = state.setting.value ?? ControlsConfiguration()
            return .none
        case .unchanged, .queued:
            if state.notice == .invalidConfiguration {
                state.notice = .quiet
            }
            return .none
        case .invalid:
            state.notice = .invalidConfiguration
            return .none
        case let .save(value):
            if state.notice == .invalidConfiguration {
                state.notice = .quiet
            }
            return save(value, state: &state)
        }
    }

    private func save(_ value: ControlsConfiguration, state: inout State) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        state.setting.beginSave(id, value: value)
        return .run { [settingsStore] send in
            do throws(PersistedSettingFailure) {
                await send(.saved(id, .success(try await settingsStore.save(value))))
            } catch {
                await send(.saved(id, .failure(error)))
            }
        }
    }

    private func saved(
        _ id: OperationID,
        _ result: Result<ControlsConfiguration, PersistedSettingFailure>,
        state: inout State
    ) -> Effect<Action> {
        guard case let .saving(running, _, _) = state.setting, running == id else {
            return .none
        }
        let next = state.setting.finishSave(id, result)
        var effects: [Effect<Action>] = []
        switch result {
        case let .success(stored):
            effects.append(.send(.delegate(.committed(stored))))
        case .failure:
            effects.append(.send(.delegate(.commitFailed)))
        }
        if let next {
            effects.append(save(next, state: &state))
        }
        return .merge(effects)
    }
}
