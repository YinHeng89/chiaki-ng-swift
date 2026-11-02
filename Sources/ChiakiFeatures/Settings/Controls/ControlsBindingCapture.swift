import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Binds keys, mouse buttons and controller buttons to controls: listening for an input, swapping it with
/// the control that already used it, giving a controller or a player their own preset before their first
/// change, and offering to undo the latest change.
///
/// A capture for a connected controller ends on its own after
/// ``ControlsSettingsFeature/buttonCaptureTimeout``; one for a controller that is not connected waits for a
/// tapped button instead. A capture that ends without an input puts back the preset it created. Every
/// binding that lands is committed through ``ControlsSettingsStorage`` and stays undoable until
/// ``ControlsSettingsFeature/changeLifetime`` passes.
struct ControlsBindingCapture: Reducer {
    /// The Controls pane's state.
    typealias State = ControlsSettingsFeature.State

    /// What the Controls pane reacts to.
    typealias Action = ControlsSettingsFeature.Action

    /// The capture work a later capture or leaving the pane cancels.
    enum CancelID {
        /// The controller button capture's timeout.
        case buttonCapture

        /// The undo offer's expiry.
        case changeExpiry
    }

    /// Where a binding lands and how its controller buttons are named.
    private struct Destination {
        /// The preset that receives the binding.
        let presetID: UUID

        /// The name of the preset created for this change, if one was.
        let created: String?

        /// The family whose button names describe the input.
        let family: ControllerFamily

        /// The button layout of the controller being bound.
        let layout: ButtonLayout
    }

    @Dependency(\.uuid) private var uuid
    @Dependency(\.continuousClock) private var clock

    /// Reacts to captures, binding assignments and undo.
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard state.isEditable else {
                return .none
            }
            switch action {
            case let .assignControllerButton(device, target, code):
                let previous = state.draft
                guard let destination = controllerDestination(device, state: &state) else {
                    return .none
                }
                let name = ControllerGlyphs.button(
                    code,
                    family: destination.family,
                    layout: destination.layout
                )
                let binding = InputBinding(
                    source: .gamepadButton,
                    code: code,
                    label: String(name.name.prefix(40)),
                    target: target
                )
                return assign(binding, to: destination, previous: previous, state: &state)
            case let .captureControllerButton(device, target):
                let previous = state.draft
                guard let destination = controllerDestination(device, state: &state) else {
                    return .none
                }
                let waits = !state.devices.contains { $0.preferenceKey == device.preferenceKey }
                return buttonCapture(
                    target,
                    into: destination,
                    waits: waits,
                    previous: previous,
                    state: &state
                )
            case let .capturePlayerButton(player, target):
                let previous = state.draft
                guard let destination = playerDestination(player, state: &state) else {
                    return .none
                }
                let waits = !state.devices.contains { !$0.isKeyboard }
                return buttonCapture(
                    target,
                    into: destination,
                    waits: waits,
                    previous: previous,
                    state: &state
                )
            case let .captureButton(target, presetID):
                let destination = Destination(presetID: presetID, created: nil, family: .playStation,
                                              layout: .position)
                return buttonCapture(
                    target,
                    into: destination,
                    waits: false,
                    previous: state.draft,
                    state: &state
                )
            case .capture(let target):
                state.mode = .capturing(ControlsCapture(
                    id: uuid(), target: target, presetID: state.draft.keyboardPreset.id
                ))
                state.notice = .quiet
                return .cancel(id: CancelID.buttonCapture)
            case .captureTimedOut(let id):
                guard state.capture?.id == id else {
                    return .none
                }
                return endCapture(&state)
            case let .captured(id, code, label):
                guard let capture = state.capture, capture.id == id else {
                    return .none
                }
                return captured(capture, code: code, label: label, state: &state)
            case .cancelCapture:
                guard state.capture != nil else {
                    return .cancel(id: CancelID.buttonCapture)
                }
                return endCapture(&state)
            case let .assignBinding(id, binding):
                let destination = Destination(
                    presetID: id,
                    created: nil,
                    family: .playStation,
                    layout: .position
                )
                return assign(binding, to: destination, previous: state.draft, state: &state)
            case let .clearBinding(target, source, owner):
                return clear(target, source: source, owner: owner, state: &state)
            case .undoChange(let id):
                guard let change = state.change, change.id == id else {
                    return .none
                }
                state.change = nil
                state.mode = .idle
                state.draft = change.previous
                return .merge(
                    .cancel(id: CancelID.changeExpiry),
                    .cancel(id: CancelID.buttonCapture),
                    ControlsSettingsStorage().commit(&state)
                )
            case .changeExpired(let id):
                if state.change?.id == id {
                    state.change = nil
                }
                return .none
            default:
                return .none
            }
        }
    }

    /// Records a change as undoable for ``ControlsSettingsFeature/changeLifetime``.
    ///
    /// - Parameters:
    ///   - summary: What the change did.
    ///   - createdPreset: The name of the preset the change created, if any.
    ///   - family: The family whose button names describe controller inputs.
    ///   - layout: The controller's button layout.
    ///   - previous: The configuration from before the change.
    ///   - state: The pane's state.
    /// - Returns: The effect that withdraws the offer when it lapses.
    func offerUndo(_ summary: ControlsChange.Summary, createdPreset: String? = nil,
                   family: ControllerFamily = .playStation, layout: ButtonLayout = .position,
                   previous: ControlsConfiguration, state: inout State) -> Effect<Action> {
        let id = uuid()
        state.change = ControlsChange(id: id, summary: summary, createdPreset: createdPreset, family: family,
                                      layout: layout, previous: previous)
        return .run { [clock] send in
            try await clock.sleep(for: ControlsSettingsFeature.changeLifetime)
            await send(.changeExpired(id))
        }
        .cancellable(id: CancelID.changeExpiry, cancelInFlight: true)
    }

    private func buttonCapture(_ target: PlayStationControl, into destination: Destination, waits: Bool,
                               previous: ControlsConfiguration, state: inout State) -> Effect<Action> {
        guard state.draft.presets.contains(where: { $0.id == destination.presetID }) else {
            return .none
        }
        let id = uuid()
        state.mode = .capturing(ControlsCapture(
            id: id, target: target, presetID: destination.presetID, source: .gamepadButton,
            family: destination.family, layout: destination.layout,
            restores: destination.created == nil
                ? nil
                : previous
        ))
        state.notice = .quiet
        guard !waits else {
            return .cancel(id: CancelID.buttonCapture)
        }
        return .run { [clock] send in
            try await clock.sleep(for: ControlsSettingsFeature.buttonCaptureTimeout)
            await send(.captureTimedOut(id))
        }
        .cancellable(id: CancelID.buttonCapture, cancelInFlight: true)
    }

    private func endCapture(_ state: inout State) -> Effect<Action> {
        if let previous = state.capture?.restores {
            state.draft = previous
        }
        state.mode = .idle
        return .merge(.cancel(id: CancelID.buttonCapture), ControlsSettingsStorage().commit(&state))
    }

    private func captured(_ capture: ControlsCapture, code: Int, label: String,
                          state: inout State) -> Effect<Action> {
        guard let presetID = capture.presetID else {
            return .none
        }
        let created = capture.restores == nil
            ? nil
            : state.draft.presets.first { $0.id == presetID }?.name
        let destination = Destination(presetID: presetID, created: created, family: capture.family,
                                      layout: capture.layout)
        let previous = capture.restores ?? state.draft
        switch capture.source {
        case .macKey:
            guard (0...127).contains(code), !label.isEmpty, label.count <= 40 else {
                return .none
            }
            let binding = InputBinding(source: .macKey, code: code, label: label, target: capture.target)
            return assign(binding, to: destination, previous: previous, state: &state)
        case .gamepadButton:
            guard (0...25).contains(code) else {
                return .none
            }
            let name = ControllerGlyphs.button(code, family: capture.family, layout: capture.layout).name
            let binding = InputBinding(source: .gamepadButton, code: code, label: String(name.prefix(40)),
                                       target: capture.target)
            return .merge(
                .cancel(id: CancelID.buttonCapture),
                assign(binding, to: destination, previous: previous, state: &state)
            )
        case .mouseButton:
            return .none
        }
    }
}

extension ControlsBindingCapture {
    private func assign(_ binding: InputBinding, to destination: Destination, previous: ControlsConfiguration,
                        state: inout State) -> Effect<Action> {
        let maximum = switch binding.source {
        case .macKey:
            127
        case .mouseButton:
            7
        case .gamepadButton:
            25
        }
        guard (-1...maximum).contains(binding.code), binding.label.count <= 40,
              let index = state.draft.presets.firstIndex(where: { $0.id == destination.presetID }) else {
            return .none
        }
        state.mode = .idle
        state.notice = .quiet
        let summary: ControlsChange.Summary
        if binding.code < 0 {
            state.draft.presets[index].clear(binding.target, source: binding.source)
            summary = .cleared(binding.target)
        } else {
            summary = ControlsChange.summary(of: binding, result: state.draft.presets[index].assign(binding))
        }
        return .merge(
            ControlsSettingsStorage().commit(&state),
            offerUndo(summary, createdPreset: destination.created, family: destination.family,
                      layout: destination.layout, previous: previous, state: &state)
        )
    }

    private func clear(_ target: PlayStationControl, source: InputSource, owner: ControlsEditTarget,
                       state: inout State) -> Effect<Action> {
        let previous = state.capture?.restores ?? state.draft
        let destination: Destination?
        switch owner {
        case .keyboard:
            destination = Destination(
                presetID: state.draft.keyboardPreset.id,
                created: nil,
                family: .playStation,
                layout: .position
            )
        case .controller(let key):
            destination = state.device(key).flatMap { controllerDestination($0, state: &state) }
        case .player(let player):
            destination = playerDestination(player, state: &state)
        }
        guard let destination else {
            return .none
        }
        let created = previous.presets.count < state.draft.presets.count
            ? state.draft.presets.first { $0.id == destination.presetID }?.name
            : nil
        let binding = InputBinding(source: source, code: -1, label: "", target: target)
        return .merge(
            .cancel(id: CancelID.buttonCapture),
            assign(binding, to: Destination(presetID: destination.presetID, created: created,
                                            family: destination.family, layout: destination.layout),
                   previous: previous, state: &state)
        )
    }

    private func controllerDestination(_ device: ControllerDevice, state: inout State) -> Destination? {
        let before = state.draft.presets.count
        let given = state.draft.givePreset(
            to: device.preferenceKey, named: device.name, touchpad: device.touchpad, gyro: device.motion,
            id: uuid()
        )
        guard given, state.draft.ownsPreset(device.preferenceKey),
              let id = state.draft.controllers[device.preferenceKey]?.presetID else {
            state.notice = .presetLimit(ControlsConfiguration.presetLimit)
            return nil
        }
        let layout = state.draft.controllers[device.preferenceKey]?.buttonLayout ?? .position
        let created = state.draft.presets.count > before
            ? state.draft.presets.first { $0.id == id }?.name
            : nil
        return Destination(presetID: id, created: created, family: device.family, layout: layout)
    }

    private func playerDestination(_ player: Int, state: inout State) -> Destination? {
        let before = state.draft.presets.count
        guard state.draft.givePlayerPreset(player, named: "Player \(player + 1)", id: uuid()),
              let preset = state.draft.playerPreset(player) else {
            state.notice = .presetLimit(ControlsConfiguration.presetLimit)
            return nil
        }
        let family = state.devices.first { !$0.isKeyboard }?.family ?? .playStation
        let created = state.draft.presets.count > before
            ? preset.name
            : nil
        return Destination(presetID: preset.id, created: created, family: family, layout: .position)
    }
}
