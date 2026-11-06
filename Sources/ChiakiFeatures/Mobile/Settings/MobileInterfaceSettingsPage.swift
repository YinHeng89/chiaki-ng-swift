import ChiakiModels
import ComposableArchitecture
import SwiftUI

/// The Interface page in the touch library: where the library menu sits.
struct MobileInterfaceSettingsPage: View {
    @Bindable private var store: StoreOf<PersistedSettingFeature<InterfaceSettings>>

    /// Creates the page.
    ///
    /// - Parameter settings: The settings, scoped to the persisted interface settings.
    init(settings: StoreOf<SettingsFeature>) {
        store = settings.scope(state: \.interface, action: \.interface)
    }

    var body: some View {
        MobileSettingsForm {
            MobileSettingsGroup("Menu") {
                MobilePickerRow(
                    "Menu Position",
                    selection: $store.draft.railEdge,
                    choices: LibraryRailEdge.allCases
                ) { edge in
                    InterfaceSettingsView.title(edge)
                }
            }
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: "interface settings") {
                store.send(.retry)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }
}
