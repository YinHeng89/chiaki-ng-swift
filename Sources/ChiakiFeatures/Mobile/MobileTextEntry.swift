import DesignSystem
import MenuFocus
import SwiftUI

/// Hosts the touch text editor: while a field is open, the screen dims and the field, its title and its value
/// sit large above the software keyboard, so what is being typed never hides behind it.
struct MobileTextEntryStage: ViewModifier {
    @State private var entry: TouchKeyboardRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The content with the editor over it while a field is open.
    ///
    /// - Parameter content: The content.
    /// - Returns: The content hosting the editor.
    func body(content: Content) -> some View {
        content
            .environment(\.touchKeyboard, TouchKeyboardAction { entry = $0 })
            .overlay {
                if let entry {
                    MobileTextEntryEditor(entry: entry) {
                        entry.finished?()
                        self.entry = nil
                    }
                    .id(entry.id)
                    .transition(.opacity)
                }
            }
            .animation(AppMotion.animation(reduced: reduceMotion), value: entry?.id)
    }
}

/// The editor of an open field: a dimmed screen with the field large in the space above the keyboard.
private struct MobileTextEntryEditor: View {
    let entry: TouchKeyboardRequest
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.7))
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Done", action: close)
                        .buttonStyle(.glassProminent)
                        .tint(Palette.accent)
                        .foregroundStyle(.black)
                }
                field
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: 2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: 640)
            .background(Color(white: 0.12), in: .rect(cornerRadius: 28))
            .glassEffect(AppGlass.control, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .onAppear {
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                close()
            }
        }
    }

    @ViewBuilder private var field: some View {
        if entry.secure {
            SecureField(entry.title, text: entry.text, prompt: Text(entry.prompt))
                .modifier(MobileTextEntryInput(entry: entry, focused: $focused))
                .submitLabel(.done)
                .onSubmit(close)
        } else if entry.multiline {
            TextField(entry.title, text: entry.text, prompt: Text(entry.prompt), axis: .vertical)
                .lineLimit(1...4)
                .modifier(MobileTextEntryInput(entry: entry, focused: $focused))
        } else {
            TextField(entry.title, text: entry.text, prompt: Text(entry.prompt))
                .modifier(MobileTextEntryInput(entry: entry, focused: $focused))
                .submitLabel(
                    entry.kind == .search
                        ? .search
                        : .done
                )
                .onSubmit(close)
        }
    }
}

/// The shared look and keyboard of the editor's field.
private struct MobileTextEntryInput: ViewModifier {
    let entry: TouchKeyboardRequest
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .font(.title2)
            .focused(focused)
            .autocorrectionDisabled(!entry.multiline)
        #if os(iOS)
            .textInputAutocapitalization(
                entry.multiline
                    ? .sentences
                    : .never
            )
            .keyboardType(keyboard)
            .textContentType(
                entry.kind == .number
                    ? .oneTimeCode
                    : nil
            )
        #endif
    }

    #if os(iOS)
        private var keyboard: UIKeyboardType {
            switch entry.kind {
            case .text, .search:
                .default
            case .address:
                .numbersAndPunctuation
            case .url:
                .URL
            case .number:
                .numberPad
            }
        }
    #endif
}

/// A settings row showing a field's value, opening it in the editor above the keyboard when tapped.
///
/// With a controller the row is one focus stop, and Confirm opens the on-screen keyboard instead.
struct MobileTextEntryRow: View {
    /// The title.
    let title: String

    /// The placeholder shown while the value is empty.
    let prompt: String

    /// The value.
    @Binding var text: String

    /// The kind of text the field takes.
    var kind = TouchKeyboardRequest.Kind.text

    /// Whether the value holds one entry per line.
    var multiline = false

    /// Whether the value is rejected, shown in red.
    var invalid = false

    /// Runs when editing finishes.
    var finished: (() -> Void)?

    @Environment(\.touchKeyboard) private var editor
    @Environment(\.isEnabled) private var isEnabled
    @MenuFocusState private var focused: Bool

    var body: some View {
        field
            .interactiveGrowth()
            .focusWithoutGrowth()
            .menuFocusable(isEnabled)
            .menuFocusBinding($focused)
            .environment(\.menuItemFocused, focused)
            .focusHighlightShape(MobileRowFocus.shape)
            .focusEffectDisabled()
            .controllerKeyboard(
                title: title,
                text: $text,
                isFocused: focused,
                numberPad: kind == .number,
                allowsNewline: multiline
            ) { _ in
                focused = true
                finished?()
            }
    }

    private var field: some View {
        Button {
            editor?(TouchKeyboardRequest(
                title: title,
                prompt: prompt,
                text: $text,
                kind: kind,
                multiline: multiline,
                finished: finished
            ))
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(shown)
                    .foregroundStyle(valueStyle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .mobileRowPadding()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(text)
    }

    private var shown: String {
        let value = multiline
            ? text.split(whereSeparator: \.isNewline).joined(separator: ", ")
            : text
        return value.isEmpty
            ? prompt
            : value
    }

    private var valueStyle: Color {
        if invalid {
            return .red
        }
        return text.isEmpty
            ? Color.secondary.opacity(0.6)
            : .secondary
    }
}

/// A search field showing its query, opening it in the editor above the keyboard when tapped.
struct MobileSearchEntry: View {
    /// The placeholder shown while the query is empty.
    let prompt: String

    /// The query.
    @Binding var text: String

    /// The kind of text the query takes.
    var kind = TouchKeyboardRequest.Kind.search

    @Environment(\.touchKeyboard) private var editor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(
                text.isEmpty
                    ? prompt
                    : text
            )
            .foregroundStyle(
                text.isEmpty
                    ? .secondary
                    : .primary
            )
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            editor?(TouchKeyboardRequest(title: prompt, prompt: prompt, text: $text, kind: kind))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prompt)
        .accessibilityValue(text)
        .accessibilityAddTraits(.isSearchField)
    }
}

extension View {
    /// Hosts the touch text editor over this view.
    ///
    /// - Returns: The view hosting the editor.
    func mobileTextEntryStage() -> some View {
        modifier(MobileTextEntryStage())
    }
}
