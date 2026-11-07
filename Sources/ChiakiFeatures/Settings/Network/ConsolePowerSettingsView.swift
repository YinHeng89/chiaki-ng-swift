import ChiakiModels
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// What happens to a console when a stream ends, this device sleeps or the connection drops.
public struct ConsolePowerSettingsView: View {
    /// The persisted console power settings being edited.
    @Bindable public var store: StoreOf<PersistedSettingFeature<ConsolePowerSettings>>

    /// Creates a console power settings view.
    ///
    /// - Parameter store: The persisted console power settings being edited.
    public init(store: StoreOf<PersistedSettingFeature<ConsolePowerSettings>>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.settingsNetworkConsolePowerHeading).font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Text(.settingsNetworkLeaveConsoleStream)
                FocusableSegments(
                    options: ConsoleLeaveAction.allCases,
                    title: Self.title,
                    selection: $store.draft.leaveAction
                )
                .accessibilityLabel(.settingsNetworkLeaveConsoleStream)
                Text(Self.detail(store.draft.leaveAction))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(.settingsNetworkRestOnSleep, isOn: $store.draft.restOnMacSleep)
                    .padding(.top, 6)
                Toggle(.settingsNetworkResumeAfterWake, isOn: $store.draft.resumeAfterWake)
                Text(.settingsNetworkResumeAfterWakeDetail)
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(.settingsNetworkReconnectAfterDrop, isOn: $store.draft.reconnectAfterDrop)
                    .padding(.top, 6)
                Text(.settingsNetworkReconnectAfterDropDetail)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: .settingsNetworkConsolePowerSubject) {
                store.send(.retry)
            }
        }
        .onAppear {
            store.send(.appeared)
        }
    }

    /// The name of a leave action.
    ///
    /// - Parameter action: The action.
    /// - Returns: Its short name.
    public static func title(_ action: ConsoleLeaveAction) -> LocalizedStringResource {
        switch action {
        case .ask:
            .settingsNetworkLeaveAsk
        case .restMode:
            .settingsNetworkLeaveRestMode
        case .leaveOn:
            .settingsNetworkLeaveOn
        }
    }

    /// What a leave action does.
    ///
    /// - Parameter action: The action.
    /// - Returns: One sentence describing it.
    public static func detail(_ action: ConsoleLeaveAction) -> LocalizedStringResource {
        switch action {
        case .ask:
            .settingsNetworkLeaveAskDetail
        case .restMode:
            .settingsNetworkLeaveRestModeDetail
        case .leaveOn:
            .settingsNetworkLeaveOnDetail
        }
    }
}
