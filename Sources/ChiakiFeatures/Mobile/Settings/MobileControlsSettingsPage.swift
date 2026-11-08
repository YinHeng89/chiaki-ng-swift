import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The touch Controls settings page: every remembered controller and players 1 to 4, the bindings of the one
/// chosen on the binding board, then that controller's own settings and the shared shortcuts and lights.
///
/// Every change is saved as it is made and the latest can be undone.
struct MobileControlsSettingsPage: View {
    /// The settings feature that owns the controls settings.
    let settings: StoreOf<SettingsFeature>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings feature that owns the controls settings.
    init(settings: StoreOf<SettingsFeature>) {
        self.settings = settings
    }

    var body: some View {
        MobileControlsForm(store: settings.scope(state: \.controls, action: \.controls))
    }
}

/// The groups of the Controls page, bound to the controls settings feature.
private struct MobileControlsForm: View {
    /// The controller layer that captures a button for a binding.
    @Environment(\.controllerNavigation) var controllerNavigation

    /// The controls settings feature the page reads and edits.
    @Bindable var store: StoreOf<ControlsSettingsFeature>

    @State private var buttonCaptureID: UUID?
    @State private var keyboardTab = 0
    @State private var mappingTab = MobileControlsMappingTab.buttons
    @State private var presetMenuAnchor = NativeMenuAnchorReference()
    @State private var presetRenameRequest = 0
    @Environment(\.screenLayout) private var layout
    @Environment(\.touchKeyboard) private var touchKeyboard

    private static let buttonChoices = Array(0...20)

    var body: some View {
        Group {
            if store.showsMapping {
                mapping
            } else {
                MobileSettingsForm {
                    players
                    controllers
                    shared
                } trailing: {
                    selection
                }
            }
        }
        .background(KeyBindingCapture(capture: keyCapture) { id, code, label in
            store.send(.captured(id, code, label))
        } cancel: {
            store.send(.cancelCapture)
        })
        .task {
            let clock = ContinuousClock()
            while !Task.isCancelled {
                store.send(.refreshDevices)
                try? await clock.sleep(for: .seconds(1))
            }
        }
        .onChange(of: buttonCapture?.id, initial: true) { _, _ in
            updateButtonCapture()
        }
        .onChange(of: store.canListen) { _, _ in
            updateButtonCapture()
        }
        .onChange(of: store.showsMapping) { _, _ in
            mappingTab = .buttons
        }
        .onAppear {
            store.send(.appeared)
            #if !os(macOS)
                if store.editing == .keyboard {
                    store.send(.show(.player(0)))
                }
            #endif
        }
        .onDisappear {
            endButtonCapture()
            store.send(.stop)
        }
    }

    private var players: some View {
        MobileSettingsGroup(
            .mobileControlsPlayers,
            footer: .mobileControlsPlayersFooter
        ) {
            ForEach(0..<ControlsConfiguration.playerCount, id: \.self) { player in
                MobileControlsTargetRow(
                    title: Text(.mobileControlsPlayer(player: player + 1)),
                    lines: playerLines(player),
                    selected: store.editing == .player(player),
                    tag: player == 0 && playsWithTouch
                        ? .mobileControlsTouchTag
                        : nil
                ) {
                    MobileControlsPlayerBadge(player: player)
                } choose: {
                    store.send(.show(.player(player)))
                }
            }
        }
    }

    @ViewBuilder private var controllers: some View {
        if !devices.isEmpty {
            MobileSettingsGroup(.mobileControlsControllers) {
                ForEach(devices, id: \.preferenceKey) { device in
                    deviceRow(device)
                }
            }
        }
    }

    @ViewBuilder private var selection: some View {
        if let change = store.change {
            MobileSettingsGroup {
                changeRow(change)
            }
            .disabled(!store.isEditable)
        }
        switch store.editing {
        case .keyboard:
            bindingsGroup(title: String(localized: .mobileControlsKeyboardAndMouse))
            MobileSettingsGroup(.mobileControlsKeyboardAndMouse) {
                ControlsKeyboardMouseSection(store: store, preset: store.editingPreset, tab: $keyboardTab)
                    .padding(16)
            }
            .disabled(!store.isEditable)
        case .player(let player) where player == 0:
            playerOne
            bindingsGroup(title: String(localized: .mobileControlsBindings))
        case .player(let player):
            MobileSettingsGroup {
                playsWith(player)
            }
            .disabled(!store.isEditable)
            bindingsGroup(title: String(localized: .mobileControlsPlayer(player: player + 1)))
        case .controller(let key):
            bindingsGroup(title: targetTitle)
            if let device = store.state.device(key) {
                MobileControllerSettings(
                    device: device,
                    preferences: store.draft.controllers[key] ?? .init(),
                    preset: store.editingPreset,
                    update: { value in
                        store.send(.setControllerPreferences(key, value))
                    },
                    test: { strength in
                        store.send(.testRumble(device.id, strength))
                    },
                    connected: store.state.isConnected(key),
                    lightbar: store.draft.lightbar
                )
                .disabled(!store.isEditable)
                .id(key)
            }
        }
    }

    private var playerOne: some View {
        MobileSettingsGroup(.mobileControlsPlayerOne, footer: playerOneNote) {
            playsWith(0)
            #if !os(macOS)
                MobilePickerRow(
                    .mobileControlsTouchControls,
                    selection: $store.draft.virtualGamepad,
                    choices: [.automatic, .shown, .hidden]
                ) { presence in
                    switch presence {
                    case .automatic:
                        .commonAutomatic
                    case .shown:
                        .mobileControlsTouchControlsAlways
                    case .hidden:
                        .commonOff
                    }
                }
                MobileToggleRow(.mobileControlsOnScreenTouchpad, isOn: edited(\.onScreenTouchpad))
                MobileToggleRow(
                    .mobileControlsMotionControls,
                    detail: .mobileControlsMotionControlsDetail,
                    isOn: edited(\.deviceMotion)
                )
            #endif
        }
        .disabled(!store.isEditable)
    }

    private func bindingsGroup(title: String) -> some View {
        MobileSettingsGroup(verbatim: title, footer: note) {
            MobileValueRow(.mobileControlsButtonMapping, value: store.editingPreset.title) {
                store.send(.openMapping(store.editing))
            }
            MobilePickerRow(
                .mobileControlsPreset,
                selection: presetSelection,
                choices: store.draft.presets.map(\.id),
                label: { id in
                    store.draft.presets.first { $0.id == id }?.title ?? .verbatim("")
                }
            )
            if case .player(let player) = store.editing, store.draft.playerPreset(player) != nil {
                MobileButtonRow(.mobileControlsUseEachControllersBindings) {
                    store.send(.removePlayerPreset(player))
                }
            }
            if case .controller(let key) = store.editing, !store.state.isConnected(key) {
                MobileButtonRow(.mobileControlsForgetController, destructive: true) {
                    store.send(.forgetController(key))
                }
            }
        }
        .disabled(!store.isEditable)
    }

    @ViewBuilder private var shared: some View {
        touchpadGroup
            .disabled(!store.isEditable)
        streamMenuGroup
            .disabled(!store.isEditable)
        MobileLightbarGroup(
            note: .allControllers,
            value: store.draft.lightbar,
            inherited: nil
        ) { value in
            var draft = store.draft
            draft.lightbar = value ?? .followGame
            store.send(.edit(draft))
        }
        .disabled(!store.isEditable)
        #if os(macOS)
            MobileSettingsGroup(
                .mobileControlsBackground,
                footer: .mobileControlsBackgroundFooter
            ) {
                MobileToggleRow(
                    .mobileControlsBackgroundInput,
                    isOn: edited(\.backgroundInput)
                )
            }
            .disabled(!store.isEditable)
        #endif
        if let message = store.notice.message {
            Label(message, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        SettingsPersistenceBanner(
            store.setting,
            subject: .mobileControlsPersistenceSubject,
            reportsInvalid: false
        ) {
            store.send(.retry)
        }
        .padding(.horizontal, 16)
    }

    private var touchpadGroup: some View {
        MobileSettingsGroup(
            .mobileControlsTouchpadShortcut,
            footer: store.draft.onScreenTouchpad
                ? .mobileControlsTouchpadShortcutOn
                : .mobileControlsTouchpadShortcutOff
        ) {
            MobileToggleRow(.mobileControlsControllerCombo, isOn: touchpadCombo)
            if store.draft.touchpadShortcut.buttons.count >= 2 {
                MobilePickerRow(
                    .mobileControlsFirstButton,
                    selection: touchpadButton(0),
                    choices: Self.buttonChoices,
                    label: BindingRow.buttonName
                )
                MobilePickerRow(
                    .mobileControlsSecondButton,
                    selection: touchpadButton(1),
                    choices: Self.buttonChoices,
                    label: BindingRow.buttonName
                )
            }
        }
        .disabled(!store.draft.onScreenTouchpad)
    }

    private var streamMenuGroup: some View {
        MobileSettingsGroup(
            .mobileControlsStreamMenu,
            footer: .mobileControlsStreamMenuFooter
        ) {
            ForEach(0..<StreamMenuShortcut.buttonLimit.upperBound, id: \.self) { slot in
                MobilePickerRow(
                    .mobileControlsButtonSlot(slot: slot + 1),
                    selection: streamMenuButton(slot),
                    choices: (slot >= StreamMenuShortcut.buttonLimit.lowerBound
                        ? [StreamMenuShortcutCard.unused]
                        : []) + Self.buttonChoices
                ) { code in
                    code == StreamMenuShortcutCard.unused
                        ? .mobileControlsNotUsed
                        : BindingRow.buttonName(code)
                }
            }
        }
    }

    private func playsWith(_ player: Int) -> some View {
        let fixed: [String?] = player == 0
            ? [nil, ControlsConfiguration.keyboardOnlyKey]
            : [nil]
        return MobilePickerRow(
            .mobileControlsPlaysWith,
            selection: Binding(
                get: {
                    store.state.shownControllerKey(forPlayer: player)
                },
                set: { key in
                    var draft = store.draft
                    draft.setControllerKey(key, forPlayer: player)
                    store.send(.edit(draft))
                }
            ),
            choices: fixed + store.state.controllerChoices(forPlayer: player).map {
                Optional($0.preferenceKey)
            },
            label: playsWithTitle
        )
    }

    private func playsWithTitle(_ key: String?) -> LocalizedStringResource {
        guard let key else {
            return .mobileControlsFirstAvailable
        }
        if key == ControlsConfiguration.keyboardOnlyKey {
            return ControlsPlayerControllerPicker.withoutControllerTitle
        }
        return store.state.device(key).map { store.state.title(of: $0) } ?? .mobileControlsFirstAvailable
    }

    private func deviceRow(_ device: ControllerDevice) -> some View {
        let target = device.isKeyboard
            ? ControlsEditTarget.keyboard
            : .controller(device.preferenceKey)
        let connected = device.isKeyboard || store.state.isConnected(device.preferenceKey)
        return MobileControlsTargetRow(
            title: title(for: device),
            lines: lines(for: device, connected: connected),
            selected: store.editing == target
        ) {
            deviceThumbnail(device)
                .opacity(
                    connected
                        ? 1
                        : 0.45
                )
        } choose: {
            store.send(.show(target))
        }
    }

    @ViewBuilder private func deviceThumbnail(_ device: ControllerDevice) -> some View {
        if device.isKeyboard {
            Image(systemName: "keyboard")
                .font(.title3)
                .foregroundStyle(.secondary)
        } else if let image = ControllerArtwork.of(device).image {
            Image(platformImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "gamecontroller")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func changeRow(_ change: ControlsChange) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(Self.sentence(for: change))
                .frame(maxWidth: .infinity, alignment: .leading)
            FocusButton(.mobileControlsUndo) {
                store.send(.undoChange(change.id))
            }
            .buttonStyle(.borderless)
            .tint(Palette.accent)
        }
        .mobileRowPadding()
        .accessibilityElement(children: .contain)
    }

    private var mapping: some View {
        VStack(alignment: .leading, spacing: 12) {
            mappingHeader
            Group {
                if let capture = store.capture, capture.source == .gamepadButton, !store.canListen {
                    captureChoices(capture)
                } else {
                    switch mappingTab {
                    case .buttons:
                        board(.picture)
                    case .others:
                        ScrollView {
                            board(.others)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, MobilePageTitle.topPadding(layout) - 12)
        .padding(.bottom, max(12, layout.bottomInset))
        .disabled(!store.isEditable)
    }

    private func board(_ part: ControlsBindingBoard.Part) -> some View {
        ControlsBindingBoard(
            preset: store.editingPreset,
            source: store.editing == .keyboard
                ? .macKey
                : .gamepadButton,
            artwork: store.editing == .keyboard
                ? .dualSense
                : ControllerArtwork.of(store.editingDevice ?? store.playerDevice),
            family: store.editingFamily,
            layout: store.editingLayout,
            listening: store.capture?.target,
            changed: changed,
            select: listen(for:),
            part: part
        )
    }

    private var mappingHeader: some View {
        HStack(spacing: 12) {
            FocusButton {
                store.send(.closeMapping)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(.commonBack))
            VStack(alignment: .leading, spacing: 1) {
                Text(.mobileControlsButtonMapping)
                    .font(.title3.bold())
                Text(verbatim: mappingSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if let capture = store.capture {
                captureControls(capture)
            } else {
                mappingControls
            }
        }
    }

    @ViewBuilder private var mappingControls: some View {
        if store.editing != .keyboard {
            FocusableSegments(
                options: [MobileControlsMappingTab.buttons, .others],
                title: { tab in
                    tab == .buttons
                        ? .mobileControlsButtons
                        : .mobileControlsMore
                },
                selection: $mappingTab
            )
            .fixedSize()
            .accessibilityLabel(Text(.mobileControlsControls))
        }
        if let change = store.change {
            FocusButton(.mobileControlsUndo) {
                store.send(.undoChange(change.id))
            }
            .buttonStyle(.glass)
            .accessibilityHint(Text(Self.sentence(for: change)))
        }
        presetMenu
    }

    private var presetMenu: some View {
        Menu {
            Picker(selection: presetSelection) {
                ForEach(store.draft.presets) { preset in
                    Text(preset.title).tag(preset.id)
                }
            } label: {
                Text(.mobileControlsPreset)
            }
            Divider()
            Button {
                store.send(.duplicatePreset(store.editingPreset.id, for: store.editing))
            } label: {
                Label(.mobileControlsDuplicatePreset, systemImage: "plus.square.on.square")
            }
            .disabled(store.draft.presets.count >= ControlsConfiguration.presetLimit)
            if let touchKeyboard {
                Button {
                    touchKeyboard(TouchKeyboardRequest(
                        title: .mobileControlsPresetName,
                        prompt: .mobileControlsPresetNamePrompt,
                        text: presetName
                    ))
                } label: {
                    Label(.mobileControlsRenamePreset, systemImage: "pencil")
                }
            }
            Button {
                store.send(.resetPresetBindings(store.editingPreset.id))
            } label: {
                Label(.mobileControlsResetBindings, systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
                store.send(.deletePreset(store.editingPreset.id))
            } label: {
                Label(.mobileControlsDeletePreset, systemImage: "trash")
            }
            .disabled(store.draft.presets.count == 1)
        } label: {
            Label(store.editingPreset.title, systemImage: "chevron.up.chevron.down")
                .labelStyle(MobileControlsTrailingIconLabel())
                .lineLimit(1)
                .frame(maxWidth: 160)
        }
        .buttonStyle(.glass)
        .nativeMenuAnchor(presetMenuAnchor)
        .interactiveGrowth()
        .modifier(MenuButtonFocus(activate: presentPresetMenu))
        .controllerKeyboard(
            title: .mobileControlsPresetName,
            text: presetName,
            isFocused: false,
            presentationRequest: presetRenameRequest
        )
    }

    private func presentPresetMenu() {
        let presets = store.draft.presets
        var entries: [(title: String, run: () -> Void)] = presets.map { preset in
            (String(localized: preset.title), { presetSelection.wrappedValue = preset.id })
        }
        if presets.count < ControlsConfiguration.presetLimit {
            entries.append((String(localized: .mobileControlsDuplicatePreset), {
                store.send(.duplicatePreset(store.editingPreset.id, for: store.editing))
            }))
        }
        entries.append((String(localized: .mobileControlsRenamePreset), { presetRenameRequest += 1 }))
        entries.append((
            String(localized: .mobileControlsResetBindings),
            { store.send(.resetPresetBindings(store.editingPreset.id)) }
        ))
        if presets.count > 1 {
            entries.append((
                String(localized: .mobileControlsDeletePreset),
                { store.send(.deletePreset(store.editingPreset.id)) }
            ))
        }
        presetMenuAnchor.presentMenu(
            titles: entries.map(\.title),
            selected: presets.firstIndex { $0.id == store.editingPreset.id }
        ) { index in
            guard entries.indices.contains(index) else {
                return
            }
            entries[index].run()
        }
    }

    private func captureControls(_ capture: ControlsCapture) -> some View {
        HStack(spacing: 10) {
            Text(listeningPrompt(for: capture))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            FocusButton(.commonClear) {
                store.send(.clearBinding(capture.target, source: capture.source, owner: store.editing))
            }
            .buttonStyle(.glass)
            FocusButton(.commonCancel) {
                store.send(.cancelCapture)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .foregroundStyle(.black)
        }
    }

    private func captureChoices(_ capture: ControlsCapture) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
            ForEach(captureButtons(for: capture), id: \.self) { code in
                let glyph = ControllerGlyphs.button(code, family: capture.family, layout: capture.layout)
                FocusButton {
                    store.send(.captured(capture.id, code, ""))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: glyph.symbol ?? "circle.dashed")
                            .font(.title3)
                            .opacity(
                                glyph.symbol == nil
                                    ? 0
                                    : 1
                            )
                        Text(glyph.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .accessibilityLabel(Text(glyph.name))
            }
        }
    }

    private func listeningPrompt(for capture: ControlsCapture) -> LocalizedStringResource {
        let control = String(localized: capture.target.label)
        guard capture.source == .gamepadButton, !store.canListen else {
            return .mobileControlsPressButton(control: control)
        }
        return .mobileControlsChooseButton(control: control)
    }

    private var mappingSubtitle: String {
        switch store.editing {
        case .keyboard:
            return String(localized: .mobileControlsKeyboard)
        case .controller:
            return targetTitle
        case .player(let player):
            guard let device = store.playerDevice else {
                return String(localized: .mobileControlsPlayer(player: player + 1))
            }
            return String(localized: .mobileControlsPlayerDevice(player: player + 1, device: device.name))
        }
    }

    private var playsWithTouch: Bool {
        store.draft.selectedControllerKey == ControlsConfiguration.keyboardOnlyKey
    }
}

/// Which controls the touch Button Mapping screen shows: the drawing's buttons, or the sticks, touchpad halves
/// and gyro hold that have no place on it.
enum MobileControlsMappingTab: Hashable {
    /// The buttons on the drawing.
    case buttons

    /// The controls without a place on the drawing.
    case others
}

/// A label with its icon after its title, for a menu showing its current choice.
private struct MobileControlsTrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// A player's badge in the Players list: the player's number on their light colour.
private struct MobileControlsPlayerBadge: View {
    /// The player's index, 0 for player 1.
    let player: Int

    var body: some View {
        Text(.mobileControlsPlayerBadge(player: player + 1))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: 30, height: 30)
            .background(color.gradient, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch player {
        case 0:
            Palette.accent
        case 1:
            .blue
        case 2:
            .green
        default:
            .pink
        }
    }
}

extension MobileControlsForm {
    private var devices: [ControllerDevice] {
        #if os(macOS)
            store.listedDevices
        #else
            store.listedDevices.filter {
                !$0.isKeyboard
            }
        #endif
    }

    private var keyCapture: ControlsCapture? {
        guard let capture = store.capture, capture.source == .macKey else {
            return nil
        }
        return capture
    }

    private var buttonCapture: ControlsCapture? {
        guard let capture = store.capture, capture.source == .gamepadButton else {
            return nil
        }
        return capture
    }

    private var presetSelection: Binding<UUID> {
        Binding(
            get: {
                store.editingPreset.id
            },
            set: { id in
                store.send(.selectPreset(id, for: store.editing))
            }
        )
    }

    private var presetName: Binding<String> {
        Binding(
            get: {
                store.editingPreset.name
            },
            set: { name in
                store.send(.renamePreset(store.editingPreset.id, name))
            }
        )
    }

    private var touchpadCombo: Binding<Bool> {
        Binding(
            get: {
                !store.draft.touchpadShortcut.buttons.isEmpty
            },
            set: { enabled in
                store.send(.setTouchpadButtons(
                    enabled
                        ? TouchpadShortcut.standard.buttons
                        : []
                ))
            }
        )
    }

    private func touchpadButton(_ slot: Int) -> Binding<Int> {
        let shown = store.draft.touchpadShortcut.buttons
        return Binding(
            get: {
                shown.indices.contains(slot)
                    ? shown[slot]
                    : TouchpadShortcut.standard.buttons[slot]
            },
            set: { code in
                var buttons = store.draft.touchpadShortcut.buttons
                guard buttons.indices.contains(slot) else {
                    return
                }
                if let existing = buttons.firstIndex(of: code), existing != slot {
                    buttons.swapAt(existing, slot)
                } else {
                    buttons[slot] = code
                }
                store.send(.setTouchpadButtons(buttons))
            }
        )
    }

    private func streamMenuButton(_ slot: Int) -> Binding<Int> {
        let buttons = store.draft.streamMenuShortcut.buttons
        return Binding(
            get: {
                buttons.indices.contains(slot)
                    ? buttons[slot]
                    : StreamMenuShortcutCard.unused
            },
            set: { code in
                let chosen = StreamMenuShortcutCard.choosing(code, slot: slot, in: buttons)
                store.send(.setStreamMenuButtons(chosen))
            }
        )
    }

    private func edited<Value>(_ key: WritableKeyPath<ControlsConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: {
                store.draft[keyPath: key]
            },
            set: { value in
                var draft = store.draft
                draft[keyPath: key] = value
                store.send(.edit(draft))
            }
        )
    }

    private var changed: Set<PlayStationControl> {
        switch store.change?.summary {
        case .assigned(let binding):
            [binding.target]
        case let .moved(binding, from, _):
            [binding.target, from]
        case .cleared(let control):
            [control]
        case .forgot, .playerPresetRemoved, nil:
            []
        }
    }

    private func listen(for control: PlayStationControl) {
        switch store.editing {
        case .keyboard:
            store.send(.capture(control))
        case .controller:
            if let device = store.editingDevice {
                store.send(.captureControllerButton(device, control))
            }
        case .player(let player):
            store.send(.capturePlayerButton(player, control))
        }
    }

    private func updateButtonCapture() {
        endButtonCapture()
        guard let capture = buttonCapture, store.canListen else {
            return
        }
        let id = capture.id
        let device: UInt32? = if case .controller(let key) = store.editing {
            store.devices.first { $0.preferenceKey == key }?.id
        } else {
            nil
        }
        buttonCaptureID = controllerNavigation?.beginButtonCapture(device: device) { outcome in
            switch outcome {
            case .assign(let code):
                store.send(.captured(id, code, ""))
            case .cancel:
                store.send(.cancelCapture)
            }
        }
    }

    private func endButtonCapture() {
        if let buttonCaptureID {
            controllerNavigation?.endButtonCapture(buttonCaptureID)
        }
        buttonCaptureID = nil
    }
}

extension MobileControlsForm {
    private var targetTitle: String {
        switch store.editing {
        case .keyboard:
            String(localized: .mobileControlsKeyboardAndMouse)
        case .controller:
            store.editingDevice?.name ?? String(localized: .mobileControlsController)
        case .player(let player):
            String(localized: .mobileControlsPlayer(player: player + 1))
        }
    }

    private var note: LocalizedStringResource {
        switch store.editing {
        case .keyboard:
            return .mobileControlsNoteKeyboard
        case .controller(let key):
            guard store.state.isConnected(key) else {
                return .mobileControlsNoteDisconnected
            }
            guard store.draft.ownsPreset(key) else {
                return .mobileControlsNoteFirstChange
            }
            return .mobileControlsNoteOwnPreset
        case .player(let player):
            let shared = store.draft.playerPreset(player) == nil
            guard player > 0 else {
                return shared
                    ? .mobileControlsNotePlayerShared(player: player + 1)
                    : .mobileControlsNotePlayerOwn(player: player + 1)
            }
            return shared
                ? .mobileControlsNotePlayerJoinShared(joining: player + 1, player: player + 1)
                : .mobileControlsNotePlayerJoinOwn(joining: player + 1, player: player + 1)
        }
    }

    private func title(for device: ControllerDevice) -> Text {
        guard !device.isKeyboard else {
            return Text(.mobileControlsKeyboardAndMouseDevice)
        }
        return Text(store.state.title(of: device))
    }

    private func lines(for device: ControllerDevice, connected: Bool) -> [Text] {
        guard !device.isKeyboard else {
            return [Text(.mobileControlsPlaysAsPlayerOne)]
        }
        var lines: [Text]
        if connected {
            lines = [Text(.mobileControlsConnected), Text(verbatim: device.transport)]
        } else if let seen = store.draft.remembered[device.preferenceKey]?.lastSeen {
            lines = [
                Text(.mobileControlsNotConnected),
                Text(.mobileControlsLastSeen(time: seen.formatted(.relative(presentation: .named))))
            ]
        } else {
            lines = [Text(.mobileControlsNotConnected)]
        }
        if !device.individual {
            lines.append(Text(.mobileControlsSharedByEvery(model: device.name)))
        }
        return lines
    }

    private func playerLines(_ player: Int) -> [Text] {
        let bindings = Text(
            store.draft.playerPreset(player) == nil
                ? .mobileControlsEachControllersBindings
                : .mobileControlsOwnBindings
        )
        guard player > 0, store.state.shownControllerKey(forPlayer: player) == nil else {
            return [playerController(player), bindings]
        }
        return [Text(.mobileControlsJoinsWithPS), bindings]
    }

    private var playerOneNote: LocalizedStringResource {
        guard playsWithTouch else {
            return virtualGamepadNote
        }
        return .mobileControlsPlayerOneTouchNote
    }

    private func playerController(_ player: Int) -> Text {
        Text(playsWithTitle(store.state.shownControllerKey(forPlayer: player)))
    }

    private var virtualGamepadNote: LocalizedStringResource {
        switch store.draft.virtualGamepad {
        case .automatic:
            .mobileControlsTouchAutomaticNote
        case .shown:
            .mobileControlsTouchShownNote
        case .hidden:
            .mobileControlsTouchHiddenNote
        }
    }

    private func captureButtons(for capture: ControlsCapture) -> [Int] {
        switch capture.family {
        case .playStation:
            Array(0...15) + [20]
        case .xbox, .nintendo:
            Array(0...15)
        case .generic:
            Array(0..<ControllerGlyphs.buttonCount)
        }
    }

    private static func sentence(for change: ControlsChange) -> LocalizedStringResource {
        let name = { (input: InputBinding) in
            String(localized: KeyCodeLabels.title(for: input, family: change.family, layout: change.layout))
        }
        let preset = change.createdPreset
        switch change.summary {
        case .assigned(let binding):
            let control = String(localized: binding.target.label)
            return preset.map {
                .mobileControlsChangeAssignedSaved(control: control, input: name(binding), preset: $0)
            } ?? .mobileControlsChangeAssigned(control: control, input: name(binding))
        case let .moved(binding, displaced, exchanged?):
            let control = String(localized: displaced.label)
            return preset.map {
                .mobileControlsChangeExchangedSaved(
                    input: name(binding),
                    displaced: control,
                    control: control,
                    exchanged: name(exchanged),
                    preset: $0
                )
            } ?? .mobileControlsChangeExchanged(
                input: name(binding),
                displaced: control,
                control: control,
                exchanged: name(exchanged)
            )
        case let .moved(binding, displaced, nil):
            let control = String(localized: displaced.label)
            return preset.map {
                .mobileControlsChangeMovedSaved(input: name(binding), displaced: control, preset: $0)
            } ?? .mobileControlsChangeMoved(input: name(binding), displaced: control)
        case .cleared(let control):
            let label = String(localized: control.label)
            return preset.map {
                .mobileControlsChangeClearedSaved(control: label, preset: $0)
            } ?? .mobileControlsChangeCleared(control: label)
        case .forgot(let controller) where controller.isEmpty:
            return preset.map {
                .mobileControlsChangeForgotUnnamedSaved(preset: $0)
            } ?? .mobileControlsChangeForgotUnnamed
        case .forgot(let controller):
            return preset.map {
                .mobileControlsChangeForgotSaved(controller: controller, preset: $0)
            } ?? .mobileControlsChangeForgot(controller: controller)
        case .playerPresetRemoved(let player):
            return preset.map {
                .mobileControlsChangePlayerSharedSaved(player: player + 1, preset: $0)
            } ?? .mobileControlsChangePlayerShared(player: player + 1)
        }
    }
}

/// One controller's own settings beside its bindings, in Calibration, Feedback, Adaptive Triggers, Light Bar
/// and Details groups.
///
/// A disconnected controller keeps its settings visible, but only its details can change until it is back.
private struct MobileControllerSettings: View {
    /// The controller whose capabilities decide which settings are offered.
    let device: ControllerDevice

    /// The controller's current preferences.
    let preferences: ControllerPreferences

    /// The preset whose gyro hold button the calibration caption names.
    let preset: InputPreset

    /// Called with the preferences after any calibration, feedback or detail changes.
    let update: (ControllerPreferences) -> Void

    /// Plays a rumble test at the given strength.
    let test: (Double) -> Void

    /// Whether the controller is connected; when not, only its details can change.
    let connected: Bool

    /// The light bar setting inherited when this controller does not choose its own.
    let lightbar: ControllerLightbar

    var body: some View {
        calibration
            .disabled(!connected)
        feedback
            .disabled(!connected)
        triggers
            .disabled(!connected)
        MobileLightbarGroup(
            note: device.lights
                ? nil
                : .noLightBar,
            value: preferences.lightbar,
            inherited: lightbar,
            enabled: device.lights
        ) { value in
            var changed = preferences
            changed.lightbar = value
            update(changed)
        }
        .disabled(!connected)
        MobileSettingsGroup(
            .mobileControlsDetails,
            footer: device.individual
                ? nil
                : .mobileControlsSharedIdentity
        ) {
            MobileTextEntryRow(
                title: .mobileControlsNickname,
                prompt: .mobileControlsNickname,
                text: binding(\.nickname)
            )
        }
    }

    private var card: ControllerSettingsCard {
        ControllerSettingsCard(
            device: device,
            preferences: preferences,
            preset: preset,
            update: update,
            test: test,
            connected: connected,
            lightbar: lightbar
        )
    }

    private var calibration: some View {
        MobileSettingsGroup(.mobileControlsCalibration, footer: card.stickGyroCaption) {
            slider(.mobileControlsDeadZone, key: \.deadZone, range: 0...0.5, step: 0.01)
            MobileToggleRow(.mobileControlsInvertRightY, isOn: binding(\.invertRightY))
            MobileToggleRow(.mobileControlsSwapSticks, isOn: binding(\.swapSticks))
            if device.family == .nintendo {
                MobileToggleRow(
                    .mobileControlsNintendoLabels,
                    detail: preferences.buttonLayout == .label
                        ? .mobileControlsNintendoLabelsOn
                        : .mobileControlsNintendoLabelsOff,
                    isOn: nintendoLabels
                )
            }
            MobilePickerRow(
                .mobileControlsRightStickGyro,
                selection: binding(\.stickGyro),
                choices: StickGyroMode.allCases
            ) { mode in
                mode.title
            }
        }
    }

    private var feedback: some View {
        MobileSettingsGroup(
            .mobileControlsFeedback,
            footer: .mobileControlsFeedbackFooter(caption: String(localized: card.hapticsCaption))
        ) {
            MobilePickerRow(
                .mobileControlsHaptics,
                selection: binding(\.hapticFeedback),
                choices: HapticFeedback.allCases
            ) { feedback in
                feedback.title
            }
            .disabled(!device.nativeHaptics && !device.rumble)
            slider(.mobileControlsHapticStrength, key: \.hapticStrength, range: 0...2.4, step: 0.1)
                .disabled(!device.nativeHaptics && !device.rumble)
            slider(.mobileControlsRumbleStrength, key: \.rumbleStrength, range: 0...1, step: 0.05)
                .disabled(!device.rumble)
            MobileButtonRow(.mobileControlsTestRumble) {
                test(preferences.rumbleStrength)
            }
            .disabled(!device.rumble)
        }
    }

    private var triggers: some View {
        MobileSettingsGroup(
            .mobileControlsAdaptiveTriggers,
            footer: .mobileControlsAdaptiveTriggersFooter
        ) {
            MobileToggleRow(.mobileControlsAdaptiveTriggers, isOn: binding(\.adaptiveTriggersEnabled))
                .disabled(!device.adaptiveTriggers)
            MobilePickerRow(
                .mobileControlsTriggerStrength,
                selection: binding(\.triggerStrength),
                choices: TriggerStrength.allCases
            ) { strength in
                strength.title
            }
            .disabled(!device.adaptiveTriggers || !preferences.adaptiveTriggersEnabled)
        }
    }

    private var nintendoLabels: Binding<Bool> {
        Binding(
            get: {
                preferences.buttonLayout == .label
            },
            set: { enabled in
                var changed = preferences
                changed.buttonLayout = enabled
                    ? .label
                    : .position
                update(changed)
            }
        )
    }

    private func slider(
        _ title: LocalizedStringResource,
        key: WritableKeyPath<ControllerPreferences, Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        MobileSliderRow(
            title: title,
            verbatimValue: preferences[keyPath: key].formatted(.percent.precision(.fractionLength(0))),
            value: binding(key),
            range: range,
            step: step
        )
    }

    private func binding<Value>(_ key: WritableKeyPath<ControllerPreferences, Value>) -> Binding<Value> {
        Binding(
            get: {
                preferences[keyPath: key]
            },
            set: { value in
                var changed = preferences
                changed[keyPath: key] = value
                update(changed)
            }
        )
    }
}

/// A Light Bar group: how a light bar is coloured, the colour swatches while a fixed colour is chosen, and a
/// footer explaining the result.
private struct MobileLightbarGroup: View {
    /// A sentence put before the explanation.
    enum Note {
        /// The group is the setting every controller without its own light bar setting uses.
        case allControllers

        /// The controller has no light bar to set.
        case noLightBar
    }

    /// A sentence put before the explanation, or `nil` for none.
    let note: Note?

    /// The current setting, or `nil` when deferring to the setting for all controllers.
    let value: ControllerLightbar?

    /// The setting for all controllers; when `nil` this group is that setting, so the option to defer is
    /// hidden.
    let inherited: ControllerLightbar?

    /// Whether the controller has a light bar to set.
    var enabled = true

    /// Called with the new setting, `nil` meaning defer to all controllers.
    let update: (ControllerLightbar?) -> Void

    @State private var lastFixed: UInt32?

    var body: some View {
        MobileSettingsGroup(.mobileControlsLightBar, footer: footer) {
            MobilePickerRow(.mobileControlsColour, selection: mode, choices: modes) { mode in
                mode.title
            }
            if case .fixed(let selected) = value {
                swatches(selected: selected)
            }
        }
        .disabled(!enabled)
        .onChange(of: value, initial: true) { _, current in
            if case .fixed(let rgb) = current {
                lastFixed = rgb
            }
        }
    }

    private var modes: [LightbarMode] {
        inherited == nil
            ? [.followGame, .fixed]
            : LightbarMode.allCases
    }

    private var mode: Binding<LightbarMode> {
        Binding(
            get: {
                LightbarMode(value)
            },
            set: { next in
                switch next {
                case .allControllers:
                    update(nil)
                case .followGame:
                    update(.followGame)
                case .fixed:
                    update(.fixed(rgb: lastFixed ?? fixedColor ?? ControllerLightbarSwatch.all[0].rgb))
                }
            }
        )
    }

    private var fixedColor: UInt32? {
        if case .fixed(let rgb) = value {
            return rgb
        }
        if case .fixed(let rgb) = inherited {
            return rgb
        }
        return nil
    }

    private var footer: LocalizedStringResource {
        switch (note, value) {
        case (nil, nil):
            inherited == .followGame
                ? .mobileLightBarInheritedFollow
                : .mobileLightBarInheritedFixed
        case (nil, .followGame):
            .mobileLightBarFollowGame
        case (nil, .fixed):
            .mobileLightBarFixed
        case (.allControllers, nil):
            inherited == .followGame
                ? .mobileLightBarSharedInheritedFollow
                : .mobileLightBarSharedInheritedFixed
        case (.allControllers, .followGame):
            .mobileLightBarSharedFollowGame
        case (.allControllers, .fixed):
            .mobileLightBarSharedFixed
        case (.noLightBar, nil):
            inherited == .followGame
                ? .mobileLightBarMissingInheritedFollow
                : .mobileLightBarMissingInheritedFixed
        case (.noLightBar, .followGame):
            .mobileLightBarMissingFollowGame
        case (.noLightBar, .fixed):
            .mobileLightBarMissingFixed
        }
    }

    private func swatches(selected: UInt32) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(ControllerLightbarSwatch.all) { swatch in
                FocusButton {
                    update(.fixed(rgb: swatch.rgb))
                } label: {
                    swatchLabel(swatch, selected: swatch.rgb == selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(swatch.name))
                .accessibilityAddTraits(
                    swatch.rgb == selected
                        ? .isSelected
                        : []
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func swatchLabel(_ swatch: ControllerLightbarSwatch, selected: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        swatch.rgb == 0
                            ? Color.secondary.opacity(0.15)
                            : CouchLight.color(swatch.rgb) ?? .clear
                    )
                Circle()
                    .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                if swatch.rgb == 0 {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(.secondary)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            swatch.rgb == 0xffffff || swatch.rgb == 0
                                ? Color.primary
                                : Color.white
                        )
                }
            }
            .frame(width: 32, height: 32)
            Text(swatch.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
}

/// A row choosing whose bindings are shown: a picture, a name, status lines and a check mark when chosen.
private struct MobileControlsTargetRow<Icon: View>: View {
    /// The name.
    let title: Text

    /// The status lines under the name.
    let lines: [Text]

    /// Whether the row's bindings are shown.
    let selected: Bool

    /// A short label at the trailing edge, or `nil` for none.
    var tag: LocalizedStringResource?

    /// The picture at the leading edge.
    @ViewBuilder let icon: Icon

    /// Shows the row's bindings.
    let choose: () -> Void

    var body: some View {
        FocusButton(action: choose) {
            HStack(spacing: 12) {
                icon
                    .frame(width: 44, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            line
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let tag {
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.accent, in: .capsule)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(MobileRowFocus.shape)
        .accessibilityAddTraits(
            selected
                ? .isSelected
                : []
        )
    }
}
