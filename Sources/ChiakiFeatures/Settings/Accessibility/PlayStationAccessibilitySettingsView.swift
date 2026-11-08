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
            Text(.settingsAccessibilityTitle).font(.headline)
            Toggle(
                .settingsAccessibilityScreenReader,
                isOn: choice(\.screenReaderOverride, default: \.screenReader)
            )
            Text(.settingsAccessibilityScreenReaderFooter)
                .font(.caption).foregroundStyle(.secondary)
            valueSlider(
                .settingsAccessibilitySpeechSpeed,
                value: level(\.screenReaderSpeed),
                range: PlayStationAccessibilitySettings.speedRange,
                display: String(localized: Self.speedName(store.draft.screenReaderSpeed))
            )
            valueSlider(
                .settingsAccessibilityVoiceVolume,
                value: level(\.screenReaderVolume),
                range: PlayStationAccessibilitySettings.volumeRange,
                display: "\(store.draft.screenReaderVolume)"
            )
            Text(.settingsAccessibilitySpeechFooter)
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(.settingsAccessibilityTextSize)
                FocusableSegments(
                    options: Array(PlayStationAccessibilitySettings.textSizeRange),
                    title: Self.textSizeName,
                    selection: textSize
                )
                .accessibilityLabel(.settingsAccessibilityTextSize)
            }
            Toggle(.settingsAccessibilityBoldText, isOn: choice(\.boldTextOverride, default: \.boldText))
            Toggle(
                .settingsAccessibilityHigherContrast,
                isOn: choice(\.higherContrastOverride, default: \.higherContrast)
            )
            Text(.settingsAccessibilityScopeFooter)
                .font(.caption).foregroundStyle(.secondary)
            FocusButton(.settingsAccessibilityUseDeviceSettings) {
                store.send(.edit(PlayStationAccessibilitySettings()))
            }
            Text(.settingsAccessibilityDeviceSettingsFooter)
                .font(.caption).foregroundStyle(.secondary)
            Text(.settingsAccessibilityNextLaunchFooter)
                .font(.caption).foregroundStyle(.secondary)
            SettingsPersistenceBanner(store.setting, subject: .settingsAccessibilityPersistenceSubject) {
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
        _ title: LocalizedStringResource,
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

    private static func speedName(_ speed: Int) -> LocalizedStringResource {
        switch speed {
        case 0...2:
            .settingsAccessibilitySpeedSlow(level: 3 - speed)
        case 3:
            .settingsAccessibilitySpeedStandard
        default:
            .settingsAccessibilitySpeedFast(level: speed - 3)
        }
    }

    private static func textSizeName(_ size: Int) -> LocalizedStringResource {
        switch size {
        case -1:
            .settingsAccessibilityTextSizeSmall
        case 1:
            .settingsAccessibilityTextSizeLarge
        case 2:
            .settingsAccessibilityTextSizeVeryLarge
        default:
            .settingsAccessibilityTextSizeStandard
        }
    }
}
