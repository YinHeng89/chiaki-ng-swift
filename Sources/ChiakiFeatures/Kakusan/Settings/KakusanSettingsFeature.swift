import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The Remote players settings: this device's identity, the remembered devices, the user's own STUN servers and
/// the media tuning.
///
/// The servers and the tuning are stored together and each has its own `ChiakiModels/SaveablePhase`; only one
/// of them saves at a time. Renaming a remembered device presents ``KakusanRememberFeature``. Every load and
/// save carries the id of the operation that started it.
@Reducer
public struct KakusanSettingsFeature {
    /// Where a loaded value is.
    public enum Load<Value: Equatable & Sendable>: Equatable, Sendable {
        /// Not loaded.
        case idle
        /// The operation with the id is loading it.
        case loading(UUID)
        /// Loaded.
        case ready(Value)
        /// Loading failed.
        case failed
    }

    /// Where forgetting a remembered device is.
    public enum Forget: Equatable, Sendable {
        /// Asking whether to forget the device.
        case confirming(KakusanPeer)
        /// The operation with the id is forgetting it.
        case removing(KakusanPeer, UUID)
        /// Forgetting failed.
        case failed(KakusanPeer)
    }

    /// The settings' state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// This device's identity.
        public internal(set) var identity = Load<KakusanIdentity>.idle
        /// The remembered devices.
        public internal(set) var peers = Load<[KakusanPeer]>.idle
        /// The stored preferences.
        public internal(set) var configuration = KakusanSettings()
        /// The user's own STUN servers as typed.
        public var stunDraft = ""
        /// Where the servers are.
        public internal(set) var stun = SaveablePhase.idle
        /// The tuning as typed.
        public internal(set) var tuningDraft = KakusanTuningDraft()
        /// Where the tuning is.
        public internal(set) var tuning = SaveablePhase.idle
        /// Renaming a remembered device.
        @Presents public var rename: KakusanRememberFeature.State?
        /// Forgetting a remembered device.
        public internal(set) var forget: Forget?

        /// Creates unloaded settings.
        public init() {}

        /// Whether the typed servers differ from the stored ones.
        public var stunChanged: Bool {
            KakusanSettings.parse(stunDraft) != configuration.stunServers
        }

        /// Whether the typed tuning differs from the stored one.
        public var tuningChanged: Bool {
            tuningDraft != KakusanTuningDraft(configuration.tuning)
        }

        /// Whether the servers or the tuning are loading or saving.
        public var settingsBusy: Bool {
            stun.busy || tuning.busy
        }

        /// Whether the typed tuning cannot be saved now.
        public var tuningSaveBlocked: Bool {
            !tuningChanged || settingsBusy || tuning == .invalid
        }

        /// Whether restoring the default tuning would change nothing or cannot run now.
        public var tuningDefaultsBlocked: Bool {
            settingsBusy || (configuration.tuning == KakusanMediaTuning() && !tuningChanged)
        }

        /// Whether handing the servers back to the core would change nothing or cannot run now.
        public var stunDefaultsBlocked: Bool {
            settingsBusy || configuration.stunServers.isEmpty
        }

        /// The remembered device with a key.
        ///
        /// - Parameter key: The device's public key.
        /// - Returns: The device, if it is loaded.
        public func peer(_ key: KakusanPublicKey) -> KakusanPeer? {
            guard case .ready(let list) = peers else {
                return nil
            }
            return list.first { $0.publicKey == key }
        }
    }

    /// Everything the settings react to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to the typed servers.
        case binding(BindingAction<State>)
        /// Load everything.
        case load
        /// The identity was loaded.
        case identityLoaded(UUID, KakusanIdentity)
        /// The identity could not be loaded.
        case identityFailed(UUID)
        /// The remembered devices were loaded.
        case peersLoaded(UUID, [KakusanPeer])
        /// The remembered devices could not be loaded.
        case peersFailed(UUID)
        /// The preferences were loaded.
        case settingsLoaded(UUID, KakusanSettings)
        /// The preferences could not be loaded.
        case settingsFailed(UUID)
        /// Save the typed servers.
        case saveStun
        /// Hand the choice of servers back to the core.
        case restoreDefaultStun
        /// The servers were saved.
        case stunSaved(UUID, KakusanSettings)
        /// The servers could not be saved.
        case stunFailed(UUID)
        /// A tuning field was edited.
        case editTuning(KakusanMediaTuning.Field, String)
        /// Save the typed tuning.
        case saveTuning
        /// Restore the default tuning.
        case restoreDefaultTuning
        /// The tuning was saved.
        case tuningSaved(UUID, KakusanMediaTuning)
        /// The tuning could not be saved.
        case tuningFailed(UUID)
        /// Rename a remembered device.
        case startRename(KakusanPublicKey)
        /// The renaming card.
        case rename(PresentationAction<KakusanRememberFeature.Action>)
        /// Ask to forget a remembered device.
        case requestForget(KakusanPublicKey)
        /// Keep the device.
        case cancelForget
        /// Forget the device.
        case confirmForget
        /// The device was forgotten.
        case forgotten(UUID)
        /// The device could not be forgotten.
        case forgetFailed(UUID)
    }

    @Dependency(\.kakusan) private var kakusan
    @Dependency(\.uuid) private var uuid

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            reduce(&state, action)
        }
        .ifLet(\.$rename, action: \.rename) {
            KakusanRememberFeature()
        }
    }

    private func reduce(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .binding(\.stunDraft):
            if state.stun == .invalid {
                state.stun = .ready
            }
            return .none
        case .binding:
            return .none
        case .load, .identityLoaded, .identityFailed, .peersLoaded, .peersFailed, .settingsLoaded,
             .settingsFailed:
            return loading(action, in: &state)
        case .saveStun, .restoreDefaultStun, .stunSaved, .stunFailed, .editTuning, .saveTuning,
             .restoreDefaultTuning, .tuningSaved, .tuningFailed:
            return saving(action, in: &state)
        case .startRename, .rename, .requestForget, .cancelForget, .confirmForget, .forgotten, .forgetFailed:
            return devices(action, in: &state)
        }
    }
}

extension KakusanSettingsFeature {
    private func loading(_ action: Action, in state: inout State) -> Effect<Action> {
        switch action {
        case .load:
            return load(&state)
        case let .identityLoaded(id, value):
            if state.identity == .loading(id) {
                state.identity = .ready(value)
            }
            return .none
        case .identityFailed(let id):
            if state.identity == .loading(id) {
                state.identity = .failed
            }
            return .none
        case let .peersLoaded(id, list):
            if state.peers == .loading(id) {
                state.peers = .ready(list)
            }
            return .none
        case .peersFailed(let id):
            if state.peers == .loading(id) {
                state.peers = .failed
            }
            return .none
        case let .settingsLoaded(id, value):
            settingsLoaded(id, value, in: &state)
            return .none
        case .settingsFailed(let id):
            settingsFailed(id, in: &state)
            return .none
        default:
            return .none
        }
    }

    private func saving(_ action: Action, in state: inout State) -> Effect<Action> {
        switch action {
        case .saveStun:
            let proposed = KakusanSettings(
                stunServers: KakusanSettings.parse(state.stunDraft),
                tuning: state.configuration.tuning
            )
            return saveStun(proposed, in: &state)
        case .restoreDefaultStun:
            return saveStun(KakusanSettings(tuning: state.configuration.tuning), in: &state)
        case let .stunSaved(id, value):
            guard state.stun == .saving(id) else {
                return .none
            }
            state.configuration.stunServers = value.stunServers
            state.stunDraft = value.stunServers.joined(separator: "\n")
            state.stun = .ready
            return .none
        case .stunFailed(let id):
            if state.stun == .saving(id) {
                state.stun = .failed
            }
            return .none
        case let .editTuning(field, text):
            editTuning(field, text, in: &state)
            return .none
        case .saveTuning:
            guard !state.settingsBusy, state.tuningChanged else {
                return .none
            }
            guard let value = state.tuningDraft.tuning else {
                state.tuning = .invalid
                return .none
            }
            return writeTuning(value, in: &state)
        case .restoreDefaultTuning:
            return writeTuning(KakusanMediaTuning(), in: &state)
        case let .tuningSaved(id, value):
            guard state.tuning == .saving(id) else {
                return .none
            }
            state.configuration.tuning = value
            state.tuningDraft = KakusanTuningDraft(value)
            state.tuning = .ready
            return .none
        case .tuningFailed(let id):
            if state.tuning == .saving(id) {
                state.tuning = .failed
            }
            return .none
        default:
            return .none
        }
    }

    private func devices(_ action: Action, in state: inout State) -> Effect<Action> {
        switch action {
        case .startRename(let key):
            guard state.rename == nil, let peer = state.peer(key) else {
                return .none
            }
            state.rename = KakusanRememberFeature.State(
                subject: .remembered(peer),
                name: peer.nickname,
                normalised: kakusan.nickname(peer.nickname)
            )
            return .none
        case .rename(.presented(.delegate(.finished(let saved)))):
            state.rename = nil
            guard saved != nil else {
                return .none
            }
            return reloadPeers(&state)
        case .requestForget(let key):
            guard state.forget == nil, let peer = state.peer(key) else {
                return .none
            }
            state.forget = .confirming(peer)
            return .none
        case .cancelForget:
            if case .removing = state.forget {
                return .none
            }
            state.forget = nil
            return .none
        case .confirmForget:
            return confirmForget(&state)
        case .forgotten(let id):
            guard case .removing(_, id) = state.forget else {
                return .none
            }
            state.forget = nil
            return reloadPeers(&state)
        case .forgetFailed(let id):
            guard case .removing(let peer, id) = state.forget else {
                return .none
            }
            state.forget = .failed(peer)
            return .none
        default:
            return .none
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        let identityID = uuid()
        let settingsID = uuid()
        let peersID = uuid()
        state.identity = .loading(identityID)
        state.stun = .loading(settingsID)
        state.tuning = .loading(settingsID)
        state.peers = .loading(peersID)
        return .run { [kakusan] send in
            do {
                await send(.identityLoaded(identityID, try await kakusan.identity()))
            } catch {
                await send(.identityFailed(identityID))
            }
            do {
                await send(.settingsLoaded(settingsID, try await kakusan.loadSettings()))
            } catch {
                await send(.settingsFailed(settingsID))
            }
            do {
                await send(.peersLoaded(peersID, try await kakusan.peers()))
            } catch {
                await send(.peersFailed(peersID))
            }
        }
    }

    private func reloadPeers(_ state: inout State) -> Effect<Action> {
        let id = uuid()
        state.peers = .loading(id)
        return .run { [kakusan] send in
            do {
                await send(.peersLoaded(id, try await kakusan.peers()))
            } catch {
                await send(.peersFailed(id))
            }
        }
    }

    private func settingsLoaded(_ id: UUID, _ value: KakusanSettings, in state: inout State) {
        if state.stun == .loading(id) {
            state.configuration.stunServers = value.stunServers
            state.stunDraft = value.stunServers.joined(separator: "\n")
            state.stun = .ready
        }
        if state.tuning == .loading(id) {
            state.configuration.tuning = value.tuning
            state.tuningDraft = KakusanTuningDraft(value.tuning)
            state.tuning = .ready
        }
    }

    private func settingsFailed(_ id: UUID, in state: inout State) {
        if state.stun == .loading(id) {
            state.stun = .failed
        }
        if state.tuning == .loading(id) {
            state.tuning = .failed
        }
    }

    private func saveStun(_ proposed: KakusanSettings, in state: inout State) -> Effect<Action> {
        guard !state.settingsBusy else {
            return .none
        }
        guard let value = try? proposed.validated() else {
            state.stun = .invalid
            return .none
        }
        let id = uuid()
        state.stun = .saving(id)
        return .run { [kakusan] send in
            do {
                try await kakusan.saveSettings(value)
                await send(.stunSaved(id, value))
            } catch {
                await send(.stunFailed(id))
            }
        }
    }

    private func editTuning(_ field: KakusanMediaTuning.Field, _ text: String, in state: inout State) {
        guard !state.tuning.busy else {
            return
        }
        state.tuningDraft[field] = text
        if state.tuningDraft.tuning == nil {
            state.tuning = .invalid
        } else if state.tuning == .invalid {
            state.tuning = .ready
        }
    }

    private func writeTuning(_ value: KakusanMediaTuning, in state: inout State) -> Effect<Action> {
        guard !state.settingsBusy else {
            return .none
        }
        let tuning = value.clamped()
        let proposed = KakusanSettings(stunServers: state.configuration.stunServers, tuning: tuning)
        let id = uuid()
        state.tuning = .saving(id)
        return .run { [kakusan] send in
            do {
                try await kakusan.saveSettings(proposed)
                await send(.tuningSaved(id, tuning))
            } catch {
                await send(.tuningFailed(id))
            }
        }
    }

    private func confirmForget(_ state: inout State) -> Effect<Action> {
        let peer: KakusanPeer
        switch state.forget {
        case .confirming(let value), .failed(let value):
            peer = value
        case .removing, nil:
            return .none
        }
        let id = uuid()
        state.forget = .removing(peer, id)
        return .run { [kakusan] send in
            do {
                try await kakusan.forget(peer.publicKey)
                await send(.forgotten(id))
            } catch {
                await send(.forgetFailed(id))
            }
        }
    }
}
