import Foundation

/// Decides when a command-line launch quits the app: after the launched stream ends, or after any stream
/// the session watches ends.
///
/// The watch arms on a launch or a session request, follows the stream that answers it, and reports
/// ``Outcome/quit`` exactly once.
public enum ExitWatch: Equatable, Sendable {
    /// What the watch returns to when the launch it armed for is replaced.
    public enum Fallback: Equatable, Sendable {
        /// Nothing is watched.
        case disabled
        /// The session asked to quit after its stream.
        case session
    }

    /// What the watch is told.
    public enum Event: Equatable, Sendable {
        /// The session asked to quit after its next stream.
        case sessionRequested
        /// The launch with this id started connecting.
        case launchConnecting(UUID)
        /// The launch with this id ended as its request asked.
        case launchEnded(UUID, LaunchStreamExit)
        /// The launch with this id was replaced by another.
        case launchSuperseded(UUID)
        /// A stream started playing.
        case streamPlaying
        /// The stream ended.
        case streamEnded
    }

    /// What the app does after an event.
    public enum Outcome: Equatable, Sendable {
        /// Keep running.
        case stay
        /// Quit the app.
        case quit
    }

    /// Nothing is watched.
    case disabled
    /// The session asked to quit after its next stream.
    case session
    /// The launch with this id is watched, with what to return to if it is replaced.
    case launch(UUID, then: Fallback)
    /// A playing stream is watched.
    case watching
    /// The app is quitting.
    case quitting

    /// Moves the watch for an event.
    ///
    /// - Parameter event: What happened.
    /// - Returns: ``Outcome/quit`` when the app should quit now.
    public mutating func send(_ event: Event) -> Outcome {
        switch (self, event) {
        case (.disabled, .sessionRequested):
            self = .session
        case (.launch(let id, .disabled), .sessionRequested):
            self = .launch(id, then: .session)
        case (.disabled, .launchConnecting(let id)):
            self = .launch(id, then: .disabled)
        case (.session, .launchConnecting(let id)):
            self = .launch(id, then: .session)
        case (.disabled, .launchEnded(_, .quitApp)), (.session, .launchEnded(_, .quitApp)),
             (.watching, .launchEnded(_, .quitApp)):
            self = .quitting
            return .quit
        case (.launch(let armed, _), .launchEnded(let id, _)) where armed == id:
            self = .quitting
            return .quit
        case (.launch(let armed, let fallback), .launchSuperseded(let id)) where armed == id:
            self = Self(fallback)
        case (.session, .streamPlaying), (.launch, .streamPlaying):
            self = .watching
        case (.watching, .streamEnded):
            self = .quitting
            return .quit
        case (.disabled, _), (.session, _), (.launch, _), (.watching, _), (.quitting, _):
            break
        }
        return .stay
    }

    private init(_ fallback: Fallback) {
        switch fallback {
        case .disabled:
            self = .disabled
        case .session:
            self = .session
        }
    }
}
