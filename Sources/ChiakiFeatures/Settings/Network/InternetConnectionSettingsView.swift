import ChiakiModels
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// How internet connections guess ports behind strict routers.
public struct InternetConnectionSettingsView: View {
    /// The persisted internet connection settings being edited.
    @Bindable public var store: StoreOf<PersistedSettingFeature<InternetConnectionSettings>>

    /// Creates an internet connection settings view.
    ///
    /// - Parameter store: The persisted internet connection settings being edited.
    public init(store: StoreOf<PersistedSettingFeature<InternetConnectionSettings>>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Internet connections").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Always guess ports", isOn: $store.draft.forcePortGuessing)
                    .accessibilityIdentifier("internet-force-port-guessing")
                Text(
                    "Connections through the PlayStation Network guess ports only when the router needs it. "
                        + "Turn this on if Internet connections fail behind a strict router."
                )
                .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Port guesses")
                        Spacer()
                        Text("\(store.draft.portGuessCount)")
                            .monospacedDigit()
                    }
                    Slider(
                        value: $store.draft.portGuessSliderValue,
                        in: Double(InternetConnectionSettings.portGuessRange.lowerBound)...Double(
                            InternetConnectionSettings.portGuessRange.upperBound
                        ),
                        step: Double(InternetConnectionSettings.portGuessStep)
                    )
                    .nativeFocusHighlight()
                    .focusHighlightShape(.capsule)
                    .accessibilityLabel("Port guesses")
                    .accessibilityValue("\(store.draft.portGuessCount) ports")
                    .settingsSliderController(value: $store.draft.portGuessSliderValue)
                    Text("More guesses can get through stricter routers but take longer to connect.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: "Internet connection settings") {
                store.send(.retry)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }
}

private extension InternetConnectionSettings {
    var portGuessSliderValue: Double {
        get {
            Double(portGuessCount)
        }
        set {
            let step = Double(Self.portGuessStep)
            let snapped = Int((newValue / step).rounded() * step)
            portGuessCount = min(max(snapped, Self.portGuessRange.lowerBound), Self.portGuessRange.upperBound)
        }
    }
}
