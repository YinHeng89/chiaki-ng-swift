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
                SettingsPersistenceBanner(store.setting, subject: "PlayStation accessibility settings") {
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
            "PlayStation Accessibility",
            footer: "Reads PlayStation cloud system menus, including the Create menu "
                + "and in-game purchase screens. A game may have separate narration settings."
        ) {
            MobileToggleRow("Screen Reader", isOn: choice(\.screenReaderOverride, default: \.screenReader))
        }
    }

    private var speechGroup: some View {
        MobileSettingsGroup(
            "Speech",
            footer: "Speech speed and voice volume control the PlayStation screen reader. "
                + "They do not change game audio or a game’s own narration settings."
        ) {
            MobileSliderRow(
                title: "Speech Speed",
                valueText: Self.speedName(store.draft.screenReaderSpeed),
                value: level(\.screenReaderSpeed),
                range: Self.sliderRange(PlayStationAccessibilitySettings.speedRange),
                step: 1
            )
            .accessibilityValue(Self.speedName(store.draft.screenReaderSpeed))
            MobileSliderRow(
                title: "Voice Volume",
                valueText: "\(store.draft.screenReaderVolume)",
                value: level(\.screenReaderVolume),
                range: Self.sliderRange(PlayStationAccessibilitySettings.volumeRange),
                step: 1
            )
            .accessibilityValue("\(store.draft.screenReaderVolume)")
        }
    }

    private var displayGroup: some View {
        MobileSettingsGroup(
            "Display",
            footer: "These settings apply to PlayStation cloud system menus. "
                + "Each game decides which settings it also uses."
        ) {
            MobilePickerRow(
                "Text Size",
                selection: textSize,
                choices: Array(PlayStationAccessibilitySettings.textSizeRange)
            ) { size in
                Self.textSizeName(size)
            }
            MobileToggleRow("Bold Text", isOn: choice(\.boldTextOverride, default: \.boldText))
            MobileToggleRow(
                "Higher Contrast",
                isOn: choice(\.higherContrastOverride, default: \.higherContrast)
            )
        }
    }

    private var deviceGroup: some View {
        MobileSettingsGroup(
            footer: "Available device accessibility preferences are used until changed here. "
                + "Screen reader speech speed and voice volume use PlayStation defaults.\n\n"
                + "Requests these settings for the PlayStation cloud console at the next stream launch."
        ) {
            MobileButtonRow("Use Device Accessibility Settings") {
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
