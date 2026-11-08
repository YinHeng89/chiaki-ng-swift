import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// Where the library menu sits and which language the app shows.
public struct InterfaceSettingsView: View {
    /// The persisted interface settings whose library menu edge is edited and saved.
    @Bindable public var store: StoreOf<PersistedSettingFeature<InterfaceSettings>>
    @State private var language = AppLanguageSetting()

    /// Creates an interface settings view.
    ///
    /// - Parameter store: The persisted interface settings whose library menu edge is edited and saved.
    public init(store: StoreOf<PersistedSettingFeature<InterfaceSettings>>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.settingsInterfaceMenuPosition).font(.headline)
            FocusableSegments(
                options: LibraryRailEdge.allCases,
                title: Self.title,
                selection: $store.draft.railEdge
            )
            .accessibilityLabel(.settingsInterfaceMenuPosition)
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: .settingsInterfacePersistenceSubject) {
                store.send(.retry)
            }
            Text(.settingsInterfaceLanguage)
                .font(.headline)
                .padding(.top, 8)
            Picker(selection: languageChoice) {
                ForEach(language.choices, id: \.self) { choice in
                    Text(AppLanguageSetting.title(choice)).tag(choice)
                }
            } label: {
                Text(.settingsInterfaceLanguage)
            }
            .labelsHidden()
            .fixedSize()
            .nativeFocusHighlight()
            if language.needsRelaunch {
                Text(.settingsInterfaceLanguageRelaunch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    private var languageChoice: Binding<AppLanguageSetting.Choice> {
        Binding {
            language.choice
        } set: { choice in
            language.choose(choice)
        }
    }

    /// The name of a menu edge.
    ///
    /// - Parameter edge: The edge.
    /// - Returns: Its name.
    public static func title(_ edge: LibraryRailEdge) -> LocalizedStringResource {
        switch edge {
        case .top:
            .settingsInterfaceEdgeTop
        case .left:
            .settingsInterfaceEdgeLeft
        case .right:
            .settingsInterfaceEdgeRight
        case .bottom:
            .settingsInterfaceEdgeBottom
        }
    }
}
