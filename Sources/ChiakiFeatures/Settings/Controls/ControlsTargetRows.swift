import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The Controls pane's two rows of cards: the keyboard and every remembered controller, connected ones
/// first, and players 1 to 4. Choosing a card shows its bindings.
struct ControlsTargetRows: View {
    /// The controls settings feature the rows read and choose from.
    let store: StoreOf<ControlsSettingsFeature>

    /// Draws both rows.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row(.settingsControlsDevices) {
                ForEach(devices, id: \.preferenceKey) { device in
                    card(for: device)
                }
            }
            row(.settingsControlsPlayers) {
                ForEach(0..<ControlsConfiguration.playerCount, id: \.self) { player in
                    ControlsTargetCard(
                        picture: .player(player),
                        title: String(localized: .settingsControlsPlayerTitle(number: player + 1)),
                        lines: playerLines(player),
                        selected: store.editing == .player(player)
                    ) {
                        store.send(.show(.player(player)))
                    }
                }
            }
        }
    }

    private var devices: [ControllerDevice] {
        #if os(macOS)
            store.listedDevices
        #else
            store.listedDevices.filter {
                !$0.isKeyboard
            }
        #endif
    }

    private func row(_ title: LocalizedStringResource, @ViewBuilder cards: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                cards()
            }
        }
    }

    private func card(for device: ControllerDevice) -> some View {
        let target = device.isKeyboard
            ? ControlsEditTarget.keyboard
            : .controller(device.preferenceKey)
        let connected = device.isKeyboard || store.state.isConnected(device.preferenceKey)
        return ControlsTargetCard(
            picture: device.isKeyboard
                ? .keyboard
                : .controller(ControllerArtwork.of(device)),
            title: title(for: device),
            lines: lines(for: device, connected: connected),
            connected: connected && !device.isKeyboard,
            selected: store.editing == target
        ) {
            store.send(.show(target))
        }
    }

    private func title(for device: ControllerDevice) -> String {
        guard !device.isKeyboard else {
            return String(localized: .settingsControlsKeyboardAndMouse)
        }
        return String(localized: store.state.title(of: device))
    }

    private func lines(for device: ControllerDevice, connected: Bool) -> [String] {
        guard !device.isKeyboard else {
            return [String(localized: .settingsControlsPlaysAsPlayerOne)]
        }
        var lines: [String]
        if connected {
            lines = [String(localized: .settingsControlsConnected), device.transport]
        } else if let seen = store.draft.remembered[device.preferenceKey]?.lastSeen {
            lines = [
                String(localized: .settingsControlsNotConnected),
                String(localized: .settingsControlsLastSeen(
                    time: seen.formatted(.relative(presentation: .named))
                ))
            ]
        } else {
            lines = [String(localized: .settingsControlsNotConnected)]
        }
        if !device.individual {
            lines.append(String(localized: .settingsControlsSharedByEvery(name: device.name)))
        }
        return lines
    }

    private func playerLines(_ player: Int) -> [String] {
        let bindings = String(localized: store.draft.playerPreset(player) == nil
            ? .settingsControlsUsesControllerBindings
            : .settingsControlsHasOwnBindings)
        return [bindings, playerController(player)]
    }

    private func playerController(_ player: Int) -> String {
        guard let key = store.state.shownControllerKey(forPlayer: player) else {
            return String(localized: .settingsControlsFirstAvailableController)
        }
        if key == ControlsConfiguration.keyboardOnlyKey {
            return String(localized: ControlsPlayerControllerPicker.withoutControllerTitle)
        }
        return store.state.device(key).map { String(localized: store.state.title(of: $0)) }
            ?? String(localized: .settingsControlsFirstAvailableController)
    }
}

/// A card in the Controls pane's device and player rows: what it is, its status on separate lines, and
/// whether its bindings are the ones shown.
private struct ControlsTargetCard: View {
    /// What the card shows a picture of.
    enum Picture: Equatable {
        /// A keyboard symbol.
        case keyboard

        /// A controller drawing.
        case controller(ControllerArtwork)

        /// A player's number.
        case player(Int)
    }

    /// The picture.
    let picture: Picture

    /// The name.
    let title: String

    /// The status lines, the first one emphasised.
    let lines: [String]

    /// Whether the first status line reads as connected.
    var connected = false

    /// Whether the card's bindings are shown.
    let selected: Bool

    /// Shows the card's bindings.
    let choose: () -> Void

    /// Draws the card.
    var body: some View {
        FocusButton(action: choose) {
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 58, height: 40)
                    .opacity(dimmed
                        ? 0.45
                        : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(2)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        statusLine(line, first: index == 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(selected
                ? Palette.accent.opacity(0.12)
                : Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(selected
                        ? Palette.accent.opacity(0.8)
                        : Color.primary.opacity(0.08))
                }
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected
            ? .isSelected
            : [])
    }

    private var dimmed: Bool {
        if case .controller = picture {
            return !connected
        }
        return false
    }

    @ViewBuilder private var thumbnail: some View {
        switch picture {
        case .keyboard:
            Image(systemName: "keyboard").font(.title2).foregroundStyle(.secondary)
        case .controller(let artwork):
            if let image = artwork.image {
                Image(platformImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "gamecontroller").font(.title2).foregroundStyle(.secondary)
            }
        case .player(let index):
            Text(.settingsControlsPlayerBadge(number: index + 1))
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func statusLine(_ line: String, first: Bool) -> some View {
        if first && connected {
            Label(line, systemImage: "circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.green)
                .imageScale(.small)
        } else {
            Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}
