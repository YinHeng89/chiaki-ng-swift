import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// The Controls pane: bindings, presets, controller preferences and shortcuts, saved as they are made.
///
/// The saved configuration follows the `ChiakiModels/PersistedSetting` machine. Every intent edits
/// ``State/draft`` and then commits it: a valid draft is saved at once, an invalid one is held with
/// `ChiakiModels/ControlsNotice/invalidConfiguration` until a later edit makes it valid. While a binding
/// capture or a shortcut recording runs (`ControlsMode`), nothing is committed; the commit happens when it
/// ends. There is no Save or Discard; the latest binding change can be undone instead (``State/change``).
///
/// Every controller seen is remembered in the configuration, so the pane lists it with its bindings while it
/// is disconnected until it is forgotten.
@Reducer
public struct ControlsSettingsFeature {
    /// The pane's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The saved configuration's workflow.
        public internal(set) var setting = PersistedSetting<ControlsConfiguration>.unloaded

        /// The configuration the pane shows and edits.
        public var draft = ControlsConfiguration()

        /// What the pane is waiting for.
        public internal(set) var mode = ControlsMode.idle

        /// What the pane tells the user.
        public internal(set) var notice = ControlsNotice.quiet

        /// The connected controllers.
        public internal(set) var devices: [ControllerDevice] = []

        /// Whose bindings the pane shows and edits.
        public internal(set) var editing = ControlsEditTarget.keyboard

        /// The latest change that can still be undone.
        public internal(set) var change: ControlsChange?

        /// The controller listing that is running, if any.
        public internal(set) var inventoryAttempt: UUID?

        /// Whether the shown bindings fill the pane on their own screen, as the touch interface shows them.
        public internal(set) var showsMapping = false

        /// Creates the pane with nothing loaded.
        public init() {}

        /// Whether edits are accepted.
        public var isEditable: Bool {
            setting.isLoaded
        }

        /// The configuration known to be stored, or the defaults before it loads.
        public var configuration: ControlsConfiguration {
            setting.saved ?? ControlsConfiguration()
        }

        /// The binding capture that is running, if any.
        public var capture: ControlsCapture? {
            mode.capture
        }

        /// A controller by preference key: the connected one, or a remembered one standing in while it is
        /// disconnected.
        ///
        /// - Parameter key: The controller's preference key.
        /// - Returns: The controller, or `nil` when it is neither connected nor remembered.
        public func device(_ key: String) -> ControllerDevice? {
            devices.first { $0.preferenceKey == key } ?? draft.remembered[key]?.device(key: key)
        }

        /// The controller being edited, when the pane shows one.
        public var editingDevice: ControllerDevice? {
            guard case .controller(let key) = editing else {
                return nil
            }
            return device(key)
        }

        /// The controller a player's bindings are shown for: the first connected one.
        public var playerDevice: ControllerDevice? {
            devices.first { !$0.isKeyboard }
        }

        /// The preset the pane shows, adapted to the controller it is shown for.
        public var editingPreset: InputPreset {
            switch editing {
            case .keyboard:
                return draft.keyboardPreset
            case .controller(let key):
                let device = device(key)
                return draft.preset(
                    for: draft.controllers[key], touchpad: device?.touchpad ?? true,
                    gyro: device?.motion ?? true
                )
            case .player(let player):
                return draft.preset(
                    forPlayer: player, preferences: nil, touchpad: playerDevice?.touchpad ?? true,
                    gyro: playerDevice?.motion ?? true
                )
            }
        }

        /// The family whose drawing and button names the pane shows.
        public var editingFamily: ControllerFamily {
            switch editing {
            case .keyboard:
                .playStation
            case .controller:
                editingDevice?.family ?? .playStation
            case .player:
                playerDevice?.family ?? .playStation
            }
        }

        /// The button layout of the controller being edited.
        public var editingLayout: ButtonLayout {
            guard case .controller(let key) = editing else {
                return .position
            }
            return draft.controllers[key]?.buttonLayout ?? .position
        }

        /// Whether a real key or button press can be heard for the shown bindings, rather than only a tapped
        /// button.
        public var canListen: Bool {
            switch editing {
            case .keyboard:
                true
            case .controller(let key):
                isConnected(key)
            case .player:
                playerDevice != nil
            }
        }

        /// Whether a controller is connected now.
        ///
        /// - Parameter key: The controller's preference key.
        /// - Returns: `true` when it is connected.
        public func isConnected(_ key: String) -> Bool {
            devices.contains { $0.preferenceKey == key }
        }

        /// The keyboard followed by every remembered or connected controller, connected ones first and then by
        /// when they were last seen.
        public var listedDevices: [ControllerDevice] {
            var connected: [ControllerDevice] = []
            for device in devices where !device.isKeyboard
                && !connected.contains(where: { $0.preferenceKey == device.preferenceKey }) {
                connected.append(device)
            }
            let away = draft.remembered
                .filter { entry in
                    !connected.contains { $0.preferenceKey == entry.key }
                }
                .sorted {
                    $0.value.lastSeen > $1.value.lastSeen
                }
                .map {
                    $0.value.device(key: $0.key)
                }
            return [.keyboard] + connected + away
        }

        /// The shortcut recording that is running, if any.
        public var shortcutCapture: UUID? {
            mode.shortcutRecording
        }

        /// Takes a configuration saved elsewhere, such as by a couch controls card, when nothing is pending.
        ///
        /// - Parameter saved: The configuration now stored.
        public mutating func adopt(_ saved: ControlsConfiguration) {
            guard case .ready = setting, mode == .idle else {
                return
            }
            setting.adopt(saved)
            draft = saved
        }
    }

    /// Everything the Controls pane reacts to.
    public enum Action: BindableAction, Equatable, Sendable {
        /// A change to a bound control.
        case binding(BindingAction<State>)

        /// The pane appeared: loads the configuration once and lists controllers.
        case appeared

        /// The result of a load.
        case loaded(OperationID, Result<ControlsConfiguration, PersistedSettingFailure>)

        /// The result of a save.
        case saved(OperationID, Result<ControlsConfiguration, PersistedSettingFailure>)

        /// Loads again after a failed load, or saves the held draft again after a failed save.
        case retry

        /// Replaces the whole configuration, ending any capture.
        case edit(ControlsConfiguration)

        /// Uses a preset for the keyboard, a controller or a player.
        case selectPreset(UUID, for: ControlsEditTarget)

        /// Copies a preset and uses the copy for the keyboard, a controller or a player.
        case duplicatePreset(UUID, for: ControlsEditTarget)

        /// Deletes a preset; users of it fall back to the selected preset.
        case deletePreset(UUID)

        /// Renames a preset.
        case renamePreset(UUID, String)

        /// Puts a preset's bindings back to the standard layout.
        case resetPresetBindings(UUID)

        /// Replaces one controller's preferences.
        case setControllerPreferences(String, ControllerPreferences)

        /// Binds a controller button for a controller, giving it its own preset first.
        case assignControllerButton(ControllerDevice, PlayStationControl, code: Int)

        /// Starts listening for a controller button for a controller, giving it its own preset first.
        case captureControllerButton(ControllerDevice, PlayStationControl)

        /// Ends captures and listings when the pane goes away.
        case stop

        /// Starts capturing a key for a control.
        case capture(PlayStationControl)

        /// A key or button was captured.
        case captured(UUID, Int, String)

        /// Ends the capture without binding.
        case cancelCapture

        /// Starts capturing a controller button into a preset.
        case captureButton(PlayStationControl, UUID)

        /// The button capture with this id waited too long.
        case captureTimedOut(UUID)

        /// Removes a control's input of one source from the keyboard's, a controller's or a player's preset.
        case clearBinding(PlayStationControl, source: InputSource, owner: ControlsEditTarget)

        /// Starts listening for a controller button for a player, giving the player their own preset first.
        case capturePlayerButton(Int, PlayStationControl)

        /// Returns a player to each controller's own preset.
        case removePlayerPreset(Int)

        /// Puts back the configuration from before the change with this id.
        case undoChange(UUID)

        /// The undo offer with this id lapsed.
        case changeExpired(UUID)

        /// Shows the keyboard's, a controller's or a player's bindings.
        case show(ControlsEditTarget)

        /// Shows the keyboard's, a controller's or a player's bindings on their own screen.
        case openMapping(ControlsEditTarget)

        /// Leaves the bindings' own screen, ending any capture.
        case closeMapping

        /// Forgets a disconnected controller, its preferences and its own preset.
        case forgetController(String)

        /// Binds an input in a preset.
        case assignBinding(UUID, InputBinding)

        /// Gives a controller its own copy of its preset.
        case ownPreset(key: String, name: String, touchpad: Bool, gyro: Bool)

        /// Lists the connected controllers.
        case refreshDevices

        /// The controller listing finished.
        case devices(UUID, [ControllerDevice])

        /// The controller listing failed.
        case devicesFailed(UUID)

        /// Rumbles a controller.
        case testRumble(UInt32, Double)

        /// The rumble test failed.
        case testFailed

        /// Starts recording the touchpad keyboard shortcut.
        case recordTouchpadShortcut

        /// The touchpad shortcut was recorded.
        case recordedTouchpadShortcut(UUID, KeyChord)

        /// Ends the shortcut recording.
        case cancelTouchpadShortcut

        /// Sets the touchpad shortcut's controller buttons.
        case setTouchpadButtons([Int])

        /// Sets the stream menu shortcut's controller buttons.
        case setStreamMenuButtons([Int])

        /// What the parent is told.
        case delegate(Delegate)

        /// What the Controls pane reports to its parent.
        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// A configuration was stored.
            case committed(ControlsConfiguration)

            /// A configuration could not be stored.
            case commitFailed
        }
    }

    @Dependency(\.uuid) private var uuid

    /// How long a controller button capture waits.
    static let buttonCaptureTimeout = Duration.seconds(6)

    /// How long the latest change stays undoable.
    static let changeLifetime = Duration.seconds(8)

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        ControlsSettingsStorage()
        ControlsBindingCapture()
        ControlsPresets()
        ControlsShortcuts()
        ControlsDevices()
        Reduce { state, action in
            switch action {
            case .binding(\.draft):
                guard state.isEditable else {
                    state.draft = state.setting.value ?? ControlsConfiguration()
                    return .none
                }
                state.mode = .idle
                state.notice = .quiet
                return commitEndingCapture(&state)
            case .binding:
                return .none
            case .appeared:
                return .merge(
                    ControlsSettingsStorage().load(&state),
                    ControlsDevices().refreshDevices(&state)
                )
            case let .edit(value):
                guard state.isEditable else {
                    return .none
                }
                state.mode = .idle
                state.notice = .quiet
                state.draft = value
                return commitEndingCapture(&state)
            case let .ownPreset(key, name, touchpad, gyro):
                guard state.isEditable else {
                    return .none
                }
                if !state.draft.givePreset(to: key, named: name, touchpad: touchpad, gyro: gyro, id: uuid()) {
                    state.notice = .presetLimit(ControlsConfiguration.presetLimit)
                    return .none
                }
                return ControlsSettingsStorage().commit(&state)
            case .stop:
                if let previous = state.capture?.restores {
                    state.draft = previous
                }
                state.mode = .idle
                state.inventoryAttempt = nil
                state.showsMapping = false
                return commitEndingCapture(&state)
            case .loaded, .saved, .retry, .selectPreset, .duplicatePreset, .deletePreset, .renamePreset,
                 .resetPresetBindings, .setControllerPreferences, .assignControllerButton,
                 .captureControllerButton,
                 .capture, .captured, .cancelCapture, .clearBinding, .capturePlayerButton,
                 .removePlayerPreset,
                 .undoChange, .changeExpired, .show, .openMapping, .closeMapping, .forgetController,
                 .captureButton,
                 .captureTimedOut,
                 .assignBinding, .recordTouchpadShortcut, .recordedTouchpadShortcut, .cancelTouchpadShortcut,
                 .setTouchpadButtons, .setStreamMenuButtons, .refreshDevices, .devices, .devicesFailed,
                 .testRumble,
                 .testFailed, .delegate:
                return .none
            }
        }
    }

    private func commitEndingCapture(_ state: inout State) -> Effect<Action> {
        .merge(
            .cancel(id: ControlsBindingCapture.CancelID.buttonCapture),
            ControlsSettingsStorage().commit(&state)
        )
    }
}

/// Lists the connected controllers, remembers them, chooses which device the pane edits and who is player 1,
/// forgets controllers and tests their rumble.
///
/// Only the answer of the latest listing is taken. A listing that finds a new controller, or misses one that
/// was connected, updates the remembered controllers and commits them.
private struct ControlsDevices: Reducer {
    /// The Controls pane's state.
    typealias State = ControlsSettingsFeature.State

    /// What the Controls pane reacts to.
    typealias Action = ControlsSettingsFeature.Action

    @Dependency(\.controllers) private var inventory
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date.now) private var now

    /// Reacts to listing and rumble requests and their answers.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(&state, action: action)
        }
    }

    /// Lists the connected controllers, replacing a listing still running.
    ///
    /// - Parameter state: The Controls pane's state.
    /// - Returns: The effect that lists them.
    func refreshDevices(_ state: inout State) -> Effect<Action> {
        let id = uuid()
        state.inventoryAttempt = id
        return .run { [inventory] send in
            do {
                await send(.devices(id, try await inventory.devices()))
            } catch {
                await send(.devicesFailed(id))
            }
        }
    }

    private func reduce(_ state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .refreshDevices:
            return refreshDevices(&state)
        case let .devices(id, devices):
            return listed(devices, attempt: id, state: &state)
        case .show(let target):
            return show(target, state: &state)
        case .openMapping(let target):
            state.showsMapping = true
            return show(target, state: &state)
        case .closeMapping:
            state.showsMapping = false
            return endCapture(&state)
        case .forgetController(let key):
            return forget(key, state: &state)
        case .removePlayerPreset(let player):
            return removePlayerPreset(player, state: &state)
        case .devicesFailed(let id):
            guard state.inventoryAttempt == id else {
                return .none
            }
            state.inventoryAttempt = nil
            state.notice = .controllersUnreadable
        case let .testRumble(id, strength):
            guard state.devices.contains(where: { $0.id == id && $0.rumble }) else {
                return .none
            }
            return .run { [inventory] send in
                do {
                    try await inventory.testRumble(id, strength)
                } catch {
                    await send(.testFailed)
                }
            }
        case .testFailed:
            state.notice = .rumbleRejected
        default:
            break
        }
        return .none
    }

    private func listed(_ devices: [ControllerDevice], attempt: UUID, state: inout State) -> Effect<Action> {
        guard state.inventoryAttempt == attempt else {
            return .none
        }
        let previous = state.devices
        state.devices = devices
        state.inventoryAttempt = nil
        guard state.isEditable, state.draft.needsRemembering(devices, previous: previous),
              state.draft.remember(devices, previous: previous, at: now) else {
            return .none
        }
        return ControlsSettingsStorage().commit(&state)
    }

    private func show(_ target: ControlsEditTarget, state: inout State) -> Effect<Action> {
        guard target != state.editing else {
            return .none
        }
        state.editing = target
        return endCapture(&state)
    }

    private func endCapture(_ state: inout State) -> Effect<Action> {
        guard state.capture != nil else {
            return .none
        }
        if let previous = state.capture?.restores {
            state.draft = previous
        }
        state.mode = .idle
        return .merge(
            .cancel(id: ControlsBindingCapture.CancelID.buttonCapture),
            ControlsSettingsStorage().commit(&state)
        )
    }

    private func forget(_ key: String, state: inout State) -> Effect<Action> {
        guard state.isEditable, state.draft.remembered[key] != nil || state.draft.controllers[key] != nil,
              !state.devices.contains(where: { $0.preferenceKey == key }) else {
            return .none
        }
        let previous = state.draft
        let name = state.draft.remembered[key]?.name ?? ""
        state.draft.forget(key)
        if state.editing == .controller(key) {
            state.editing = .keyboard
        }
        state.mode = .idle
        return .merge(
            ControlsSettingsStorage().commit(&state),
            ControlsBindingCapture().offerUndo(.forgot(name), previous: previous, state: &state)
        )
    }

    private func removePlayerPreset(_ player: Int, state: inout State) -> Effect<Action> {
        guard state.isEditable, state.draft.playerPreset(player) != nil else {
            return .none
        }
        let previous = state.draft
        state.draft.removePlayerPreset(player)
        state.mode = .idle
        return .merge(
            ControlsSettingsStorage().commit(&state),
            ControlsBindingCapture().offerUndo(
                .playerPresetRemoved(player),
                previous: previous,
                state: &state
            )
        )
    }
}

/// Manages the Controls pane's presets and controller preferences: choosing, copying, deleting, renaming and
/// resetting presets.
///
/// A copy is refused at the configuration's preset limit and the last preset cannot be deleted; controllers and
/// players using a deleted preset fall back to the selected one.
private struct ControlsPresets: Reducer {
    /// The Controls pane's state.
    typealias State = ControlsSettingsFeature.State

    /// What the Controls pane reacts to.
    typealias Action = ControlsSettingsFeature.Action

    @Dependency(\.uuid) private var uuid

    /// Reacts to preset and controller preference edits.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(&state, action)
        }
    }

    private func reduce(_ state: inout State, _ action: Action) -> Effect<Action> {
        guard state.isEditable else {
            return .none
        }
        switch action {
        case let .selectPreset(id, target):
            use(id, for: target, in: &state.draft)
        case let .duplicatePreset(id, target):
            guard state.draft.presets.count < ControlsConfiguration.presetLimit,
                  var copy = state.draft.presets.first(where: { $0.id == id }) else {
                return .none
            }
            copy.id = uuid()
            copy.name = String(localized: .settingsControlsPresetCopyName(name: copy.name))
            state.draft.presets.append(copy)
            use(copy.id, for: target, in: &state.draft)
        case let .deletePreset(id):
            guard state.draft.presets.count > 1 else {
                return .none
            }
            state.draft.release(id)
            state.draft.presets.removeAll { $0.id == id }
            if state.draft.selectedPresetID == id {
                state.draft.selectedPresetID = state.draft.presets[0].id
            }
        case let .renamePreset(id, name):
            guard let index = state.draft.presets.firstIndex(where: { $0.id == id }) else {
                return .none
            }
            state.draft.presets[index].name = name
        case let .resetPresetBindings(id):
            guard let index = state.draft.presets.firstIndex(where: { $0.id == id }) else {
                return .none
            }
            state.draft.presets[index].bindings = InputPreset.standard.bindings
        case let .setControllerPreferences(key, preferences):
            state.draft.controllers[key] = preferences
        default:
            return .none
        }
        return ControlsSettingsStorage().commit(&state)
    }

    private func use(
        _ id: UUID,
        for target: ControlsEditTarget,
        in configuration: inout ControlsConfiguration
    ) {
        switch target {
        case .keyboard:
            if configuration.playerPreset(0) != nil {
                configuration.playerPresets[0] = id
            } else {
                configuration.selectedPresetID = id
            }
        case .controller(let key):
            var preferences = configuration.controllers[key] ?? ControllerPreferences()
            preferences.presetID = id
            configuration.controllers[key] = preferences
        case .player(let player):
            guard configuration.playerPresets.indices.contains(player) else {
                return
            }
            configuration.playerPresets[player] = id
        }
    }
}

/// Records the touchpad keyboard shortcut and sets the controller buttons of the touchpad and stream menu
/// shortcuts.
///
/// A recorded chord that is not allowed, or buttons that overlap the other shortcut, are refused with a notice.
private struct ControlsShortcuts: Reducer {
    /// The Controls pane's state.
    typealias State = ControlsSettingsFeature.State

    /// What the Controls pane reacts to.
    typealias Action = ControlsSettingsFeature.Action

    @Dependency(\.uuid) private var uuid

    /// Reacts to shortcut recording and shortcut button edits.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(&state, action: action)
        }
    }

    private func reduce(_ state: inout State, action: Action) -> Effect<Action> {
        guard state.isEditable else {
            return .none
        }
        switch action {
        case .recordTouchpadShortcut:
            state.mode = .recordingShortcut(uuid())
            state.notice = .quiet
            return .cancel(id: ControlsBindingCapture.CancelID.buttonCapture)
        case let .recordedTouchpadShortcut(id, chord):
            guard state.shortcutCapture == id else {
                return .none
            }
            guard chord.isAllowed else {
                state.notice = .shortcutNotAllowed
                return .none
            }
            state.draft.touchpadShortcut.key = chord
            state.mode = .idle
            state.notice = .quiet
            return ControlsSettingsStorage().commit(&state)
        case .cancelTouchpadShortcut:
            guard state.shortcutCapture != nil else {
                return .none
            }
            state.mode = .idle
            return ControlsSettingsStorage().commit(&state)
        case .setTouchpadButtons(let buttons):
            var shortcut = state.draft.touchpadShortcut
            shortcut.buttons = buttons
            guard shortcut.isValid, !state.draft.streamMenuShortcut.overlaps(shortcut) else {
                state.notice = .touchpadButtonsInvalid
                return .none
            }
            state.draft.touchpadShortcut = shortcut
            state.notice = .quiet
            return ControlsSettingsStorage().commit(&state)
        case .setStreamMenuButtons(let buttons):
            let shortcut = StreamMenuShortcut(buttons: buttons)
            guard shortcut.isValid, !shortcut.overlaps(state.draft.touchpadShortcut) else {
                state.notice = .streamMenuButtonsInvalid
                return .none
            }
            state.draft.streamMenuShortcut = shortcut
            state.notice = .quiet
            return ControlsSettingsStorage().commit(&state)
        default:
            return .none
        }
    }
}

/// What the Controls pane is waiting for.
///
/// Anything but ``idle`` holds the commit: edits made by a capture are saved only once the capture, and any
/// conflict it raised, is resolved.
public enum ControlsMode: Equatable, Sendable {
    /// Nothing is captured; every valid edit is saved.
    case idle

    /// A key, mouse or controller binding is being captured.
    case capturing(ControlsCapture)

    /// The touchpad keyboard shortcut is being recorded by the recording with this id.
    case recordingShortcut(UUID)

    /// The binding capture, if one is running.
    public var capture: ControlsCapture? {
        if case let .capturing(capture) = self {
            return capture
        }
        return nil
    }

    /// The shortcut recording, if one is running.
    public var shortcutRecording: UUID? {
        if case let .recordingShortcut(id) = self {
            return id
        }
        return nil
    }
}
