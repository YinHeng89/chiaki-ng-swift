import ChiakiModels
import SwiftUI
import DesignSystem
import MenuFocus

/// One row of a bindings list for a PlayStation control, showing a key capture button, a controller button
/// picker with Detect, or a mouse button picker depending on the input source.
struct BindingRow: View {
    /// The PlayStation control this row binds.
    let target: PlayStationControl
    /// All bindings in the profile, searched for the one that maps an input of this row's source to the
    /// target.
    let bindings: [InputBinding]
    /// Whether the row is waiting for a key or button press to capture.
    let listening: Bool
    /// Starts or cancels capturing an input for this row.
    let capture: () -> Void
    /// Called with the source, code and label of a new binding; a code of -1 clears it.
    let change: (InputSource, Int, String) -> Void
    /// Which input source the row edits; `nil` edits keyboard keys.
    var source: InputSource?
    /// The controller family used to name and draw gamepad buttons.
    var family = ControllerFamily.playStation
    /// Whether gamepad buttons are named by position or by printed label.
    var layout = ButtonLayout.position
    /// Whether a controller is connected, which enables the Detect button.
    var canDetect = true
    /// Generic names for SDL gamepad button indices, in index order.
    nonisolated static let buttons: [LocalizedStringResource] = [
        .settingsControlsButtonSouth, .settingsControlsButtonEast, .settingsControlsButtonWest,
        .settingsControlsButtonNorth, .settingsControlsButtonBack, .settingsControlsButtonGuide,
        .settingsControlsButtonStart, .settingsControlsButtonLeftStick, .settingsControlsButtonRightStick,
        .settingsControlsButtonLeftShoulder, .settingsControlsButtonRightShoulder,
        .settingsControlsButtonDpadUp, .settingsControlsButtonDpadDown, .settingsControlsButtonDpadLeft,
        .settingsControlsButtonDpadRight, .settingsControlsButtonMisc1,
        .settingsControlsButtonRightPaddle1, .settingsControlsButtonLeftPaddle1,
        .settingsControlsButtonRightPaddle2,
        .settingsControlsButtonLeftPaddle2, .settingsControlsButtonTouchpad, .settingsControlsButtonMisc2,
        .settingsControlsButtonMisc3, .settingsControlsButtonMisc4, .settingsControlsButtonMisc5,
        .settingsControlsButtonMisc6
    ]
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(target.label).font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            if source == .mouseButton {
                mouse
            } else if source == .gamepadButton {
                gamepad
            } else {
                keyboard
            }
        }
    }
    private var keyboard: some View {
        HStack(spacing: 4) {
            FocusButton(action: capture) {
                keyLabel
                    .frame(minWidth: 70)
            }.glassControlStyle()
                .accessibilityLabel(
                    .settingsControlsKeyboardBindingLabel(control: String(localized: target.label))
                )
            FocusButton {
                change(.macKey, -1, "")
            } label: {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            }.buttonStyle(.plain).focusHighlightShape(.circle).help(.settingsControlsClearKey)
                .accessibilityLabel(.settingsControlsClearKeyLabel(control: String(localized: target.label)))
        }
    }
    private var keyLabel: Text {
        if listening {
            return Text(.settingsControlsPressKey)
        }
        if let binding = binding(.macKey) {
            return Text(KeyCodeLabels.title(for: binding))
        }
        return Text(.settingsControlsAssignKey)
    }
    private var gamepad: some View {
        HStack(spacing: 8) {
            Picker(.settingsControlsControllerPicker, selection: selection(.gamepadButton)) {
                Text(.settingsControlsUnassigned).tag(-1)
                ForEach(buttonChoices, id: \.self) { code in
                    let glyph = ControllerGlyphs.button(code, family: family, layout: layout)
                    if let symbol = glyph.symbol {
                        Label(glyph.name, systemImage: symbol).tag(code)
                    } else {
                        Text(glyph.name).tag(code)
                    }
                }
            }.labelsHidden().nativeFocusHighlight().frame(maxWidth: 200)
                .accessibilityLabel(
                    .settingsControlsControllerBindingLabel(control: String(localized: target.label))
                )
            FocusButton(action: capture) {
                Text(listening
                    ? .settingsControlsPressButton
                    : .settingsControlsDetect)
                    .frame(minWidth: 70)
            }
            .glassControlStyle()
            .disabled(!canDetect && !listening)
            .help(canDetect
                ? .settingsControlsDetectHelp
                : .settingsControlsDetectUnavailableHelp)
                .accessibilityLabel(.settingsControlsDetectLabel(control: String(localized: target.label)))
        }
    }
    private var buttonChoices: [Int] {
        let common = Array(0...20)
        guard let code = binding(.gamepadButton)?.code, code > 20 else {
            return family == .generic
                ? Array(0..<ControllerGlyphs.buttonCount)
                : common
        }
        return common + [code]
    }
    /// Returns the generic name of an SDL gamepad button index.
    ///
    /// - Parameter code: The button index.
    /// - Returns: The name from `buttons`, or "Button N" for indices past the list.
    static func buttonName(_ code: Int) -> LocalizedStringResource {
        buttons.indices.contains(code)
            ? buttons[code]
            : .settingsControlsButtonNumbered(number: code)
    }

    /// Returns the label of a binding chosen from a row's picker.
    ///
    /// - Parameters:
    ///   - source: The input the binding reads.
    ///   - code: The button index.
    /// - Returns: The controller button's name, or the mouse button's number.
    static func pickedLabel(source: InputSource, code: Int) -> String {
        let name: LocalizedStringResource = source == .gamepadButton && buttons.indices.contains(code)
            ? buttons[code]
            : .settingsControlsMouseNumbered(number: code + 1)
        return name.english
    }
    private var mouse: some View {
        Picker(.settingsControlsMousePicker, selection: selection(.mouseButton)) {
            Text(.settingsControlsNoMouseButton).tag(-1)
            Text(.settingsControlsLeftClick).tag(0)
            Text(.settingsControlsRightClick).tag(1)
            Text(.settingsControlsMiddleClick).tag(2)
            ForEach(3...7, id: \.self) { Text(.settingsControlsMouseNumbered(number: $0 + 1)).tag($0) }
        }.labelsHidden().nativeFocusHighlight().frame(maxWidth: 160)
            .accessibilityLabel(.settingsControlsMouseBindingLabel(control: String(localized: target.label)))
    }
    private func binding(_ source: InputSource) -> InputBinding? {
        bindings.first { $0.target == target && $0.source == source }
    }
    private func selection(_ source: InputSource) -> Binding<Int> {
        Binding(get: { binding(source)?.code ?? -1 }, set: { change(source, $0, "") })
    }
}
