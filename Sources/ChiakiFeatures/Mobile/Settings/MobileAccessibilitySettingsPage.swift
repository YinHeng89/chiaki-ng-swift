import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// The Accessibility page in the touch library: the PlayStation accessibility settings a cloud console uses for
/// its system menus, saved for the next cloud stream launch.
struct MobileAccessibilitySettingsPage: View {
    private let store: StoreOf<PersistedSettingFeature<PlayStationAccessibilitySettings>>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings, scoped to the persisted PlayStation accessibility settings.
    init(settings: StoreOf<SettingsFeature>) {
        store = settings.scope(state: \.playStationAccessibility, action: \.playStationAccessibility)
    }

    var body: some View {
        MobileSettingsForm {
            Group {
                screenReaderGroup
                speechGroup
            }
            .disabled(!store.isEditable)
        } trailing: {
            Group {
                displayGroup
                deviceGroup
                SettingsPersistenceBanner(store.setting, subject: .mobileAccessibilityPersistenceSubject) {
                    store.send(.retry)
                }
            }
            .disabled(!store.isEditable)
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    private var screenReaderGroup: some View {
        MobileSettingsGroup(
            .mobileAccessibilityPlayStation,
            footer: .mobileAccessibilityPlayStationFooter
        ) {
            MobileToggleRow(
                .mobileAccessibilityScreenReader,
                isOn: choice(\.screenReaderOverride, default: \.screenReader)
            )
        }
    }

    private var speechGroup: some View {
        MobileSettingsGroup(
            .mobileAccessibilitySpeech,
            footer: .mobileAccessibilitySpeechFooter
        ) {
            MobileSliderRow(
                title: .mobileAccessibilitySpeechSpeed,
                valueText: Self.speedName(store.draft.screenReaderSpeed),
                value: level(\.screenReaderSpeed),
                range: Self.sliderRange(PlayStationAccessibilitySettings.speedRange),
                step: 1
            )
            .accessibilityValue(Text(Self.speedName(store.draft.screenReaderSpeed)))
            MobileSliderRow(
                title: .mobileAccessibilityVoiceVolume,
                verbatimValue: "\(store.draft.screenReaderVolume)",
                value: level(\.screenReaderVolume),
                range: Self.sliderRange(PlayStationAccessibilitySettings.volumeRange),
                step: 1
            )
            .accessibilityValue("\(store.draft.screenReaderVolume)")
        }
    }

    private var displayGroup: some View {
        MobileSettingsGroup(
            .mobileAccessibilityDisplay,
            footer: .mobileAccessibilityDisplayFooter
        ) {
            MobilePickerRow(
                .mobileAccessibilityTextSize,
                selection: textSize,
                choices: Array(PlayStationAccessibilitySettings.textSizeRange)
            ) { size in
                Self.textSizeName(size)
            }
            MobileToggleRow(
                .mobileAccessibilityBoldText,
                isOn: choice(\.boldTextOverride, default: \.boldText)
            )
            MobileToggleRow(
                .mobileAccessibilityHigherContrast,
                isOn: choice(\.higherContrastOverride, default: \.higherContrast)
            )
        }
    }

    private var deviceGroup: some View {
        MobileSettingsGroup(
            footer: .mobileAccessibilityDeviceFooter
        ) {
            MobileButtonRow(.mobileAccessibilityUseDevice) {
                store.send(.edit(PlayStationAccessibilitySettings()))
            }
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

    private static func sliderRange(_ range: ClosedRange<Int>) -> ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }

    private static func speedName(_ speed: Int) -> LocalizedStringResource {
        switch speed {
        case 0...2:
            .mobileAccessibilitySpeedSlow(level: 3 - speed)
        case 3:
            .mobileAccessibilitySpeedStandard
        default:
            .mobileAccessibilitySpeedFast(level: speed - 3)
        }
    }

    private static func textSizeName(_ size: Int) -> LocalizedStringResource {
        switch size {
        case -1:
            .mobileAccessibilityTextSizeSmall
        case 1:
            .mobileAccessibilityTextSizeLarge
        case 2:
            .mobileAccessibilityTextSizeVeryLarge
        default:
            .mobileAccessibilityTextSizeStandard
        }
    }
}
