import MenuFocus
import PlatformUI

/// A `MenuInputPolicy` for tests: menus always accept input, no window hosts a stream and no key is bound.
@MainActor
public final class StandaloneMenuInputPolicy: MenuInputPolicy {
    /// Windows the test pretends are showing a stream.
    public var streamWindows = Set<ObjectIdentifier>()

    /// Creates the policy.
    public init() {
    }

    /// Always `true`.
    public var acceptsMenuInput: Bool {
        true
    }

    /// Whether the test marked the window as showing a stream.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: `true` for windows in ``streamWindows``.
    public func hostsStream(_ window: PlatformWindow) -> Bool {
        streamWindows.contains(ObjectIdentifier(window))
    }

    /// Always `nil`.
    ///
    /// - Parameter keyCode: The key code.
    /// - Returns: `nil`.
    public func tabCommand(forKeyCode keyCode: Int) -> MenuCommand? {
        nil
    }

    /// Handles no script steps.
    ///
    /// - Parameter step: The step.
    /// - Returns: `false`.
    public func performScriptStep(_ step: String) -> Bool {
        false
    }
}
