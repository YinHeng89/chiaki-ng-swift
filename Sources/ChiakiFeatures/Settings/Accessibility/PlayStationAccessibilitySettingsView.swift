import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The PlayStation accessibility settings a cloud console uses for its system menus.
///
/// The screen reader, text size, bold text and higher contrast follow the device until changed here; speech
/// speed and voice volume use PlayStation's defaults. Every change is saved for the next cloud stream launch.
public struct PlayStationAccessibilitySettingsView: View {
    /// The persisted PlayStation accessibility settings being edited.
    @Bindable public var store: StoreOf<PersistedSettingFeature<PlayStationAccessibilitySettings>>

    /// Creates the view.
    ///
    /// - Parameter store: The persisted PlayStation accessibility settings being edited.
    public init(store: StoreOf<PersistedSettingFeature<PlayStationAccessibilitySettings>>) {
        self.store = store
    }

    /// The choices, their explanations and the button that returns to the device's preferences.
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PlayStation accessibility").font(.headline)
            Toggle("Screen reader", isOn: choice(\.screenReaderOverride, default: \.screenReader))
            Text(
                "Reads PlayStation cloud system menus, including the Create menu "
                    + "and in-game purchase screens. A game may have separate narration settings."
            )
            .font(.caption).foregroundStyle(.secondary)
            valueSlider(
                "Speech speed",
                value: level(\.screenReaderSpeed),
                range: PlayStationAccessibilitySettings.speedRange,
                display: Self.speedName(store.draft.screenReaderSpeed)
            )
            valueSlider(
                "Voice volume",
                value: level(\.screenReaderVolume),
                range: PlayStationAccessibilitySettings.volumeRange,
                display: "\(store.draft.screenReaderVolume)"
            )
            Text(
                "Speech speed and voice volume control the PlayStation screen reader. "
                    + "They do not change game audio or a game’s own narration settings."
            )
            .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Text size")
                FocusableSegments(
                    options: Array(PlayStationAccessibilitySettings.textSizeRange),
                    title: Self.textSizeName,
                    selection: textSize
                )
                .accessibilityLabel("Text size")
            }
            Toggle("Bold text", isOn: choice(\.boldTextOverride, default: \.boldText))
            Toggle("Higher contrast", isOn: choice(\.higherContrastOverride, default: \.higherContrast))
            Text(
                "These settings apply to PlayStation cloud system menus. "
                    + "Each game decides which settings it also uses."
            )
            .font(.caption).foregroundStyle(.secondary)
            FocusButton("Use device accessibility settings") {
                store.send(.edit(PlayStationAccessibilitySettings()))
            }
            Text(
                "Available device accessibility preferences are used until changed here. "
                    + "Screen reader speech speed and voice volume use PlayStation defaults."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text("Requests these settings for the PlayStation cloud console at the next stream launch.")
                .font(.caption).foregroundStyle(.secondary)
            SettingsPersistenceBanner(store.setting, subject: "PlayStation accessibility settings") {
                store.send(.retry)
            }
        }
        .disabled(!store.isEditable)
        .onAppear {
            store.send(.appeared)
        }
    }

    private func choice(
        _ key: WritableKeyPath<PlayStationAccessibilitySettings, Bool?>,
        default defaultKey: KeyPath<PlayStationAccessibilityDefaults, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                store.draft[keyPath: key]
                    ?? PlayStationAccessibilitySystemDefaults.current[keyPath: defaultKey]
            },
            set: { enabled in
                var draft = store.draft
                draft[keyPath: key] = enabled
                store.send(.edit(draft))
            }
        )
    }

    private func level(_ key: WritableKeyPath<PlayStationAccessibilitySettings, Int>) -> Binding<Double> {
        Binding(
            get: {
                Double(store.draft[keyPath: key])
            },
            set: { value in
                var draft = store.draft
                draft[keyPath: key] = Int(value)
                store.send(.edit(draft))
            }
        )
    }

    private var textSize: Binding<Int> {
        Binding(
            get: {
                store.draft.textSizeOverride
                    ?? PlayStationAccessibilitySystemDefaults.current.textSize
            },
            set: { size in
                var draft = store.draft
                draft.textSizeOverride = size
                store.send(.edit(draft))
            }
        )
    }

    private func valueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Int>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit()
            }
            Slider(value: value, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .nativeFocusHighlight()
                .focusHighlightShape(.capsule)
                .accessibilityLabel(title)
                .accessibilityValue(display)
                .settingsSliderController(value: value)
        }
    }

    private static func speedName(_ speed: Int) -> String {
        switch speed {
        case 0...2:
            "Slow \(3 - speed)"
        case 3:
            "Standard"
        default:
            "Fast \(speed - 3)"
        }
    }

    private static func textSizeName(_ size: Int) -> String {
        switch size {
        case -1:
            "Small"
        case 1:
            "Large"
        case 2:
            "Very large"
        default:
            "Standard"
        }
    }
}
