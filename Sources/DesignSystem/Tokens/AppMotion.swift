import SwiftUI

/// The durations, animations and transitions shared by screen changes and overlays.
///
/// Each value has a reduced form used when Reduce Motion is on: shorter and without movement.
public enum AppMotion {
    /// The duration of a screen or overlay change.
    ///
    /// - Parameter reduced: Whether Reduce Motion is on.
    /// - Returns: The duration in seconds.
    public static func duration(reduced: Bool) -> Double {
        reduced
            ? 0.12
            : 0.28
    }

    /// The animation for a screen or overlay change.
    ///
    /// - Parameter reduced: Whether Reduce Motion is on.
    /// - Returns: An ease-out when reduced, otherwise a smooth spring.
    public static func animation(reduced: Bool) -> Animation {
        reduced
            ? .easeOut(duration: duration(reduced: true))
            : .smooth(duration: duration(reduced: false), extraBounce: 0)
    }

    /// The transition for content that appears or disappears.
    ///
    /// - Parameter reduced: Whether Reduce Motion is on.
    /// - Returns: A fade when reduced, otherwise a fade with a short vertical slide.
    public static func transition(reduced: Bool) -> AnyTransition {
        reduced
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 12)),
                removal: .opacity.combined(with: .offset(y: -8))
            )
    }
}
