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
            Text("Console power").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Text("When leaving a console stream")
                FocusableSegments(
                    options: ConsoleLeaveAction.allCases,
                    title: Self.title,
                    selection: $store.draft.leaveAction
                )
                .accessibilityLabel("When leaving a console stream")
                Text(Self.detail(store.draft.leaveAction))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(
                    "Put the console in rest mode when this device sleeps",
                    isOn: $store.draft.restOnMacSleep
                )
                .padding(.top, 6)
                Toggle("Reconnect after this device wakes", isOn: $store.draft.resumeAfterWake)
                Text("A console stream interrupted by sleep starts again on the same connection.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Reconnect when the connection drops", isOn: $store.draft.reconnectAfterDrop)
                    .padding(.top, 6)
                Text(
                    "A console stream that loses its connection connects again, up to three times, instead of ending."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.isEditable)
            SettingsPersistenceBanner(store.setting, subject: "console power settings") {
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
    public static func title(_ action: ConsoleLeaveAction) -> String {
        switch action {
        case .ask:
            "Ask"
        case .restMode:
            "Rest mode"
        case .leaveOn:
            "Leave it on"
        }
    }

    /// What a leave action does.
    ///
    /// - Parameter action: The action.
    /// - Returns: One sentence describing it.
    public static func detail(_ action: ConsoleLeaveAction) -> String {
        switch action {
        case .ask:
            "Leaving a stream offers Disconnect or Rest mode."
        case .restMode:
            "Leaving a stream puts the console in rest mode."
        case .leaveOn:
            "Leaving a stream keeps the console on."
        }
    }
}
