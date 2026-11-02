import Foundation

/// Something that happened to a guest's join.
public enum KakusanGuestInput: Equatable, Sendable {
    /// Preview inputs.
    public enum Preview: Equatable, Sendable {
        /// A preview was requested by the operation with the given id.
        case request(UUID)

        /// The preview succeeded.
        case succeeded(UUID, KakusanInvitationSummary)

        /// The preview failed.
        case failed(UUID, KakusanError)
    }

    /// Inputs from the running session.
    public enum Session: Equatable, Sendable {
        /// The reply is ready.
        case replyReady(KakusanBlock)

        /// The guest's code is ready.
        case codeReady(KakusanCode)

        /// The guest submitted the host's code, with the operation's id.
        case submitCode(UUID)

        /// The submission finished, with its error if any.
        case codeResult(UUID, KakusanError?)

        /// The session changed state.
        case state(KakusanStateChange)

        /// The stream is ready at the frame rate.
        case streamReady(fps: Int)

        /// The first frame was shown.
        case firstFrame

        /// The stream stopped.
        case streamStopped

        /// The session failed.
        case failed(KakusanError)

        /// The session ended.
        case ended

        /// The invitation expired.
        case expired

        /// The session was stopped.
        case stopped
    }

    /// The join screen opened.
    case open

    /// A preview input.
    case preview(Preview)

    /// The user accepted or withdrew the disclosure.
    case setDisclosure(Bool)

    /// A session started with the given id.
    case start(UUID)

    /// An input from the session with the given id.
    case session(UUID, Session)

    /// The user chose to leave.
    case leave

    /// The user went back to entering an invitation.
    case back
}
