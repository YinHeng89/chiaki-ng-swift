import ChiakiModels
import Dependencies

/// The picture fit a command-line launch asked for, from the launch's preparation until it is restored.
///
/// The launch client writes it and the console launcher reads it when the stream opens; both reach the same
/// instance through ``Dependencies/DependencyValues/launchPresentation``.
@MainActor
public final class LaunchPresentation {
    /// The fit the launch asked for, if any.
    public var videoFit: VideoFit?

    /// Creates an override that asks for nothing.
    public nonisolated init() {}
}

private enum LaunchPresentationKey: DependencyKey {
    static let liveValue = LaunchPresentation()

    static var testValue: LaunchPresentation {
        LaunchPresentation()
    }
}

extension DependencyValues {
    /// The display override of a command-line launch.
    public var launchPresentation: LaunchPresentation {
        get {
            self[LaunchPresentationKey.self]
        }
        set {
            self[LaunchPresentationKey.self] = newValue
        }
    }
}
