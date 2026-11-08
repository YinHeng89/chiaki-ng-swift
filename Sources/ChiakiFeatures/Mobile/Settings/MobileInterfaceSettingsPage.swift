import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// The Interface page in the touch library: where the library menu sits and which language the app shows.
struct MobileInterfaceSettingsPage: View {
    @Bindable private var store: StoreOf<PersistedSettingFeature<InterfaceSettings>>
    @State private var language = AppLanguageSetting()

    /// Creates the page.
    ///
    /// - Parameter settings: The settings, scoped to the persisted interface settings.
    init(settings: StoreOf<SettingsFeature>) {
        store = settings.scope(state: \.interface, action: \.interface)
    }

    var body: some View {
        MobileSettingsForm {
            MobileSettingsGroup(.mobileInterfaceMenu) {
                MobilePickerRow(
                    .mobileInterfaceMenuPosition,
                    selection: $store.draft.railEdge,
                    choices: LibraryRailEdge.allCases
                ) { edge in
                    InterfaceSettingsView.title(edge)
                }
            }
            .disabled(!store.isEditable)
            MobileSettingsGroup(
                .settingsInterfaceLanguage,
                footer: language.needsRelaunch
                    ? .settingsInterfaceLanguageRelaunch
                    : nil
            ) {
                MobilePickerRow(
                    .settingsInterfaceLanguage,
                    selection: Binding {
                        language.choice
                    } set: { choice in
                        language.choose(choice)
                    },
                    choices: language.choices
                ) { choice in
                    AppLanguageSetting.title(choice)
                }
            }
            SettingsPersistenceBanner(store.setting, subject: .mobileInterfacePersistenceSubject) {
                store.send(.retry)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }
}
