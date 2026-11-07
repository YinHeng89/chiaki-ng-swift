import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The Controls tab's keyboard and mouse half: the keyboard mode and key bindings, or the mouse button
/// bindings.
struct ControlsKeyboardMouseSection: View {
    /// The controls settings feature the section reads and edits.
    @Bindable var store: StoreOf<ControlsSettingsFeature>

    /// The preset whose bindings are shown.
    let preset: InputPreset

    /// Which tab is shown: 0 for the keyboard, 1 for the mouse.
    @Binding var tab: Int

    /// The keyboard or the mouse bindings.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    deviceChoice
                    Spacer(minLength: 0)
                    modeChoice
                }
                VStack(alignment: .leading, spacing: 12) {
                    deviceChoice
                    modeChoice
                }
            }
            FlowTransition(selection: tab) {
                if tab == 0 {
                    keyboard
                } else {
                    mouse
                }
            }
        }
        .disabled(!store.isEditable)
        .onChange(of: tab) { _, _ in
            store.send(.cancelCapture)
        }
    }

    private var deviceChoice: some View {
        FocusableSegments(options: [0, 1], title: {
            $0 == 0
                ? .settingsControlsDeviceKeyboard
                : .settingsControlsDeviceMouse
        }, selection: $tab)
    }

    @ViewBuilder private var modeChoice: some View {
        if tab == 0 {
            FocusableSegments(
                options: KeyboardMode.allCases,
                title: Self.modeTitle,
                selection: $store.draft.keyboardMode
            )
        }
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(modeNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            KeyboardBindingsView(store: store)
        }
    }

    private var mouse: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(.settingsControlsEnableMouse, isOn: $store.draft.mouseEnabled)
            ForEach(PlayStationControl.allCases, id: \.self) { target in
                BindingRow(target: target, bindings: preset.bindings, listening: false,
                           capture: {}, change: { source, code, _ in
                               let label = BindingRow.pickedLabel(source: source, code: code)
                               let binding = InputBinding(
                                   source: source,
                                   code: code,
                                   label: label,
                                   target: target
                               )
                               store.send(.assignBinding(preset.id, binding))
                           }, source: .mouseButton)
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: GlassPanel.Radius.medium.shape)
    }

    private var modeNote: LocalizedStringResource {
        switch store.draft.keyboardMode {
        case .typeOnConsole:
            .settingsControlsModeTypeNote
        case .controller:
            .settingsControlsModeControllerNote
        }
    }

    private static func modeTitle(_ mode: KeyboardMode) -> LocalizedStringResource {
        switch mode {
        case .typeOnConsole:
            .settingsControlsModeTypeOnConsole
        case .controller:
            .settingsControlsModeController
        }
    }
}

/// The keyboard drawn key by key under the keyboard's binding board.
///
/// While a control listens, choosing a keycap binds that key, which is how a controller picks a key. With
/// nothing listening, choosing a bound keycap starts listening for its control, and choosing an unbound one
/// explains what to do instead.
private struct KeyboardBindingsView: View {
    /// The controls settings feature the keyboard reads and edits.
    let store: StoreOf<ControlsSettingsFeature>

    @State private var note: LocalizedStringResource?
    @MenuFocusState private var focus: KeyBindingFocus?

    /// Draws the keyboard.
    var body: some View {
        KeyboardLayoutView(
            bindings: store.draft.keyboardPreset.bindings,
            selected: store.capture?.target,
            note: note,
            focus: $focus
        ) { code, label in
            choose(code, label: label)
        }
    }

    private func choose(_ code: Int, label: String) {
        note = nil
        if let capture = store.capture {
            guard capture.source == .macKey else {
                return
            }
            store.send(.captured(capture.id, code, label))
        } else if let binding = store.draft.keyboardPreset.bindings.first(where: {
            $0.source == .macKey && $0.code == code
        }) {
            store.send(.capture(binding.target))
        } else {
            let key = String(localized: KeyCodeLabels.title(forKey: code, label: label))
            note = .settingsControlsKeyNotBound(key: key)
        }
    }
}

/// The keycap of the keyboard layout that controller focus is on.
public enum KeyBindingFocus: Hashable {
    /// The keycap with the given virtual key code.
    case key(Int)
}

/// An ANSI keyboard drawn as focusable keycaps that highlights assigned keys and the key bound to the
/// selected action; choosing a keycap reports its code and label, and arrow keys move focus geometrically
/// between keycaps.
public struct KeyboardLayoutView: View {
    /// The menu navigator used to move focus between keycaps with the arrow keys.
    @Environment(\.menuNavigator) var navigator
    @Environment(\.inputMode) private var inputMode
    /// The bindings whose keyboard keys are shaded as assigned.
    public let bindings: [InputBinding]
    /// The action being captured, whose key is outlined; when it changes to a value, focus moves to its key
    /// or the first free key.
    public let selected: PlayStationControl?
    /// A hint shown under the keyboard, such as a key that has no action yet.
    public var note: LocalizedStringResource?
    /// The editor's shared controller focus, which the keycaps join.
    public let focus: MenuFocusState<KeyBindingFocus?>.Binding
    /// Called with the virtual key code and display label of the chosen keycap.
    public let choose: (Int, String) -> Void
    @State private var hostWindow: PlatformWindow?

    /// Creates a keyboard layout view.
    ///
    /// - Parameters:
    ///   - bindings: The bindings whose keyboard keys are shaded as assigned.
    ///   - selected: The action being captured, whose key is outlined; when it changes to a value, focus moves to its
    ///     key or the first free key.
    ///   - note: A hint shown under the keyboard, such as a key that has no action yet.
    ///   - focus: The editor's shared controller focus, which the keycaps join.
    ///   - choose: Called with the virtual key code and display label of the chosen keycap.
    public init(
        bindings: [InputBinding],
        selected: PlayStationControl?,
        note: LocalizedStringResource? = nil,
        focus: MenuFocusState<KeyBindingFocus?>.Binding,
        choose: @escaping (Int, String) -> Void
    ) {
        self.bindings = bindings
        self.selected = selected
        self.note = note
        self.focus = focus
        self.choose = choose
    }

    private struct Key: Identifiable {
        let id: Int
        let label: String
        var width: CGFloat = 1
    }
    private static let rows: [[Key]] = [
        [.init(id: 53, label: "esc"), .init(id: 122, label: "F1"), .init(id: 120, label: "F2"),
         .init(id: 99, label: "F3"), .init(id: 118, label: "F4"), .init(id: 96, label: "F5"),
         .init(id: 97, label: "F6"), .init(id: 98, label: "F7"), .init(id: 100, label: "F8"),
         .init(id: 101, label: "F9"), .init(id: 109, label: "F10"), .init(id: 103, label: "F11"),
         .init(id: 111, label: "F12")],
        [.init(id: 50, label: "`"), .init(id: 18, label: "1"), .init(id: 19, label: "2"),
         .init(id: 20, label: "3"), .init(id: 21, label: "4"), .init(id: 23, label: "5"),
         .init(id: 22, label: "6"), .init(id: 26, label: "7"), .init(id: 28, label: "8"),
         .init(id: 25, label: "9"), .init(id: 29, label: "0"), .init(id: 27, label: "−"),
         .init(id: 24, label: "="), .init(id: 51, label: "delete", width: 1.5)],
        [.init(id: 48, label: "tab", width: 1.5), .init(id: 12, label: "Q"), .init(id: 13, label: "W"),
         .init(id: 14, label: "E"), .init(id: 15, label: "R"), .init(id: 17, label: "T"),
         .init(id: 16, label: "Y"), .init(id: 32, label: "U"), .init(id: 34, label: "I"),
         .init(id: 31, label: "O"), .init(id: 35, label: "P"), .init(id: 33, label: "["),
         .init(id: 30, label: "]"), .init(id: 42, label: "\\")],
        [.init(id: 57, label: "caps", width: 1.8), .init(id: 0, label: "A"), .init(id: 1, label: "S"),
         .init(id: 2, label: "D"), .init(id: 3, label: "F"), .init(id: 5, label: "G"),
         .init(id: 4, label: "H"), .init(id: 38, label: "J"), .init(id: 40, label: "K"),
         .init(id: 37, label: "L"), .init(id: 41, label: ";"), .init(id: 39, label: "'"),
         .init(id: 36, label: "return", width: 1.7)],
        [.init(id: 56, label: "shift", width: 2.2), .init(id: 6, label: "Z"), .init(id: 7, label: "X"),
         .init(id: 8, label: "C"), .init(id: 9, label: "V"), .init(id: 11, label: "B"),
         .init(id: 45, label: "N"), .init(id: 46, label: "M"), .init(id: 43, label: ","),
         .init(id: 47, label: "."), .init(id: 44, label: "/"), .init(id: 60, label: "shift", width: 2.3)],
        [.init(id: 59, label: "ctrl", width: 1.2), .init(id: 58, label: "opt", width: 1.2),
         .init(id: 55, label: "cmd", width: 1.4), .init(id: 49, label: "space", width: 4.5),
         .init(id: 54, label: "cmd", width: 1.4), .init(id: 61, label: "opt", width: 1.2),
         .init(id: 123, label: "←"), .init(id: 126, label: "↑"), .init(id: 125, label: "↓"),
         .init(id: 124, label: "→")]
    ]
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(.settingsControlsKeyboardLayout).font(.headline)
                Spacer()
                Text(.settingsControlsAnsiReference).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                VStack(spacing: 5) {
                    ForEach(Self.rows.indices, id: \.self) { index in
                        let row = Self.rows[index]
                        let unit = max(1, (geometry.size.width - CGFloat(row.count - 1) * 5)
                            / row.reduce(0) { $0 + $1.width })
                        HStack(spacing: 5) {
                            ForEach(row) { key in
                                keycap(key).frame(width: unit * key.width, height: 34)
                            }
                        }
                    }
                }
            }.frame(height: 229)
            if let note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
        .background(WindowAccessor { hostWindow = $0 })
        .onChange(of: selected) { _, selected in
            if selected != nil {
                focusInitialKey()
            }
        }
    }
    private func keycap(_ key: Key) -> some View {
        let binding = bindings.first { $0.source == .macKey && $0.code == key.id }
        let highlighted = binding?.target == selected && selected != nil
        let modifier = [54, 55, 56, 57, 58, 59, 60, 61].contains(key.id)
        return FocusButton {
            choose(key.id, KeyCodeLabels.label(for: key.id, characters: key.label))
        } label: {
            keycapLabel(key, assigned: binding != nil, highlighted: highlighted)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .drawsOwnFocusHighlight()
        .menuFocused(focus, equals: .key(key.id))
        .onMenuKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
            guard let direction = moveDirection(press.key), let hostWindow else {
                return .ignored
            }
            _ = navigator?.moveGeometric(direction, in: hostWindow, allowUnaligned: true)
            return .handled
        }
        .disabled(modifier)
        .accessibilityLabel(.settingsControlsKeySpoken(
            key: key.label,
            control: String(localized: binding?.target.label ?? .settingsControlsKeyUnassignedSpoken)
        ))
        .help(modifier
            ? .settingsControlsModifierReserved
            : binding?.target.label ?? .settingsControlsUnassigned)
    }

    private func keycapLabel(_ key: Key, assigned: Bool, highlighted: Bool) -> some View {
        let focused = inputMode.shows(focus.wrappedValue == .key(key.id))
        let lime = Palette.accent
        let fill = assigned
            ? lime.opacity(0.18)
            : Color.primary.opacity(0.05)
        let stroke = highlighted
            ? lime
            : focused
                ? Palette.accent
                : Color.primary.opacity(0.14)
        let strokeWidth: CGFloat = highlighted || focused
            ? 2
            : 1
        return Text(key.label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(stroke, lineWidth: strokeWidth)
            }
            .background {
                if focused {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.accent.opacity(0.2))
                }
            }
    }

    private func moveDirection(_ key: KeyEquivalent) -> MenuMoveDirection? {
        switch key {
        case .upArrow:
            .up
        case .downArrow:
            .down
        case .leftArrow:
            .left
        case .rightArrow:
            .right
        default:
            nil
        }
    }

    private func focusInitialKey() {
        let keys = Self.rows.flatMap { $0 }.filter { key in
            ![54, 55, 56, 57, 58, 59, 60, 61].contains(key.id)
        }
        if let selected,
           let selectedKey = bindings.first(where: {
               $0.source == .macKey && $0.target == selected
           })?.code,
           keys.contains(where: { $0.id == selectedKey }) {
            focus.wrappedValue = .key(selectedKey)
        } else if let firstAvailableKey = keys.first(where: { key in
            !bindings.contains { $0.source == .macKey && $0.code == key.id }
        }) {
            focus.wrappedValue = .key(firstAvailableKey.id)
        } else {
            focus.wrappedValue = keys.first.map { .key($0.id) }
        }
    }
}
