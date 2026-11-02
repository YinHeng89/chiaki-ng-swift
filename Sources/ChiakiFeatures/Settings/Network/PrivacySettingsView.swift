import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// Streamer mode, which hides addresses and hardware ids on screen.
public struct PrivacySettingsView: View {
    /// The persisted log settings that hold the streamer mode flag.
    @Bindable public var store: StoreOf<PersistedSettingFeature<LogSettings>>

    /// Creates a privacy settings view.
    ///
    /// - Parameter store: The persisted log settings that hold the streamer mode flag.
    public init(store: StoreOf<PersistedSettingFeature<LogSettings>>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy").font(.headline)
            Toggle("Streamer mode", isOn: $store.draft.streamerMode)
                .accessibilityIdentifier("network-streamer-mode")
                .disabled(!store.isEditable)
            Text("Hides console addresses and hardware IDs on screen while you stream or record this device. "
                + "The log follows the Developer tab’s identifier setting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            store.send(.appeared)
        }
    }
}
