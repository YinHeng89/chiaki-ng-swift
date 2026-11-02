import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// Where the library menu sits.
public struct InterfaceSettingsView: View {
    /// The persisted interface settings whose library menu edge is edited and saved.
    @Bindable public var store: StoreOf<PersistedSettingFeature<InterfaceSettings>>

    /// Creates an interface settings view.
    ///
    /// - Parameter store: The persisted interface settings whose library menu edge is edited and saved.
    public init(store: StoreOf<PersistedSettingFeature<InterfaceSettings>>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu position").font(.headline)
            FocusableSegments(
                options: LibraryRailEdge.allCases,
                title: Self.title,
                selection: $store.draft.railEdge
            )
            .accessibilityLabel("Menu position")
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: "interface settings") {
                store.send(.retry)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    /// The name of a menu edge.
    ///
    /// - Parameter edge: The edge.
    /// - Returns: Its name.
    public static func title(_ edge: LibraryRailEdge) -> String {
        switch edge {
        case .top:
            "Top"
        case .left:
            "Left"
        case .right:
            "Right"
        case .bottom:
            "Bottom"
        }
    }
}
