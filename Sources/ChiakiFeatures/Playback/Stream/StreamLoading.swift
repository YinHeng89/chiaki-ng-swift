import ChiakiModels
import Foundation

/// The loading screen a cloud stream shows until its picture has faded in, as a finite state machine.
///
/// ```
/// hidden --start--> shown(card) --art arrived--> shown(layered)
/// shown --first frame--> leaving --exit animation done--> hidden
/// any --session not starting or playing--> hidden
/// ```
public enum StreamLoading: Equatable, Sendable {
    /// What the loading screen shows.
    public enum Screen: Equatable, Sendable {
        /// The title card.
        case card

        /// The title's layered artwork.
        case layered(GameArtLayers)

        /// How long the screen takes to fade out.
        public var exit: Duration {
            switch self {
            case .card:
                .milliseconds(600)
            case .layered:
                .milliseconds(1700)
            }
        }
    }

    /// No loading screen.
    case hidden

    /// The loading screen is shown.
    case shown(Screen)

    /// The loading screen is fading out over the first frames.
    case leaving(Screen)

    /// The screen shown or leaving.
    public var screen: Screen? {
        switch self {
        case .hidden:
            nil
        case .shown(let screen), .leaving(let screen):
            screen
        }
    }

    /// Whether the screen is fading out.
    public var isLeaving: Bool {
        if case .leaving = self {
            return true
        }
        return false
    }
}
