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
                    "Calibration"
                case 1:
                    "Feedback"
                default:
                    "Details"
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
            Text("Details").font(.headline)
            TextField("Nickname", text: binding(\.nickname))
                .textFieldStyle(.roundedBorder)
                .menuFocusBinding($nicknameFocused)
                .controllerKeyboard(
                    title: "Controller nickname",
                    text: binding(\.nickname),
                    isFocused: nicknameFocused
                )
            if !device.individual {
                Text("This controller has no unique identity. Preferences are shared with its model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Feedback").font(.headline)
            HStack(spacing: 18) {
                Text("Haptics").frame(width: 125, alignment: .leading)
                FocusableSegments(
                    options: HapticFeedback.allCases,
                    title: \.title,
                    selection: binding(\.hapticFeedback)
                )
                .disabled(!device.nativeHaptics && !device.rumble)
            }
            slider("Haptic strength", key: \.hapticStrength, range: 0...2.4, step: 0.1)
                .disabled(!device.nativeHaptics && !device.rumble)
            slider("Rumble strength", key: \.rumbleStrength).disabled(!device.rumble)
            VStack(alignment: .leading, spacing: 4) {
                Text(hapticsCaption)
                Text("Both strengths follow the vibration intensity set on the PS5.")
                Text("The console sends haptics only to player 1's controller.")
            }
            .font(.callout).foregroundStyle(.secondary)
            Toggle("Adaptive triggers", isOn: binding(\.adaptiveTriggersEnabled))
                .disabled(!device.adaptiveTriggers)
            triggerStrength
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Light bar")
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
                    Text("This controller has no light bar to set.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("Test feedback")
                Spacer()
                FocusButton("Rumble", systemImage: "waveform") { test(preferences.rumbleStrength) }
                    .glassControlStyle().disabled(!device.rumble)
            }
        }
    }
}

extension ControllerSettingsCard {
    private func slider(_ label: String, key: WritableKeyPath<ControllerPreferences, Double>,
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
    var hapticsCaption: String {
        switch preferences.hapticOutput(for: device) {
        case .native:
            "Haptics play on the DualSense's own actuators and fall back to its rumble motors"
                + " if those cannot be used."
        case .rumble:
            "Haptics are turned into rumble on this controller's motors."
        case .none:
            preferences.hapticFeedback == .off
                ? "Only the game's rumble reaches this controller."
                : "This controller has no motors to play haptics."
        }
    }
}

extension ControllerSettingsCard {
    /// The trigger strength row, usable only while the controller plays adaptive trigger effects.
    var triggerStrength: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                Text("Trigger strength").frame(width: 125, alignment: .leading)
                FocusableSegments(
                    options: TriggerStrength.allCases,
                    title: \.title,
                    selection: binding(\.triggerStrength)
                )
                .disabled(!device.adaptiveTriggers || !preferences.adaptiveTriggersEnabled)
            }
            Text("Trigger strength never goes above the intensity set on the PS5.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension TriggerStrength {
    /// The label shown for this trigger strength in the settings segments.
    var title: String {
        switch self {
        case .strong:
            "Strong"
        case .medium:
            "Medium"
        case .weak:
            "Weak"
        }
    }
}

extension HapticFeedback {
    /// The label shown for this haptic feedback mode in the settings segments.
    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .rumble:
            "Rumble"
        case .off:
            "Off"
        }
    }
}

extension ControllerSettingsCard {
    /// The Calibration section: stick dead zone, stick inversion and swap, Nintendo button layout and right
    /// stick gyro mode.
    var calibration: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Calibration").font(.headline)
            slider("Stick dead zone", key: \.deadZone, range: 0...0.5, step: 0.01)
            Toggle("Invert right stick vertically", isOn: binding(\.invertRightY))
            Toggle("Swap left and right sticks", isOn: binding(\.swapSticks))
            if family == .nintendo {
                ButtonLayoutChoice(preferences: preferences, update: update)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Text("Right stick gyro").frame(width: 125, alignment: .leading)
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
    var stickGyroCaption: String {
        switch preferences.stickGyro.resolved(sensors: device.motion) {
        case .off, .automatic:
            return preferences.stickGyro == .automatic
                ? "This controller has its own gyro, so the right stick keeps moving the camera."
                : "The right stick moves the camera. Choose While held or Always to aim the game's motion "
                    + "controls with it."
        case .whileHeld:
            guard let button = gyroHoldButton else {
                return "Bind a button to Gyro (hold) above, then hold it to turn the controller with "
                    + "the right stick."
            }
            return "Hold \(button) and move the right stick to turn the controller instead of the camera. A "
                + "quick press of \(button) still does what it normally does."
        case .always:
            return "The right stick always turns the controller for the game's motion controls and no longer "
                + "moves the camera."
        }
    }

    private var gyroHoldButton: String? {
        preset.bindings.first {
            $0.source == .gamepadButton && $0.target == .gyroHold
        }.map {
            ControllerGlyphs.button($0.code, family: family, layout: preferences.buttonLayout).name
        }
    }
}

extension StickGyroMode {
    /// The label shown for this right stick gyro mode in the settings segments.
    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .off:
            "Off"
        case .whileHeld:
            "While held"
        case .always:
            "Always"
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
            Toggle("Use Nintendo button labels", isOn: labels)
            Text(preferences.buttonLayout == .label
                ? "A acts as Cross and B as Circle, so A confirms like on Switch. X and Y swap the same way."
                : "Buttons work by position: the bottom button, B, acts as Cross and confirms.")
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
