import DesignSystem
import PlatformUI
import SwiftUI

/// The on-screen keyboard a controller types with.
///
/// Directions move the selected key and confirm presses it; Square deletes, Triangle types a space, the left
/// trigger toggles shift and the right trigger is Done; back closes without moving on. Typing on a hardware
/// keyboard goes straight into the text field, and arrows there move between keys only once the user starts
/// navigating.
public struct ControllerOnScreenKeyboard: View {
    private enum KeyboardEntryMode {
        case typing
        case navigating
    }

    private let title: String
    @Binding private var text: String
    private let secure: Bool
    private let numberPad: Bool
    private let allowsNewline: Bool
    private let sourceWindow: PlatformWindow
    private let dismiss: (Bool) -> Void
    @State private var layout = ControllerKeyboardLayout()
    @State private var selectedKey: ControllerKeyboardLayout.Key = .glyph(0, 0)
    @State private var entryMode = KeyboardEntryMode.typing
    @MenuFocusState private var focus: ControllerKeyboardLayout.Key?
    @MenuFocusState private var typingFocused: Bool

    /// Creates the keyboard.
    ///
    /// - Parameters:
    ///   - title: The keyboard's title.
    ///   - text: The text being edited.
    ///   - secure: Whether the text is hidden.
    ///   - numberPad: Whether to show the number pad.
    ///   - allowsNewline: Whether to offer Return.
    ///   - sourceWindow: The window the keyboard was opened from.
    ///   - dismiss: Closes the keyboard; receives whether Done was chosen.
    public init(
        title: String,
        text: Binding<String>,
        secure: Bool,
        numberPad: Bool,
        allowsNewline: Bool,
        sourceWindow: PlatformWindow,
        dismiss: @escaping (Bool) -> Void
    ) {
        self.title = title
        _text = text
        self.secure = secure
        self.numberPad = numberPad
        self.allowsNewline = allowsNewline
        self.sourceWindow = sourceWindow
        self.dismiss = dismiss
    }

    private var keyboardWidth: CGFloat {
        min(540, max(336, (WindowFocus(sourceWindow).contentBounds?.width ?? 564) - 24))
    }

    /// The title, hints, text field and key grid.
    public var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ControllerKeyboardHints(numberPad: numberPad)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            textEntry
            keys
        }
        .padding(22)
        .frame(width: keyboardWidth)
        .tint(Palette.accent)
        .onAppear {
            appear()
        }
        .onChange(of: focus) { _, value in
            if let value {
                selectedKey = value
            }
        }
        .onMenuKeyPress(phases: .down) { press in
            typed(press)
        }
        .menuHandlers(move: moveSelection, modalActivate: activateSelection)
        .onMenuExitCommand {
            dismiss(false)
        }
        .onMenuCommand([.alternate, .focusToolbar, .shift, .commit]) { event in
            command(event)
        }
    }

    private var keys: some View {
        VStack(spacing: 6) {
            ForEach(layout.rows.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(layout.rows[row].indices, id: \.self) { column in
                        key(.glyph(row, column), title: layout.rows[row][column])
                    }
                }
            }
            HStack(spacing: 6) {
                if !numberPad {
                    key(.shift, title: "Shift")
                    key(.symbols, title: "123")
                    key(.space, title: "Space")
                    if allowsNewline {
                        key(.newline, title: "Return")
                    }
                }
                key(.clear, title: "Clear")
                key(.delete, title: "Delete")
                key(.done, title: "Done")
            }
        }
    }

    private func appear() {
        layout.page = numberPad
            ? .symbols
            : .lower
        layout.allowsNewline = allowsNewline
        layout.numberPad = numberPad
        selectedKey = .glyph(0, 0)
        typingFocused = true
    }

    private func moveSelection(_ window: PlatformWindow, _ direction: MenuMoveDirection) -> Bool {
        guard isKeyboardWindow(window) else {
            return false
        }
        selectedKey = layout.moved(from: selectedKey, direction: direction)
        return true
    }

    private func activateSelection(_ window: PlatformWindow) -> Bool {
        guard isKeyboardWindow(window) else {
            return false
        }
        activate(selectedKey)
        return true
    }

    private func typed(_ press: MenuKeyPress) -> MenuKeyPress.Result {
        if press.key == .delete || press.key == .deleteForward, !text.isEmpty {
            text.removeLast()
            return .handled
        }
        guard !typingFocused,
              !press.modifiers.contains(.command),
              !press.modifiers.contains(.control),
              !press.characters.isEmpty,
              press.characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            return .ignored
        }
        text.append(contentsOf: press.characters)
        typingFocused = true
        return .handled
    }

    private func command(_ event: MenuCommandEvent) {
        guard isKeyboardWindow(event) else {
            return
        }
        switch event.command {
        case .alternate:
            activate(.delete)
        case .focusToolbar where !numberPad:
            activate(.space)
        case .shift where !numberPad:
            activate(.shift)
        case .commit:
            activate(.done)
        default:
            break
        }
    }

    private func isKeyboardWindow(_ window: PlatformWindow) -> Bool {
        WindowFocus(sourceWindow).presentsSheet(reachedThrough: window)
    }

    private func isKeyboardWindow(_ event: MenuCommandEvent) -> Bool {
        guard WindowFocus(sourceWindow).hasAttachedSheet else {
            return false
        }
        #if os(macOS)
            return event.targets(sourceWindow) || event.targets(sourceWindow.attachedSheet)
        #else
            return event.targets(sourceWindow)
        #endif
    }

    @ViewBuilder private var textEntry: some View {
        Group {
            if secure {
                SecureField(title, text: $text)
                    .menuFocusBinding($typingFocused)
            } else {
                TextField(title, text: $text)
                    .menuFocusBinding($typingFocused)
            }
        }
        .onMenuKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [
            .down,
            .repeat
        ]) { press in
            navigate(press.key)
        }
        .onMenuKeyPress(.return, phases: .down) { _ in
            submitFromKeyboard()
        }
        .onMenuKeyPress(phases: .down) { press in
            if !press.characters.isEmpty, press.key != .return {
                entryMode = .typing
            }
            return .ignored
        }
        .textFieldStyle(.plain)
        .font(.title3)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityLabel(title)
    }

    private func activate(_ key: ControllerKeyboardLayout.Key) {
        if layout.press(key, editing: &text) {
            dismiss(true)
        }
    }

    private func key(_ value: ControllerKeyboardLayout.Key, title: String) -> some View {
        FocusButton {
            selectedKey = value
            activate(value)
            typingFocused = true
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(9))
        .focusWithoutGrowth()
        .glassEffect(AppGlass.control, in: .rect(cornerRadius: 9))
        .menuFocusBinding($focus, equals: value)
        .environment(\.menuItemFocused, selectedKey == value)
        .environment(\.menuMove) { direction in
            selectedKey = layout.moved(from: value, direction: direction)
        }
        .accessibilityLabel(title)
    }

    private func navigate(_ key: KeyEquivalent) -> MenuKeyPress.Result {
        guard let direction = MenuMoveDirection(key) else {
            return .ignored
        }
        if !direction.isVertical, entryMode == .typing, !numberPad {
            return .ignored
        }
        entryMode = .navigating
        selectedKey = layout.moved(from: selectedKey, direction: direction)
        return .handled
    }

    private func submitFromKeyboard() -> MenuKeyPress.Result {
        switch entryMode {
        case .navigating:
            activate(selectedKey)
        case .typing:
            dismiss(true)
        }
        return .handled
    }
}

/// The button hints shown above the on-screen keyboard's keys.
private struct ControllerKeyboardHints: View {
    /// Whether the keyboard is a number pad, which has no space or shift.
    let numberPad: Bool

    /// One hint per shortcut, in the connected controller's glyphs.
    var body: some View {
        HStack(spacing: 14) {
            ControllerPrompt(button: .west, text: "Delete")
            if !numberPad {
                ControllerPrompt(button: .north, text: "Space")
                ControllerPrompt(control: .leftTrigger, text: "Shift")
            }
            ControllerPrompt(control: .rightTrigger, text: "Done")
            ControllerPrompt(button: .east, text: "Close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The key grid of the on-screen keyboard and how the controller moves across it.
///
/// Glyph keys sit in rows above a bottom row of action keys. Moving past the end of a row clamps to its
/// last key; moving between rows of different lengths keeps the column where it can.
public struct ControllerKeyboardLayout: Sendable {
    /// Which set of glyphs the keyboard shows.
    public enum Page: Equatable, Sendable {
        /// Lowercase letters.
        case lower
        /// Uppercase letters.
        case upper
        /// Digits and punctuation.
        case symbols
    }

    /// One key of the keyboard.
    public enum Key: Hashable, Sendable {
        /// The glyph at a row and column of the current page.
        case glyph(Int, Int)
        /// Switches between lowercase and uppercase.
        case shift
        /// Switches between letters and symbols.
        case symbols
        /// Types a space.
        case space
        /// Types a line break, where the field allows one.
        case newline
        /// Clears the text.
        case clear
        /// Deletes the last character.
        case delete
        /// Closes the keyboard, keeping the text.
        case done
    }

    /// The page shown.
    public var page: Page = .lower

    /// Whether the bottom row offers Return.
    public var allowsNewline = false

    /// Whether the keyboard is a number pad with digits and the clear, delete and done keys only.
    public var numberPad = false

    /// Creates a lowercase letter keyboard.
    public init() {
    }

    private var bottomKeys: [Key] {
        if numberPad {
            return [.clear, .delete, .done]
        }
        var keys: [Key] = [.shift, .symbols, .space]
        if allowsNewline {
            keys.append(.newline)
        }
        keys += [.clear, .delete, .done]
        return keys
    }

    /// The glyphs of each row on the current page.
    public var rows: [[String]] {
        if numberPad {
            return ["123", "456", "789", "0"].map { $0.map(String.init) }
        }
        switch page {
        case .lower:
            return ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
        case .upper:
            return ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"].map { $0.map(String.init) }
        case .symbols:
            return ["1234567890", "@#$%&*-+=", "/.:_!?'"].map { $0.map(String.init) }
        }
    }

    /// The text a glyph key types.
    ///
    /// - Parameter key: A key.
    /// - Returns: The glyph, or `nil` for an action key or a position outside the grid.
    public func glyph(at key: Key) -> String? {
        guard case .glyph(let row, let column) = key,
              rows.indices.contains(row), rows[row].indices.contains(column) else {
            return nil
        }
        return rows[row][column]
    }

    /// The key a direction press moves to.
    ///
    /// - Parameters:
    ///   - key: The selected key.
    ///   - direction: The direction pressed.
    /// - Returns: The neighbouring key, or `key` itself at the top and bottom edges.
    public func moved(from key: Key, direction: MenuMoveDirection) -> Key {
        let position: (row: Int, column: Int)
        switch key {
        case .glyph(let row, let column):
            position = (row, column)
        case .shift, .symbols, .space, .newline, .clear, .delete, .done:
            guard let index = bottomKeys.firstIndex(of: key) else {
                return key
            }
            position = (rows.count, index)
        }
        var next = position
        switch direction {
        case .left:
            next.column -= 1
        case .right:
            next.column += 1
        case .up:
            next.row -= 1
        case .down:
            next.row += 1
        }
        guard (0...rows.count).contains(next.row) else {
            return key
        }
        let count = next.row == rows.count
            ? bottomKeys.count
            : rows[next.row].count
        next.column = max(0, min(next.column, count - 1))
        if next.row < rows.count {
            return .glyph(next.row, next.column)
        }
        return bottomKeys[next.column]
    }

    /// Switches between lowercase and uppercase.
    public mutating func toggleShift() {
        page = page == .upper
            ? .lower
            : .upper
    }

    /// Switches between letters and symbols.
    public mutating func toggleSymbols() {
        page = page == .symbols
            ? .lower
            : .symbols
    }

    /// Presses a key, editing the text or switching the page.
    ///
    /// - Parameters:
    ///   - key: The key pressed.
    ///   - text: The text being edited.
    /// - Returns: `true` when the key was Done and the keyboard should close.
    public mutating func press(_ key: Key, editing text: inout String) -> Bool {
        switch key {
        case .glyph:
            if let glyph = glyph(at: key) {
                text.append(glyph)
            }
        case .shift:
            toggleShift()
        case .symbols:
            toggleSymbols()
        case .space:
            text.append(" ")
        case .newline:
            text.append("\n")
        case .clear:
            text = ""
        case .delete:
            if !text.isEmpty {
                text.removeLast()
            }
        case .done:
            return true
        }
        return false
    }
}
