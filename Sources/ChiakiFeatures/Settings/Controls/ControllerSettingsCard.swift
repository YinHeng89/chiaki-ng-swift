import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// One controller's own settings beside its bindings, in Calibration, Feedback and Details sections.
///
/// A disconnected controller keeps its settings visible, but only its details can change until it is back.
struct ControllerSettingsCard: View {
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
    var connected = true
    /// The light bar setting inherited when this controller does not choose its own.
    var lightbar = ControllerLightbar.followGame
    @State private var section = 0
    @MenuFocusState private var nicknameFocused: Bool
    private var family: ControllerFamily {
        device.family
    }

    /// The section picker and the chosen section.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FocusableSegments(options: [0, 1, 2], title: { option in
                switch option {
                case 0:
                    .settingsControlsSectionCalibration
                case 1:
                    .settingsControlsSectionFeedback
                default:
                    .settingsControlsSectionDetails
                }
            }, selection: $section)
            FlowTransition(selection: section) {
                VStack(alignment: .leading, spacing: 24) {
                    switch section {
                    case 0:
                        calibration.disabled(!connected)
                    case 1:
                        feedback.disabled(!connected)
                    default:
                        details
                    }
                }
                .frame(maxWidth: 760, alignment: .topLeading)
                .padding(24)
                .settingsPanel()
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(.settingsControlsSectionDetails).font(.headline)
            TextField(.settingsControlsNickname, text: binding(\.nickname))
                .textFieldStyle(.roundedBorder)
                .menuFocusBinding($nicknameFocused)
                .controllerKeyboard(
                    title: .settingsControlsNicknameKeyboardTitle,
                    text: binding(\.nickname),
                    isFocused: nicknameFocused
                )
            if !device.individual {
                Text(.settingsControlsSharedIdentity)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(.settingsControlsSectionFeedback).font(.headline)
            HStack(spacing: 18) {
                Text(.settingsControlsHaptics).frame(width: 125, alignment: .leading)
                FocusableSegments(
                    options: HapticFeedback.allCases,
                    title: \.title,
                    selection: binding(\.hapticFeedback)
                )
                .disabled(!device.nativeHaptics && !device.rumble)
            }
            slider(.settingsControlsHapticStrength, key: \.hapticStrength, range: 0...2.4, step: 0.1)
                .disabled(!device.nativeHaptics && !device.rumble)
            slider(.settingsControlsRumbleStrength, key: \.rumbleStrength).disabled(!device.rumble)
            VStack(alignment: .leading, spacing: 4) {
                Text(hapticsCaption)
                Text(.settingsControlsStrengthsFollowConsole)
                Text(.settingsControlsHapticsPlayerOne)
            }
            .font(.callout).foregroundStyle(.secondary)
            Toggle(.settingsControlsAdaptiveTriggers, isOn: binding(\.adaptiveTriggersEnabled))
                .disabled(!device.adaptiveTriggers)
            triggerStrength
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(.settingsControlsLightBar)
                LightbarChooser(
                    value: preferences.lightbar,
                    inherited: lightbar,
                    update: { value in
                        var changed = preferences
                        changed.lightbar = value
                        update(changed)
                    },
                    enabled: device.lights
                )
                if !device.lights {
                    Text(.settingsControlsNoLightBar)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text(.settingsControlsTestFeedback)
                Spacer()
                FocusButton(.settingsControlsTestRumble, systemImage: "waveform") {
                    test(preferences.rumbleStrength)
                }
                .glassControlStyle().disabled(!device.rumble)
            }
        }
    }
}

extension ControllerSettingsCard {
    private func slider(_ label: LocalizedStringResource, key: WritableKeyPath<ControllerPreferences, Double>,
                        range: ClosedRange<Double> = 0...1, step: Double = 0.05) -> some View {
        HStack(spacing: 18) {
            Text(label).frame(width: 125, alignment: .leading)
            Slider(value: binding(key), in: range, step: step)
                .nativeFocusHighlight()
                .focusHighlightShape(.capsule)
                .settingsSliderController(value: binding(key))
            Text(preferences[keyPath: key], format: .percent.precision(.fractionLength(0)))
                .monospacedDigit().frame(width: 44)
        }
    }
    private func binding<Value>(_ key: WritableKeyPath<ControllerPreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences[keyPath: key] }, set: { value in
            var changed = preferences
            changed[keyPath: key] = value
            update(changed)
        })
    }
}

extension View {
    /// Gives the view the translucent rounded background and hairline border used by the controls settings
    /// panels.
    func settingsPanel() -> some View {
        background(.background.opacity(0.55), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07))
            }
    }
}

extension ControllerSettingsCard {
    /// Explains where haptics go on this controller: its own actuators, its rumble motors, or nowhere.
    var hapticsCaption: LocalizedStringResource {
        switch preferences.hapticOutput(for: device) {
        case .native:
            .settingsControlsHapticsNative
        case .rumble:
            .settingsControlsHapticsAsRumble
        case .none:
            preferences.hapticFeedback == .off
                ? .settingsControlsHapticsGameRumbleOnly
                : .settingsControlsHapticsNoMotors
        }
    }
}

extension ControllerSettingsCard {
    /// The trigger strength row, usable only while the controller plays adaptive trigger effects.
    var triggerStrength: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Text(.settingsControlsTriggerStrength).frame(width: 125, alignment: .leading)
                FocusableSegments(
                    options: TriggerStrength.allCases,
                    title: \.title,
                    selection: binding(\.triggerStrength)
                )
                .disabled(!device.adaptiveTriggers || !preferences.adaptiveTriggersEnabled)
            }
            Text(.settingsControlsTriggerStrengthFooter)
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension TriggerStrength {
    /// The label shown for this trigger strength in the settings segments.
    var title: LocalizedStringResource {
        switch self {
        case .strong:
            .settingsControlsTriggerStrong
        case .medium:
            .settingsControlsTriggerMedium
        case .weak:
            .settingsControlsTriggerWeak
        }
    }
}

extension HapticFeedback {
    /// The label shown for this haptic feedback mode in the settings segments.
    var title: LocalizedStringResource {
        switch self {
        case .automatic:
            .commonAutomatic
        case .rumble:
            .settingsControlsHapticModeRumble
        case .off:
            .commonOff
        }
    }
}

extension ControllerSettingsCard {
    /// The Calibration section: stick dead zone, stick inversion and swap, Nintendo button layout and right
    /// stick gyro mode.
    var calibration: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(.settingsControlsSectionCalibration).font(.headline)
            slider(.settingsControlsStickDeadZone, key: \.deadZone, range: 0...0.5, step: 0.01)
            Toggle(.settingsControlsInvertRightStick, isOn: binding(\.invertRightY))
            Toggle(.settingsControlsSwapSticks, isOn: binding(\.swapSticks))
            if family == .nintendo {
                ButtonLayoutChoice(preferences: preferences, update: update)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Text(.settingsControlsRightStickGyro).frame(width: 125, alignment: .leading)
                    FocusableSegments(
                        options: StickGyroMode.allCases,
                        title: \.title,
                        selection: binding(\.stickGyro)
                    )
                }
                Text(stickGyroCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(idealWidth: 360, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Explains what the right stick does under the chosen gyro mode, naming the bound gyro hold button when
    /// there is one.
    var stickGyroCaption: LocalizedStringResource {
        switch preferences.stickGyro.resolved(sensors: device.motion) {
        case .off, .automatic:
            return preferences.stickGyro == .automatic
                ? .settingsControlsGyroOwnSensor
                : .settingsControlsGyroOffCaption
        case .whileHeld:
            guard let button = gyroHoldButton else {
                return .settingsControlsGyroNoHoldButton
            }
            return .settingsControlsGyroWhileHeldCaption(button: button, sameButton: button)
        case .always:
            return .settingsControlsGyroAlwaysCaption
        }
    }

    private var gyroHoldButton: String? {
        preset.bindings.first {
            $0.source == .gamepadButton && $0.target == .gyroHold
        }.map {
            let glyph = ControllerGlyphs.button($0.code, family: family, layout: preferences.buttonLayout)
            return String(localized: glyph.name)
        }
    }
}

extension StickGyroMode {
    /// The label shown for this right stick gyro mode in the settings segments.
    var title: LocalizedStringResource {
        switch self {
        case .automatic:
            .commonAutomatic
        case .off:
            .commonOff
        case .whileHeld:
            .settingsControlsGyroWhileHeld
        case .always:
            .settingsControlsGyroAlways
        }
    }
}

/// A toggle that switches a Nintendo-style controller between position-based and label-based button mapping,
/// with a caption explaining which button confirms.
public struct ButtonLayoutChoice: View {
    /// The controller preferences being edited.
    public let preferences: ControllerPreferences
    /// Called with the preferences after the button layout changes.
    public let update: (ControllerPreferences) -> Void

    /// Creates a button layout choice.
    ///
    /// - Parameters:
    ///   - preferences: The controller preferences being edited.
    ///   - update: Called with the preferences after the button layout changes.
    public init(preferences: ControllerPreferences, update: @escaping (ControllerPreferences) -> Void) {
        self.preferences = preferences
        self.update = update
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(.settingsControlsNintendoLabels, isOn: labels)
            Text(preferences.buttonLayout == .label
                ? .settingsControlsNintendoLabelsOn
                : .settingsControlsNintendoLabelsOff)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(idealWidth: 360, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var labels: Binding<Bool> {
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
}
