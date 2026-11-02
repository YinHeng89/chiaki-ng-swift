import Foundation

/// The console on-screen keyboard's state machine.
///
/// Local edits are sent straight away and remembered until the console echoes them back, so an echo of an older
/// edit never overwrites newer typing. Events for a session other than the open one are ignored.
public struct ConsoleKeyboard: Equatable, Sendable {
    /// How many unconfirmed edits are remembered.
    public static let unconfirmedLimit = 64

    /// The longest text sent, in UTF-8 bytes.
    public static let textByteLimit = 4096

    /// The current phase.
    public private(set) var phase = ConsoleKeyboardPhase.closed

    /// Creates a closed keyboard.
    public init() {
    }

    /// The open session, if any.
    public var session: ConsoleKeyboardSession? {
        switch phase {
        case .closed:
            nil
        case .editing(let session):
            session
        }
    }

    /// Applies an event.
    ///
    /// - Parameter event: What happened.
    /// - Returns: The commands to send to the console, in order.
    @discardableResult
    public mutating func send(_ event: ConsoleKeyboardEvent) -> [ConsoleKeyboardCommand] {
        switch (phase, event) {
        case (_, .remoteOpened(let id, let text)):
            phase = .editing(ConsoleKeyboardSession(id: id, text: text))
            return []
        case (.editing(var session), .remoteTextChanged(let text)):
            confirm(text, in: &session)
            phase = .editing(session)
            return []
        case (.editing, .remoteClosed), (.editing, .streamEnded):
            phase = .closed
            return []
        case (.editing(var session), .edited(let id, let edited)) where session.id == id:
            let text = Self.limited(edited)
            guard session.text != text else {
                return []
            }
            session.text = text
            session.unconfirmed.append(text)
            if session.unconfirmed.count > Self.unconfirmedLimit {
                session.unconfirmed.removeFirst(session.unconfirmed.count - Self.unconfirmedLimit)
            }
            phase = .editing(session)
            return [.setText(text)]
        case (.editing(let session), .accepted(let id)) where session.id == id:
            phase = .closed
            return [.accept(session.text)]
        case (.editing(let session), .rejected(let id)) where session.id == id:
            phase = .closed
            return [.reject]
        case (.closed, _), (.editing, .edited), (.editing, .accepted), (.editing, .rejected):
            return []
        }
    }

    /// Truncates text to ``textByteLimit`` UTF-8 bytes on a character boundary.
    ///
    /// - Parameter text: The text.
    /// - Returns: The text, shortened when needed.
    public static func limited(_ text: String) -> String {
        guard text.utf8.count > textByteLimit else {
            return text
        }
        var end = text.utf8.index(text.utf8.startIndex, offsetBy: textByteLimit)
        while end > text.startIndex, end.samePosition(in: text) == nil {
            end = text.utf8.index(before: end)
        }
        return String(text[..<end])
    }

    private func confirm(_ text: String, in session: inout ConsoleKeyboardSession) {
        if let index = session.unconfirmed.firstIndex(of: text) {
            session.unconfirmed.removeFirst(index + 1)
            return
        }
        session.unconfirmed.removeAll()
        session.text = text
    }
}

/// Whether the console's on-screen keyboard is open.
public enum ConsoleKeyboardPhase: Equatable, Sendable {
    /// Closed.
    case closed

    /// Open, with the session being edited.
    case editing(ConsoleKeyboardSession)
}

/// One opening of the console's on-screen keyboard and its text.
public struct ConsoleKeyboardSession: Equatable, Sendable {
    /// Identifies this opening, so edits from an earlier one are ignored.
    public let id: UUID

    /// The text as the app last set or confirmed it.
    public internal(set) var text: String

    /// Texts sent to the console that it has not echoed back yet, oldest first, so a late echo does not
    /// overwrite newer edits.
    var unconfirmed: [String]

    /// Starts a session with the console's initial text and no pending edits.
    ///
    /// - Parameters:
    ///   - id: The identifier for this opening.
    ///   - text: The text the console opened the keyboard with.
    init(id: UUID, text: String) {
        self.id = id
        self.text = text
        unconfirmed = []
    }
}

/// Something that happened to the console keyboard, from the console or the user.
public enum ConsoleKeyboardEvent: Equatable, Sendable {
    /// The console opened its keyboard; the id names the new session.
    case remoteOpened(UUID, String)

    /// The console reported new text.
    case remoteTextChanged(String)

    /// The console closed its keyboard.
    case remoteClosed

    /// The user edited the text of a session.
    case edited(UUID, String)

    /// The user accepted a session's text.
    case accepted(UUID)

    /// The user dismissed a session.
    case rejected(UUID)

    /// The stream ended.
    case streamEnded
}

/// What the app sends to the console's on-screen keyboard.
public enum ConsoleKeyboardCommand: Equatable, Sendable {
    /// Replace the console's text.
    case setText(String)

    /// Accept the given text and close the keyboard.
    case accept(String)

    /// Dismiss the keyboard without accepting.
    case reject
}

/// What the console reports about its on-screen keyboard.
public enum ConsoleKeyboardSignal: Equatable, Sendable {
    /// The console opened its keyboard with the given text.
    case opened(String)

    /// The console's text changed to the given text.
    case textChanged(String)

    /// The console closed its keyboard.
    case closed
}
