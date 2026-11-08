import Foundation
import SwiftUI

/// A text field to edit with the software keyboard: its title, its value and how it is typed.
public struct TouchKeyboardRequest: Identifiable {
    /// The kind of text a field takes, which picks its keyboard.
    public enum Kind: Sendable {
        /// Ordinary words.
        case text
        /// A search query.
        case search
        /// Network addresses and subnets.
        case address
        /// A web address.
        case url
        /// A whole number.
        case number
    }

    /// Identifies this editing session.
    public let id = UUID()

    /// The field's title, shown above the value.
    public let title: LocalizedStringResource

    /// The placeholder shown while the value is empty.
    public let prompt: LocalizedStringResource

    /// The value.
    public let text: Binding<String>

    /// The kind of text the field takes.
    public var kind: Kind

    /// Whether Return starts a new line instead of finishing.
    public var multiline: Bool

    /// Whether the value is hidden as it is typed.
    public var secure: Bool

    /// Runs when editing finishes.
    public var finished: (() -> Void)?

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - title: The field's title, shown above the value.
    ///   - prompt: The placeholder shown while the value is empty.
    ///   - text: The value.
    ///   - kind: The kind of text the field takes.
    ///   - multiline: Whether Return starts a new line instead of finishing.
    ///   - secure: Whether the value is hidden as it is typed.
    ///   - finished: Runs when editing finishes.
    public init(
        title: LocalizedStringResource,
        prompt: LocalizedStringResource,
        text: Binding<String>,
        kind: Kind = .text,
        multiline: Bool = false,
        secure: Bool = false,
        finished: (() -> Void)? = nil
    ) {
        self.title = title
        self.prompt = prompt
        self.text = text
        self.kind = kind
        self.multiline = multiline
        self.secure = secure
        self.finished = finished
    }
}

/// Opens a text field in the touch editor, which shows the field large above the software keyboard.
public struct TouchKeyboardAction {
    private let open: (TouchKeyboardRequest) -> Void

    /// Creates the action.
    ///
    /// - Parameter open: Opens a field in the editor.
    public init(open: @escaping (TouchKeyboardRequest) -> Void) {
        self.open = open
    }

    /// Opens a field in the editor.
    ///
    /// - Parameter request: The field.
    public func callAsFunction(_ request: TouchKeyboardRequest) {
        open(request)
    }
}

extension EnvironmentValues {
    /// Opens a text field in the touch editor, or `nil` where no editor is hosted.
    @Entry public var touchKeyboard: TouchKeyboardAction?
}
