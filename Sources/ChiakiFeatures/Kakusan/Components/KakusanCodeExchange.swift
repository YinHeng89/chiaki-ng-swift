import ChiakiModels
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// A field for the other device's verification code, shown digit by digit.
public struct KakusanCodeField: View {
    /// The heading above the digits.
    public let title: LocalizedStringResource
    /// The digits typed so far.
    @Binding public var code: String
    /// Whether the card's selection is on the field.
    public let selected: Bool
    /// Changes when the field should take keyboard focus.
    public let keyboardRequest: Int
    /// Called when the code is submitted.
    public let submit: () -> Void
    @Environment(\.menuNavigator) private var navigator
    @MenuFocusState private var focused: Bool
    @State private var hostWindow: PlatformWindow?

    /// Creates a Kakusan code field.
    ///
    /// - Parameters:
    ///   - title: The heading above the digits.
    ///   - code: The digits typed so far.
    ///   - selected: Whether the card's selection is on the field.
    ///   - keyboardRequest: Changes when the field should take keyboard focus.
    ///   - submit: Called when the code is submitted.
    public init(
        title: LocalizedStringResource,
        code: Binding<String>,
        selected: Bool,
        keyboardRequest: Int,
        submit: @escaping () -> Void
    ) {
        self.title = title
        _code = code
        self.selected = selected
        self.keyboardRequest = keyboardRequest
        self.submit = submit
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            ZStack {
                HStack(spacing: 10) {
                    ForEach(0 ..< KakusanCode.length, id: \.self) { index in
                        digit(index)
                    }
                }
                TextField("", text: digits)
                    .textFieldStyle(.plain)
                    .menuFocusBinding($focused)
                    .onSubmit(submit)
                    .opacity(0.02)
                    .frame(width: 238, height: 62)
                    .accessibilityLabel(title)
                #if os(iOS)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                #endif
            }
            .contentShape(Rectangle())
            .onTapGesture {
                beginTyping()
            }
        }
        .frame(maxWidth: .infinity)
        .controllerKeyboard(
            title: title,
            text: digits,
            isFocused: focused || selected,
            numberPad: true,
            presentationRequest: keyboardRequest,
            presentationWindow: hostWindow
        )
        .background(WindowAccessor { hostWindow = $0 })
    }

    private func beginTyping() {
        focused = true
        #if os(iOS)
            let window = hostWindow
            let navigator = navigator
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                navigator?.beginEditing(in: window)
            }
        #endif
    }

    private var digits: Binding<String> {
        Binding(
            get: {
                code
            },
            set: { value in
                code = KakusanCode.digitsOnly(value)
            }
        )
    }

    private func digit(_ index: Int) -> some View {
        let characters = Array(code)
        let filled = index < characters.count
        let highlighted = selected || focused
        return Text(filled
            ? String(characters[index])
            : " ")
            .font(.system(size: 30, weight: .semibold, design: .monospaced))
            .frame(width: 52, height: 62)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        highlighted && index == min(characters.count, KakusanCode.length - 1)
                            ? Palette.accent
                            : Color.primary.opacity(0.14),
                        lineWidth: highlighted
                            ? 2
                            : 1
                    )
            }
    }
}

/// This device's verification code, digit by digit.
public struct KakusanCodeDisplay: View {
    /// The heading above the digits.
    public let title: LocalizedStringResource
    /// The code, or nothing while it is not ready.
    public let code: KakusanCode?

    /// Creates a Kakusan code display.
    ///
    /// - Parameters:
    ///   - title: The heading above the digits.
    ///   - code: The code, or nothing while it is not ready.
    public init(title: LocalizedStringResource, code: KakusanCode?) {
        self.title = title
        self.code = code
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            HStack(spacing: 10) {
                if let code {
                    ForEach(Array(code.digits.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                            .frame(width: 52, height: 62)
                            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 14))
                    }
                } else {
                    ProgressView()
                        .frame(height: 62)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenCode)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 18))
    }
}

extension KakusanCodeDisplay {
    private var spokenCode: LocalizedStringResource {
        guard let code else {
            return title
        }
        let digits = code.digits.map(String.init).joined(separator: " ")
        return .kakusanCodeAccessibility(title: String(localized: title), digits: digits)
    }
}

/// The first lines of an invitation or reply block.
public struct KakusanBlockPreview: View {
    /// The heading above the preview.
    public let label: LocalizedStringResource
    /// The block whose first lines are shown.
    public let block: KakusanBlock

    /// Creates a Kakusan block preview.
    ///
    /// - Parameters:
    ///   - label: The heading above the preview.
    ///   - block: The block whose first lines are shown.
    public init(label: LocalizedStringResource, block: KakusanBlock) {
        self.label = label
        self.block = block
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
            Text(block.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
                .accessibilityLabel(.kakusanBlockAccessibility(label: String(localized: label)))
        }
    }
}

/// Copies a block, and shares it as a file once the feature has written one.
///
/// Copying and writing the file are the feature's effects; the view reports that it appeared with `shown`, and
/// the feature removes the file when the card goes away.
public struct KakusanCopyButton: View {
    /// The button's title before copying.
    public let title: LocalizedStringResource
    /// The block's text, shared while no file is ready.
    public let text: String
    /// Whether the block was copied.
    public let copied: Bool
    /// The block's file, once written.
    public let file: URL?
    /// The card's controls.
    public let controls: KakusanControlGrid
    /// Copies the block.
    public let copy: () -> Void
    /// Tells the feature the button appeared.
    public let shown: () -> Void

    /// Creates a Kakusan copy button.
    ///
    /// - Parameters:
    ///   - title: The button's title before copying.
    ///   - text: The block's text, shared while no file is ready.
    ///   - copied: Whether the block was copied.
    ///   - file: The block's file, once written.
    ///   - controls: The card's controls.
    ///   - copy: Copies the block.
    ///   - shown: Tells the feature the button appeared.
    public init(
        title: LocalizedStringResource,
        text: String,
        copied: Bool,
        file: URL?,
        controls: KakusanControlGrid,
        copy: @escaping () -> Void,
        shown: @escaping () -> Void
    ) {
        self.title = title
        self.text = text
        self.copied = copied
        self.file = file
        self.controls = controls
        self.copy = copy
        self.shown = shown
    }

    public var body: some View {
        HStack(spacing: 10) {
            FocusButton(action: copy) {
                Label {
                    Text(copied
                        ? .kakusanCopyCopied
                        : title)
                } icon: {
                    Image(systemName: copied
                        ? "checkmark"
                        : "doc.on.doc")
                }
                .frame(maxWidth: .infinity)
            }
            .glassProminentControlStyle()
            .controlSize(.large)
            .kakusanControl(.copy, in: controls)
            share
                .glassControlStyle()
                .controlSize(.large)
                .focusable(false)
        }
        .onAppear(perform: shown)
    }

    @ViewBuilder private var share: some View {
        if let file {
            ShareLink(item: file) {
                Label(.kakusanCopyShare, systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: text) {
                Label(.kakusanCopyShare, systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// A multi-line field for pasting an invitation or reply block.
public struct KakusanTextBlockField: View {
    /// The field's accessibility label.
    public let title: LocalizedStringResource
    /// The pasted text.
    @Binding public var text: String
    /// How many lines the field grows between.
    public let lines: ClosedRange<Int>
    /// Whether the card's selection is on the field.
    public let selected: Bool
    /// Changes when the field should take keyboard focus.
    public let keyboardRequest: Int
    /// Called when the text is submitted.
    public var submit: () -> Void = {}
    @MenuFocusState private var focused: Bool
    @State private var hostWindow: PlatformWindow?

    /// Creates a Kakusan text block field.
    ///
    /// - Parameters:
    ///   - title: The field's accessibility label.
    ///   - text: The pasted text.
    ///   - lines: How many lines the field grows between.
    ///   - selected: Whether the card's selection is on the field.
    ///   - keyboardRequest: Changes when the field should take keyboard focus.
    ///   - submit: Called when the text is submitted.
    public init(
        title: LocalizedStringResource,
        text: Binding<String>,
        lines: ClosedRange<Int>,
        selected: Bool,
        keyboardRequest: Int,
        submit: @escaping () -> Void = {}
    ) {
        self.title = title
        _text = text
        self.lines = lines
        self.selected = selected
        self.keyboardRequest = keyboardRequest
        self.submit = submit
    }

    public var body: some View {
        TextField(text: $text, axis: .vertical) {
            Text(verbatim: "RCP1:")
        }
        .textFieldStyle(.plain)
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(lines)
        .menuFocusBinding($focused)
        .onSubmit(submit)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected
                    ? Palette.accent
                    : Color.clear, lineWidth: 2)
        }
        .accessibilityLabel(title)
        .controllerKeyboard(
            title: title,
            text: $text,
            isFocused: focused || selected,
            presentationRequest: keyboardRequest,
            presentationWindow: hostWindow
        )
        .background(WindowAccessor { hostWindow = $0 })
    }
}
