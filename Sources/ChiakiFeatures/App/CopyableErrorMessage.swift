import PlatformUI
import SwiftUI
import DesignSystem
import MenuFocus

/// Shows an error message as selectable text with a button that copies it, plus a button that opens the first
/// HTTPS link the message contains.
public struct CopyableErrorMessage: View {
    /// The error text to show and copy.
    public let message: String
    /// The font the message is drawn in.
    public var font: Font = .body
    /// The controller focus of the Copy error button, or `nil` when the screen leaves it to default focus.
    public var copyFocus: MenuFocusState<Bool>.Binding?

    /// Creates a copyable error message.
    ///
    /// - Parameters:
    ///   - message: The error text to show and copy.
    ///   - font: The font the message is drawn in.
    ///   - copyFocus: The controller focus of the Copy error button, or `nil` for default focus.
    public init(message: String, font: Font = .body, copyFocus: MenuFocusState<Bool>.Binding? = nil) {
        self.message = message
        self.font = font
        self.copyFocus = copyFocus
    }

    @State private var copied = false

    public var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(font)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                copyButton
                if let link = Self.link(in: message) {
                    Link(destination: link) {
                        Label("Open page", systemImage: "safari")
                    }
                    .glassControlStyle()
                }
            }
            .controlSize(.small)
        }
        .onChange(of: message) {
            copied = false
        }
    }

    @ViewBuilder private var copyButton: some View {
        let button = FocusButton(copyTitle, systemImage: copyImage) {
            PlatformPasteboard.copy(message)
            copied = true
        }
        .glassControlStyle()
        if let copyFocus {
            button.menuFocused(copyFocus)
        } else {
            button
        }
    }

    private var copyTitle: String {
        copied
            ? "Copied"
            : "Copy error"
    }

    private var copyImage: String {
        copied
            ? "checkmark"
            : "doc.on.doc"
    }

    /// Finds the first HTTPS link in a message.
    /// - Parameter message: The text to search.
    /// - Returns: The first `https` URL, or `nil` when there is none.
    public static func link(in message: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            return nil
        }
        let range = NSRange(message.startIndex..., in: message)
        return detector.matches(in: message, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "https" }
    }
}
