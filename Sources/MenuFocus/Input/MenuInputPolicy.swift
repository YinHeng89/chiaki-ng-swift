import PlatformUI

/// The questions the focus engine asks the app's input layer.
///
/// MenuFocus knows nothing about streams or the controller hardware. The app implements this protocol on
/// top of its input coordinator and hands it to the navigator at the composition root.
@MainActor
public protocol MenuInputPolicy: AnyObject {
    /// Whether controller commands currently drive menus rather than a stream.
    var acceptsMenuInput: Bool { get }

    /// Whether a window is showing a stream, where pointer and keyboard input belong to the game.
    ///
    /// - Parameter window: The window to check.
    /// - Returns: `true` while `window` hosts a stream.
    func hostsStream(_ window: PlatformWindow) -> Bool

    /// The tab command a hardware key is bound to in menus, such as the keys mapped to L1 and R1.
    ///
    /// - Parameter keyCode: The virtual key code of the pressed key.
    /// - Returns: The command to perform, or `nil` when the key has no menu binding.
    func tabCommand(forKeyCode keyCode: Int) -> MenuCommand?

    /// Runs one step of a scripted navigation session that the engine does not understand itself, such as
    /// pressing a virtual gamepad button. Used by debug navigation scripts on iOS.
    ///
    /// - Parameter step: The script step.
    /// - Returns: Whether the policy handled the step.
    func performScriptStep(_ step: String) -> Bool
}

/// Where the focus engine sends its diagnostic messages.
///
/// The app routes them into its own log; tests usually pass ``silent``.
public struct MenuFocusDiagnostics: Sendable {
    private let sink: @Sendable (String) -> Void

    /// Creates diagnostics that forward to a sink.
    ///
    /// - Parameter sink: Receives each message.
    public init(_ sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    /// Diagnostics that drop every message.
    public static let silent = MenuFocusDiagnostics { _ in
    }

    /// Records a message.
    ///
    /// - Parameter message: A short description of what the engine did and why.
    public func log(_ message: String) {
        sink(message)
    }
}
