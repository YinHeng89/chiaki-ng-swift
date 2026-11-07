import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The controller a player plays with, shown in the player's panel: the first available one, a connected one
/// no other player chose, or for player 1 none.
///
/// A saved controller that is not connected shows as the first available controller, which is what the player
/// plays with until it returns; the saved choice is kept.
struct ControlsPlayerControllerPicker: View {
    /// The controls settings feature the picker reads and edits.
    let store: StoreOf<ControlsSettingsFeature>

    /// The player, `0` for player 1.
    let player: Int

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
            Picker(.settingsControlsPlayerPicker(number: player + 1), selection: selection) {
                Text(.settingsControlsFirstAvailableController).tag(String?.none)
                if player == 0 {
                    Text(Self.withoutControllerTitle).tag(Optional(ControlsConfiguration.keyboardOnlyKey))
                }
                ForEach(store.state.controllerChoices(forPlayer: player), id: \.preferenceKey) { device in
                    Text(store.state.title(of: device)).tag(Optional(device.preferenceKey))
                }
            }
            .labelsHidden()
            .nativeFocusHighlight()
            .frame(maxWidth: 280)
        }
        .font(.callout)
        .disabled(!store.isEditable)
    }

    private var selection: Binding<String?> {
        Binding(
            get: {
                store.state.shownControllerKey(forPlayer: player)
            },
            set: { key in
                var draft = store.draft
                draft.setControllerKey(key, forPlayer: player)
                store.send(.edit(draft))
            }
        )
    }
}
