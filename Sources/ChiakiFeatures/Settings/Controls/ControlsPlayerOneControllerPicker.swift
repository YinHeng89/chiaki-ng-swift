import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The controller player 1 plays with, shown in Player 1's panel: the first available one, none, or a
/// particular one the pane lists.
struct ControlsPlayerOneControllerPicker: View {
    /// The controls settings feature the picker reads and edits.
    @Bindable var store: StoreOf<ControlsSettingsFeature>

    #if os(macOS)
        /// The choice that makes player 1 play with the keyboard alone.
        static let withoutControllerTitle: LocalizedStringResource = .settingsControlsKeyboardOnly
    #else
        /// The choice that makes player 1 play with the on-screen controller alone.
        static let withoutControllerTitle: LocalizedStringResource = .settingsControlsTouchControls
    #endif

    /// Draws the picker.
    var body: some View {
        HStack(spacing: 10) {
            Text(.settingsControlsPlaysWith).foregroundStyle(.secondary)
            Picker(.settingsControlsPlayerOnePicker, selection: $store.draft.selectedControllerKey) {
                Text(.settingsControlsFirstAvailableController).tag(String?.none)
                Text(Self.withoutControllerTitle).tag(Optional(ControlsConfiguration.keyboardOnlyKey))
                ForEach(store.listedDevices.filter { !$0.isKeyboard }, id: \.preferenceKey) { device in
                    Text(device.name).tag(Optional(device.preferenceKey))
                }
            }
            .labelsHidden()
            .nativeFocusHighlight()
            .frame(maxWidth: 280)
        }
        .font(.callout)
        .disabled(!store.isEditable)
    }
}
