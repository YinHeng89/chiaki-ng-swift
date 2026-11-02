import SwiftUI

/// Whether decorative motion such as ``AmbientBackground`` and ``ChiakiLogo`` should animate.
///
/// Views read it from the environment through `\.ambientMotion`; a view tree sets it with
/// `ambientMotion(streaming:)`.
public enum AmbientMotionState: Equatable {
    /// Why decorative motion is paused.
    public enum Reason: Equatable {
        /// The user turned on Reduce Motion.
        case reduceMotion

        /// A stream is playing, so decoration would compete with it for attention and power.
        case streaming

        /// The window is hidden, minimised, covered or in the background.
        case windowHidden

        /// The window is visible but is not the one the user is working in.
        case windowInactive
    }

    /// Decorative motion animates.
    case running

    /// Decorative motion holds its current frame.
    case paused(Reason)

    /// Whether decorative motion animates.
    public var isRunning: Bool {
        self == .running
    }

    /// Decides whether decorative motion runs, checking each reason to pause in order of precedence.
    ///
    /// - Parameters:
    ///   - reduceMotion: Whether Reduce Motion is on.
    ///   - streaming: Whether a stream is playing.
    ///   - window: The state of the window showing the motion.
    /// - Returns: ``running`` only when nothing calls for a pause; otherwise the first applicable reason.
    static func resolve(
        reduceMotion: Bool,
        streaming: Bool,
        window: AmbientWindowState
    ) -> AmbientMotionState {
        if reduceMotion {
            return .paused(.reduceMotion)
        }
        if streaming {
            return .paused(.streaming)
        }
        if !window.visible {
            return .paused(.windowHidden)
        }
        if !window.main {
            return .paused(.windowInactive)
        }
        return .running
    }
}

extension EnvironmentValues {
    /// Whether decorative motion in this part of the view tree should animate.
    @Entry public var ambientMotion = AmbientMotionState.running
}
