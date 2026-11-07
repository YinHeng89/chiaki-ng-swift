import ChiakiModels
import SwiftUI
import ComposableArchitecture
import MenuFocus

/// The light bar choices offered in the settings, including deferring to the setting for all controllers.
enum LightbarMode: Hashable, CaseIterable {
    /// Uses the light bar setting shared by all controllers.
    case allControllers
    /// Shows the colour the game asks for.
    case followGame
    /// Keeps one chosen colour for the whole stream.
    case fixed

    /// The label shown for the choice in the light bar segments.
    var title: LocalizedStringResource {
        switch self {
        case .allControllers:
            .settingsControlsLightbarAllControllers
        case .followGame:
            .settingsControlsLightbarFollowGame
        case .fixed:
            .settingsControlsLightbarFixed
        }
    }

    /// Derives the choice from a stored light bar setting.
    ///
    /// - Parameter value: The setting, or `nil` when the controller defers to all controllers.
    init(_ value: ControllerLightbar?) {
        switch value {
        case nil:
            self = .allControllers
        case .followGame:
            self = .followGame
        case .fixed:
            self = .fixed
        }
    }
}

/// Picks how a light bar is coloured, with a row of colour swatches when a fixed colour is chosen and a
/// caption explaining the result.
struct LightbarChooser: View {
    /// The current setting, or `nil` when deferring to the setting for all controllers.
    let value: ControllerLightbar?
    /// The setting for all controllers; when `nil` this chooser is that setting, so the option to defer is
    /// hidden.
    let inherited: ControllerLightbar?
    /// Called with the new setting, `nil` meaning defer to all controllers.
    let update: (ControllerLightbar?) -> Void
    /// Whether the controller has a light bar to set.
    var enabled = true
    @Environment(\.screenLayout) private var layout
    @State private var lastFixed: UInt32?

    private var modes: [LightbarMode] {
        inherited == nil
            ? [.followGame, .fixed]
            : LightbarMode.allCases
    }

    private var mode: Binding<LightbarMode> {
        Binding(
            get: {
                LightbarMode(value)
            },
            set: { next in
                switch next {
                case .allControllers:
                    update(nil)
                case .followGame:
                    update(.followGame)
                case .fixed:
                    update(.fixed(rgb: lastFixed ?? fixedColor ?? ControllerLightbarSwatch.all[0].rgb))
                }
            }
        )
    }

    private var fixedColor: UInt32? {
        if case .fixed(let rgb) = value {
            return rgb
        }
        if case .fixed(let rgb) = inherited {
            return rgb
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FocusableSegments(options: modes, title: \.title, selection: mode)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(.settingsControlsLightBar)
            if case .fixed(let selected) = value {
                swatches(selected: selected)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!enabled)
        .onChange(of: value, initial: true) { _, current in
            if case .fixed(let rgb) = current {
                lastFixed = rgb
            }
        }
    }

    private var detail: LocalizedStringResource {
        switch value {
        case nil:
            inherited == .followGame
                ? .settingsControlsLightbarInheritedFollow
                : .settingsControlsLightbarInheritedFixed
        case .followGame:
            .settingsControlsLightbarFollowDetail
        case .fixed:
            .settingsControlsLightbarFixedDetail
        }
    }

    private func swatches(selected: UInt32) -> some View {
        HStack(spacing: 10) {
            ForEach(ControllerLightbarSwatch.all) { swatch in
                FocusButton {
                    update(.fixed(rgb: swatch.rgb))
                } label: {
                    LightbarSwatchLabel(
                        swatch: swatch,
                        selected: swatch.rgb == selected,
                        showsName: !layout.hoverAffordances,
                        side: max(28, layout.controlSize)
                    )
                }
                .buttonStyle(.plain)
                .focusHighlightShape(.circle)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(swatch.rgb == selected
                    ? .isSelected
                    : [])
            }
        }
    }
}

private struct LightbarSwatchLabel: View {
    let swatch: ControllerLightbarSwatch
    let selected: Bool
    let showsName: Bool
    let side: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            circle
            if showsName {
                Text(swatch.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: side, minHeight: side)
        .contentShape(Rectangle())
    }

    private var circle: some View {
        ZStack {
            Circle()
                .fill(swatch.rgb == 0
                    ? Color.secondary.opacity(0.15)
                    : CouchLight.color(swatch.rgb) ?? .clear)
            Circle()
                .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
            if swatch.rgb == 0 {
                Image(systemName: "slash.circle")
                    .foregroundStyle(.secondary)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(swatch.rgb == 0xffffff || swatch.rgb == 0
                        ? Color.primary
                        : Color.white)
            }
        }
        .frame(width: 28, height: 28)
    }
}

/// A card that sets the light bar for every controller without its own setting, disabled when the controls
/// draft is not editable.
struct LightbarCard: View {
    /// The controls settings feature whose draft light bar the card edits.
    let store: StoreOf<ControlsSettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(.settingsControlsLightBar).font(.headline)
            Text(.settingsControlsLightbarCardFooter)
                .font(.callout)
                .foregroundStyle(.secondary)
            LightbarChooser(value: store.draft.lightbar, inherited: nil) { value in
                var draft = store.draft
                draft.lightbar = value ?? .followGame
                store.send(.edit(draft))
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .disabled(!store.isEditable)
    }
}
