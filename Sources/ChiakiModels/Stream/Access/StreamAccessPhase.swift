import Foundation

/// The code prompt of a stream, as a finite state machine.
///
/// ```
/// idle --request--> requested --submit--> submitting --accepted--> idle
///                                                    --refused--> failed --submit--> submitting
/// idle --recall saved PIN--> recalling --accepted--> idle
///                                      --missing / refused--> requested
/// requested, failed, submitting --cancel--> idle
/// ```
public enum StreamAccessPhase: Equatable, Sendable {
    /// No prompt is open.
    case idle

    /// A saved login PIN is being sent on the user's behalf by the attempt with this id.
    case recalling(UUID)

    /// The prompt is shown and waits for a code.
    case requested(StreamAccessPrompt)

    /// The typed code is being sent by the attempt with this id.
    case submitting(UUID, StreamAccessPrompt)

    /// The console refused the code; the prompt asks again.
    case failed(StreamAccessPrompt)

    /// The prompt that is open, when one is.
    public var prompt: StreamAccessPrompt? {
        switch self {
        case .requested(let prompt), .submitting(_, let prompt), .failed(let prompt):
            prompt
        case .idle, .recalling:
            nil
        }
    }

    /// Whether the console's login PIN prompt is open.
    public var loginPINOpen: Bool {
        prompt?.isLoginPIN ?? false
    }

    /// The couch pad whose passcode is asked for, when one is.
    public var passcodePad: UInt8? {
        prompt?.pad
    }
}

/// Where a Go to Home screen request made while the console hides its picture is.
///
/// ```
/// idle --requested while the picture is hidden--> waiting
/// waiting --the console shows its picture, the timer elapses or the session resets--> idle
/// ```
public enum HomeRequest: Equatable, Sendable {
    /// No request is waiting.
    case idle

    /// The request was sent and the console has not left the hidden screen yet; the timer with this id
    /// gives up waiting.
    case waiting(UUID)
}

/// The notice that the console refused to enter rest mode when the user left.
public enum RestNotice: Equatable, Sendable {
    /// Not shown.
    case hidden

    /// Shown until the timer with this id expires.
    case shown(UUID)
}

/// What a console stream does with the login PIN saved for its console, as a finite state machine.
///
/// The saved PIN is offered once per session. A PIN the user typed is remembered only after the stream has
/// played for a while with it; a PIN the console rejects is forgotten.
public enum SavedLoginPIN: Equatable, Sendable {
    /// The saved PIN has not been offered yet.
    case available

    /// The saved PIN is being read and sent.
    case recalling

    /// The console accepted the saved PIN.
    case recalled

    /// The user typed this PIN and it waits to be accepted.
    case typed(StreamAccessCode)

    /// The typed PIN was accepted while starting; the attempt with this id waits to see the stream hold.
    case verifying(UUID, StreamAccessCode)

    /// Nothing more is done with the PIN for this session.
    case settled
}
