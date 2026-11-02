import ChiakiClients
import ChiakiModels
import PlatformUI
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// Shows a player's controller or keyboard settings over the stream, with a switch between them when the
/// player uses both.
struct CouchControlsOverlay: View {
    /// The menu navigator that routes controller input to the overlay.
    @Environment(\.menuNavigator) var navigator
    /// The controller layer that captures a button for a binding.
    @Environment(\.controllerNavigation) var controllerNavigation
    /// The couch, which owns the open settings.
    let store: StoreOf<CouchReducer>
    /// The overlay's focusable controls outside the settings.
    enum Focus: Hashable {
        /// The Done button.
        case done
    }

    @State private var presentationID = UUID()
    @State private var captureID: UUID?
    @State private var hostWindow: PlatformWindow?
    @MenuFocusState private var focus: Focus?
    @MenuFocusState private var inputFocus: Bool?
    @MenuFocusState private var presetNameFocus: Bool
    @Environment(\.screenLayout) private var layout

    var body: some View {
        if let pad = store.controlsPad, let device = store.controlsDevice,
           let controls = store.scope(
               state: \.overlay?.controls?.settings,
               action: \.overlay.presented.controls.settings
           ) {
            ZStack {
                Dimming.standard.color
                VStack(alignment: .leading, spacing: 18) {
                    header(pad: pad, device: device)
                    if store.state.devices(of: pad).count > 1 {
                        FocusableSegments(
                            options: [false, true],
                            title: { keyboard in
                                keyboard
                                    ? "Keyboard"
                                    : "Controller"
                            },
                            selection: Binding(
                                get: { device.isKeyboard },
                                set: { store.send(.showKeyboardControls($0)) }
                            ),
                            focus: $inputFocus
                        )
                        .frame(maxWidth: 280, alignment: .leading)
                    }
                    if controls.isEditable {
                        ScrollView {
                            ControlsTargetPanel(
                                store: controls,
                                nameFocus: $presetNameFocus,
                                nameFocused: presetNameFocus
                            )
                            .padding(.vertical, 4)
                            .onAppear {
                                controls.send(.show(target(controls, pad: pad, device: device)))
                            }
                            .onChange(of: device.preferenceKey) { _, _ in
                                controls.send(.show(target(controls, pad: pad, device: device)))
                            }
                        }
                        .scrollIndicators(.automatic)
                        .frame(maxHeight: 560)
                    } else if case .loadFailed = controls.setting {
                        Text("Controls couldn’t load.")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                    footer(controls, pad: pad)
                }
                .padding(layout.isCompact
                    ? 18
                    : 28)
                    .frame(maxWidth: 1080)
                    .glassPanel(.modal)
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
                    .padding(.horizontal, layout.isCompact
                        ? max(16, layout.sideInset)
                        : 40)
                        .padding(.vertical, layout.isShort
                            ? 16
                            : 40)
            }
            .background(KeyBindingCapture(capture: keyCapture(controls)) { id, code, label in
                controls.send(.captured(id, code, label))
            } cancel: {
                controls.send(.cancelCapture)
            })
            .background(WindowAccessor { hostWindow = $0 })
            .menuInputBlocking()
            .menuHandlers(move: focusMove, back: back)
            .onAppear {
                focusInitial(hasInputChoice: store.state.devices(of: pad).count > 1)
            }
            .onDisappear {
                endCapture()
            }
            .onChange(of: controls.capture) { _, capture in
                updateCapture(capture, device: device, store: controls)
            }
        }
    }

    private func keyCapture(_ controls: StoreOf<ControlsSettingsFeature>) -> ControlsCapture? {
        guard let capture = controls.capture, capture.source == .macKey else {
            return nil
        }
        return capture
    }

    private func header(pad: UInt8, device: ControllerDevice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule()
                .fill(store.state.lightBar(for: pad) ?? Palette.accent)
                .frame(width: 6, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Player \(Int(pad) + 1) controls")
                    .font(.title2.weight(.semibold))
                Text(store.state.accountName(for: pad).map { "\($0) on \(device.name)" } ?? device.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func footer(_ controls: StoreOf<ControlsSettingsFeature>, pad: UInt8) -> some View {
        HStack(spacing: 14) {
            Spacer()
            if let message = controls.notice.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(CouchTone.failed.color)
            }
            FocusButton("Done") {
                store.send(.finishControls)
            }
            .glassProminentControlStyle()
            .menuFocused($focus, equals: .done)
            .disabled(controls.setting.isBusy)
        }
    }

    private func updateCapture(
        _ capture: ControlsCapture?, device: ControllerDevice,
        store controls: StoreOf<ControlsSettingsFeature>
    ) {
        endCapture()
        guard let capture, capture.source == .gamepadButton, controls.canListen else {
            return
        }
        let id = capture.id
        captureID = controllerNavigation?.beginButtonCapture(device: device.id) { outcome in
            switch outcome {
            case .assign(let code):
                controls.send(.captured(id, code, ""))
            case .cancel:
                controls.send(.cancelCapture)
            }
        }
    }

    private func endCapture() {
        if let captureID {
            controllerNavigation?.endButtonCapture(captureID)
        }
        captureID = nil
    }

    private func focusInitial(hasInputChoice: Bool) {
        Task { @MainActor in
            for _ in 0..<10 {
                await Task.yield()
                guard let window = hostWindow else {
                    try? await Task.sleep(for: .milliseconds(30))
                    continue
                }
                if navigator?.hasControlFocus(in: window) == true {
                    return
                }
                if hasInputChoice {
                    inputFocus = store.controlsDevice?.isKeyboard ?? false
                } else {
                    navigator?.ensureControlFocused(in: window)
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func focusMove(_ window: PlatformWindow, _ direction: MenuMoveDirection) -> Bool {
        guard window === hostWindow, store.controls?.capture == nil,
              !(navigator?.isEditingText(in: window) ?? false) else {
            return false
        }
        if !(navigator?.hasControlFocus(in: window) ?? false) {
            navigator?.ensureControlFocused(in: window)
            return true
        }
        navigator?.moveGeometric(direction, in: window, allowUnaligned: direction.isVertical)
        return true
    }

    private func back(_ window: PlatformWindow) -> Bool {
        guard window === hostWindow, store.controls?.capture == nil else {
            return false
        }
        store.send(.finishControls)
        return true
    }
}

extension CouchControlsOverlay {
    /// Whose bindings the overlay edits for a seat: the keyboard, the seated player's own bindings when they
    /// have them, otherwise the seated controller's.
    ///
    /// - Parameters:
    ///   - controls: The open controls settings.
    ///   - pad: The seat's pad, 0 for player 1.
    ///   - device: The seated controller or the keyboard.
    /// - Returns: The edit target.
    func target(_ controls: StoreOf<ControlsSettingsFeature>, pad: UInt8,
                device: ControllerDevice) -> ControlsEditTarget {
        if device.isKeyboard {
            return .keyboard
        }
        if controls.draft.playerPreset(Int(pad)) != nil {
            return .player(Int(pad))
        }
        return .controller(device.preferenceKey)
    }
}
