import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Loads one `ChiakiModels/PersistedSettingValue` and saves every valid edit as it is made.
///
/// The workflow is the `ChiakiModels/PersistedSetting` machine. A view binds its controls to ``State/draft``;
/// every change is normalised, validated and saved through `ChiakiClients/SettingsClient`. Edits made
/// before the stored value has loaded are refused and the draft returns to what is shown, so defaults can never
/// overwrite stored settings. Each load and save is tagged with the `ChiakiModels/OperationID` that started
/// it.
@Reducer
public struct PersistedSettingFeature<Value: PersistedSettingValue> {
    /// One settings value and its workflow.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// Where the load and save workflow is.
        public internal(set) var setting: PersistedSetting<Value>

        /// The value the controls show and edit.
        public var draft: Value

        /// Starts with nothing loaded, showing the key's default.
        public init() {
            setting = .unloaded
            draft = Value.settingKey.defaultValue
        }

        /// Whether the controls accept edits.
        public var isEditable: Bool {
            setting.isLoaded
        }

        /// The value known to be stored, once loaded.
        public var saved: Value? {
            setting.saved
        }
    }

    /// Everything a settings pane reacts to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to a bound control.
        case binding(BindingAction<State>)

        /// The pane appeared; loads the stored value unless an edit is pending.
        case appeared

        /// Loads again after a failed load, or saves the held draft again after a failed save.
        case retry

        /// Replaces the whole draft, as a composing feature's intent does.
        case edit(Value)

        /// The result of a load.
        case loaded(OperationID, Result<Value, PersistedSettingFailure>)

        /// The result of a save.
        case saved(OperationID, Result<Value, PersistedSettingFailure>)

        /// What the parent is told.
        case delegate(Delegate)

        /// What a settings pane reports to its parent.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// The stored value was loaded.
            case loaded(Value)

            /// A value was stored.
            case committed(Value)
        }
    }

    @Dependency(\.settings) private var store
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.draft):
                return commit(state.draft, state: &state)
            case .binding, .delegate:
                return .none
            case .appeared:
                return load(state: &state)
            case .retry:
                if case .loadFailed = state.setting {
                    return load(state: &state)
                }
                return commit(state.draft, state: &state)
            case let .edit(value):
                return commit(value, state: &state)
            case let .loaded(id, result):
                guard state.setting.finishLoad(id, result), let value = state.setting.value else {
                    return .none
                }
                state.draft = value
                return .send(.delegate(.loaded(value)))
            case let .saved(id, result):
                let next = state.setting.finishSave(id, result)
                var effects: [Effect<Action>] = []
                if case let .success(stored) = result {
                    effects.append(.send(.delegate(.committed(stored))))
                }
                if let next {
                    effects.append(save(next, state: &state))
                }
                return .merge(effects)
            }
        }
    }

    private func load(state: inout State) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        guard state.setting.beginLoad(id) else {
            return .none
        }
        return .run { [store] send in
            do throws(PersistedSettingFailure) {
                let value = try await store.load(Value.self)
                await send(.loaded(id, .success(value)))
            } catch {
                await send(.loaded(id, .failure(error)))
            }
        }
    }

    private func commit(_ value: Value, state: inout State) -> Effect<Action> {
        switch state.setting.edit(value) {
        case .refused:
            state.draft = state.setting.value ?? Value.settingKey.defaultValue
            return .none
        case .unchanged:
            if let shown = state.setting.value {
                state.draft = shown
            }
            return .none
        case .queued, .invalid:
            state.draft = value.normalized()
            return .none
        case let .save(checked):
            state.draft = checked
            return save(checked, state: &state)
        }
    }

    private func save(_ value: Value, state: inout State) -> Effect<Action> {
        let id = OperationID(uuid: uuid())
        state.setting.beginSave(id, value: value)
        return .run { [store] send in
            do throws(PersistedSettingFailure) {
                let stored = try await store.save(value)
                await send(.saved(id, .success(stored)))
            } catch {
                await send(.saved(id, .failure(error)))
            }
        }
    }
}
