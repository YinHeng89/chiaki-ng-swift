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
    nonisolated static let buttons = [
        "South / Cross", "East / Circle", "West / Square", "North / Triangle", "Back / Create", "Guide / PS",
        "Start / Options", "Left stick", "Right stick", "Left shoulder", "Right shoulder", "D-pad up",
        "D-pad down", "D-pad left", "D-pad right", "Misc 1", "Right paddle 1", "Left paddle 1",
        "Right paddle 2", "Left paddle 2", "Touchpad", "Misc 2", "Misc 3", "Misc 4", "Misc 5", "Misc 6"
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
                Text(listening
                    ? "Press a key…"
                    : binding(.macKey)?.label ?? "Assign key")
                    .frame(minWidth: 70)
            }.glassControlStyle().accessibilityLabel("Keyboard binding for \(target.label)")
            FocusButton {
                change(.macKey, -1, "")
            } label: {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            }.buttonStyle(.plain).focusHighlightShape(.circle).help("Clear key")
                .accessibilityLabel("Clear \(target.label) key")
        }
    }
    private var gamepad: some View {
        HStack(spacing: 8) {
            Picker("Controller", selection: selection(.gamepadButton)) {
                Text("Unassigned").tag(-1)
                ForEach(buttonChoices, id: \.self) { code in
                    let glyph = ControllerGlyphs.button(code, family: family, layout: layout)
                    if let symbol = glyph.symbol {
                        Label(glyph.name, systemImage: symbol).tag(code)
                    } else {
                        Text(glyph.name).tag(code)
                    }
                }
            }.labelsHidden().nativeFocusHighlight().frame(maxWidth: 200)
                .accessibilityLabel("Controller binding for \(target.label)")
            FocusButton(action: capture) {
                Text(listening
                    ? "Press a button…"
                    : "Detect")
                    .frame(minWidth: 70)
            }
            .glassControlStyle()
            .disabled(!canDetect && !listening)
            .help(canDetect
                ? "Press a controller button to assign it, or hold any button to cancel"
                : "Connect a controller to detect its buttons")
                .accessibilityLabel("Detect controller button for \(target.label)")
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
    static func buttonName(_ code: Int) -> String {
        buttons.indices.contains(code)
            ? buttons[code]
            : "Button \(code)"
    }

    /// Returns the label of a binding chosen from a row's picker.
    ///
    /// - Parameters:
    ///   - source: The input the binding reads.
    ///   - code: The button index.
    /// - Returns: The controller button's name, or the mouse button's number.
    static func pickedLabel(source: InputSource, code: Int) -> String {
        source == .gamepadButton && buttons.indices.contains(code)
            ? buttons[code]
            : "Mouse \(code + 1)"
    }
    private var mouse: some View {
        Picker("Mouse", selection: selection(.mouseButton)) {
            Text("No mouse button").tag(-1)
            Text("Left click").tag(0)
            Text("Right click").tag(1)
            Text("Middle click").tag(2)
            ForEach(3...7, id: \.self) { Text("Mouse \($0 + 1)").tag($0) }
        }.labelsHidden().nativeFocusHighlight().frame(maxWidth: 160)
            .accessibilityLabel("Mouse binding for \(target.label)")
    }
    private func binding(_ source: InputSource) -> InputBinding? {
        bindings.first { $0.target == target && $0.source == source }
    }
    private func selection(_ source: InputSource) -> Binding<Int> {
        Binding(get: { binding(source)?.code ?? -1 }, set: { change(source, $0, "") })
    }
}
