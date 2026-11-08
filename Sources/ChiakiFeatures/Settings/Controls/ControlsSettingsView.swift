import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The Controls tab: the keyboard, every remembered controller and players 1 to 4, the
/// bindings of the one chosen, and the shared shortcuts and lights.
///
/// Every change is saved as it is made and the latest can be undone. Back first ends a running capture or
/// shortcut recording; otherwise it is left to the settings panel.
struct ControlsSettingsView: View {
    /// The menu navigator used for the Back handler and to keep controller focus inside the pane when the
    /// shown bindings change.
    @Environment(\.menuNavigator) var navigator
    /// The controller layer that captures a button for a binding.
    @Environment(\.controllerNavigation) var controllerNavigation
    /// The controls settings feature the view reads and edits.
    @Bindable var store: StoreOf<ControlsSettingsFeature>
    @MenuFocusState private var presetNameFocused: Bool
    @State private var hostWindow: PlatformWindow?
    @State private var buttonCaptureID: UUID?
    @State private var focusTracker = FocusRegionTracker()

    /// Draws the tab.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            title
            ControlsTargetRows(store: store)
            ControlsTargetPanel(store: store, nameFocus: $presetNameFocused, nameFocused: presetNameFocused)
            TouchpadShortcutCard(store: store)
            StreamMenuShortcutCard(store: store)
            LightbarCard(store: store)
            #if os(macOS)
                BackgroundInputCard(store: store)
            #else
                VirtualGamepadCard(store: store)
                DeviceMotionCard(store: store)
            #endif
            if let message = store.notice.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsPersistenceBanner(
                store.setting,
                subject: .settingsControlsPersistenceSubject,
                reportsInvalid: false
            ) {
                store.send(.retry)
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
        .background(WindowAccessor { hostWindow = $0 })
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            focusTracker.globalRegion = frame
        }
        .onChange(of: hostWindow, initial: true) { _, window in
            focusTracker.observe(window, navigator: navigator)
        }
        .onChange(of: buttonCapture?.id, initial: true) { _, _ in
            updateButtonCapture()
        }
        .onChange(of: store.canListen) { _, _ in
            updateButtonCapture()
        }
        .onChange(of: store.editing) { _, _ in
            keepFocusAcrossTargetChange()
        }
        .onChange(of: store.devices.map(\.preferenceKey)) { _, _ in
            keepFocusAcrossTargetChange()
        }
        .onAppear {
            store.send(.appeared)
            #if !os(macOS)
                if store.editing == .keyboard {
                    store.send(.show(.player(0)))
                }
            #endif
        }
        .menuHandlers(back: { [store] window in
            guard window === hostWindow else {
                return false
            }
            if store.shortcutCapture != nil {
                store.send(.cancelTouchpadShortcut)
                return true
            }
            if store.capture != nil {
                store.send(.cancelCapture)
                return true
            }
            return false
        })
        .onDisappear {
            focusTracker.stop()
            endButtonCapture()
            store.send(.stop)
        }
    }

    private var title: some View {
        Text(.settingsControlsTitle).font(.system(size: 28, weight: .semibold))
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

    /// Whether a controller capture lost its device: the shown controller changed or went away.
    ///
    /// - Parameters:
    ///   - previous: The controller shown before.
    ///   - current: The controller shown now.
    /// - Returns: `true` when a capture for `previous` can no longer complete.
    static func capturedDeviceLeft(previous: UInt32?, current: UInt32?) -> Bool {
        previous != nil && previous != current
    }

    private func keepFocusAcrossTargetChange() {
        guard let window = hostWindow, focusTracker.wasInside(within: .milliseconds(400)),
              let frame = focusTracker.lastFrame else {
            return
        }
        let tracker = focusTracker
        Task { @MainActor in
            for delay in [60, 200] {
                for _ in 0..<6 {
                    await Task.yield()
                }
                try? await Task.sleep(for: .milliseconds(delay))
                guard WindowFocus(window).isOnScreen, !tracker.focusIsInside(window) else {
                    continue
                }
                navigator?.focusNearest(to: frame, in: window)
            }
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

/// A card with a toggle that keeps controllers driving the stream while another app is in front, disabled
/// when the controls draft is not editable.
private struct BackgroundInputCard: View {
    /// The controls settings feature whose draft the toggle edits.
    let store: StoreOf<ControlsSettingsFeature>

    private var enabled: Binding<Bool> {
        Binding(
            get: {
                store.draft.backgroundInput
            },
            set: { value in
                var draft = store.draft
                draft.backgroundInput = value
                store.send(.edit(draft))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(.settingsControlsBackgroundInput, isOn: enabled)
            Text(.settingsControlsBackgroundInputFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .disabled(!store.isEditable)
    }
}

/// A card with a toggle that feeds this device's motion sensors into the stream as the controller's gyro,
/// disabled when the controls draft is not editable.
private struct DeviceMotionCard: View {
    /// The controls settings feature whose draft the toggle edits.
    let store: StoreOf<ControlsSettingsFeature>

    private var enabled: Binding<Bool> {
        Binding(
            get: {
                store.draft.deviceMotion
            },
            set: { value in
                var draft = store.draft
                draft.deviceMotion = value
                store.send(.edit(draft))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(.settingsControlsDeviceMotion, isOn: enabled)
            Text(.settingsControlsDeviceMotionFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .disabled(!store.isEditable)
    }
}

/// A card that chooses when the on-screen gamepad appears over a touch stream, disabled when the controls
/// draft is not editable.
private struct VirtualGamepadCard: View {
    /// The controls settings feature whose draft the choice edits.
    @Bindable var store: StoreOf<ControlsSettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.settingsControlsOnScreenController)
                .font(.headline)
            FocusableSegments(
                options: VirtualGamepadPresence.allCases,
                title: Self.title,
                selection: $store.draft.virtualGamepad
            )
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .disabled(!store.isEditable)
    }

    private var note: LocalizedStringResource {
        switch store.draft.virtualGamepad {
        case .automatic:
            .settingsControlsGamepadAutomaticNote
        case .shown:
            .settingsControlsGamepadShownNote
        case .hidden:
            .settingsControlsGamepadHiddenNote
        }
    }

    private static func title(_ presence: VirtualGamepadPresence) -> LocalizedStringResource {
        switch presence {
        case .automatic:
            .commonAutomatic
        case .shown:
            .settingsControlsGamepadAlways
        case .hidden:
            .commonOff
        }
    }
}

/// A Controls settings card that picks the controller buttons pressed together to open the stream menu.
///
/// The button pickers share one row with their label when they fit, and otherwise wrap to two rows under it.
struct StreamMenuShortcutCard: View {
    /// The Controls settings store whose draft holds the shortcut and receives button changes.
    let store: StoreOf<ControlsSettingsFeature>
    /// The picker tag for an empty slot, which removes that slot's button from the shortcut.
    nonisolated static let unused = -1
    private static let buttonChoices = Array(0...20)

    private var buttons: [Int] {
        store.draft.streamMenuShortcut.buttons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(.settingsControlsStreamMenu).font(.headline)
            Text(.settingsControlsStreamMenuFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(.settingsControlsButtons)
                    Spacer()
                    pickers(Self.slots)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(.settingsControlsButtons)
                    HStack(spacing: 8) {
                        pickers(Self.slots.prefix(Self.slots.count / 2))
                    }
                    HStack(spacing: 8) {
                        pickers(Self.slots.dropFirst(Self.slots.count / 2))
                    }
                }
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .disabled(!store.isEditable)
    }

    private static var slots: Range<Int> {
        0..<StreamMenuShortcut.buttonLimit.upperBound
    }

    private func pickers(_ slots: some Collection<Int>) -> some View {
        ForEach(Array(slots), id: \.self) { slot in
            if slot != slots.first {
                Text("+").foregroundStyle(.secondary)
            }
            picker(slot: slot)
        }
    }

    private func picker(slot: Int) -> some View {
        Picker(.settingsControlsStreamMenuButtonPicker(number: slot + 1), selection: Binding(
            get: {
                buttons.indices.contains(slot)
                    ? buttons[slot]
                    : Self.unused
            },
            set: { code in
                store.send(.setStreamMenuButtons(Self.choosing(code, slot: slot, in: buttons)))
            }
        )) {
            if slot >= StreamMenuShortcut.buttonLimit.lowerBound {
                Text(.settingsControlsNotUsed).tag(Self.unused)
            }
            ForEach(Self.buttonChoices, id: \.self) { code in
                Text(BindingRow.buttonName(code)).tag(code)
            }
        }
        .labelsHidden()
        .nativeFocusHighlight()
        .frame(maxWidth: 150)
    }

    /// Returns the shortcut buttons after choosing `code` for one slot.
    ///
    /// Choosing ``StreamMenuShortcutCard/unused`` removes the slot, choosing a button already in another
    /// slot swaps the two, and any other button replaces the slot or is appended past the end.
    /// - Parameters:
    ///   - code: The chosen button code, or ``StreamMenuShortcutCard/unused``.
    ///   - slot: The zero-based picker slot being changed.
    ///   - current: The shortcut's buttons before the change.
    /// - Returns: The updated button list.
    nonisolated static func choosing(_ code: Int, slot: Int, in current: [Int]) -> [Int] {
        var buttons = current
        if code == unused {
            if buttons.indices.contains(slot) {
                buttons.remove(at: slot)
            }
            return buttons
        }
        if let existing = buttons.firstIndex(of: code), existing != slot {
            if buttons.indices.contains(slot) {
                buttons.swapAt(existing, slot)
            }
            return buttons
        }
        if buttons.indices.contains(slot) {
            buttons[slot] = code
        } else {
            buttons.append(code)
        }
        return buttons
    }
}
