import ChiakiFeatures
import ChiakiModels
import MenuFocus
import PlatformUI

/// Answers the menu navigator's input questions during playback by delegating to the stream's input
/// coordinator, so menus only take controller input when the stream lets them.
@MainActor
final class PlaybackMenuInputPolicy: MenuInputPolicy {
    private let coordinator: SDLInputCoordinator
    private let virtualGamepadLink: VirtualGamepadLink
    private let sendVirtualGamepad: @MainActor (VirtualGamepadFeature.Action) -> Void

    /// Creates a policy backed by the given coordinator.
    /// - Parameters:
    ///   - coordinator: The coordinator that decides whether menus may consume input.
    ///   - virtualGamepadLink: Holds the touchpad the UI test script steps toggle.
    ///   - sendVirtualGamepad: Sends the UI test script steps' presses to the on-screen gamepad's feature.
    init(
        coordinator: SDLInputCoordinator,
        virtualGamepadLink: VirtualGamepadLink,
        sendVirtualGamepad: @escaping @MainActor (VirtualGamepadFeature.Action) -> Void
    ) {
        self.coordinator = coordinator
        self.virtualGamepadLink = virtualGamepadLink
        self.sendVirtualGamepad = sendVirtualGamepad
    }

    /// Whether menus may currently consume controller input rather than the stream.
    var acceptsMenuInput: Bool {
        coordinator.acceptsMenuInput
    }

    /// Reports whether the window hosts the live stream.
    /// - Parameter window: The window to test.
    /// - Returns: `true` when the stream is shown in that window.
    func hostsStream(_ window: PlatformWindow) -> Bool {
        coordinator.hostsStream(window)
    }

    /// Maps a key code to the menu tab command it triggers during playback.
    /// - Parameter keyCode: The hardware key code that was pressed.
    /// - Returns: The tab command, or `nil` when the key does not switch tabs.
    func tabCommand(forKeyCode keyCode: Int) -> MenuCommand? {
        coordinator.menuTabCommand(for: keyCode)
    }

    /// Runs a UI test script step that toggles the virtual touchpad or gamepad, or presses a virtual control,
    /// on iOS.
    /// - Parameter step: The step name, such as `touchpad`, `gamepad` or `press:` followed by a control name.
    /// - Returns: `true` when the step was handled; always `false` on macOS.
    func performScriptStep(_ step: String) -> Bool {
        #if os(iOS)
            if step == "touchpad" {
                virtualGamepadLink.touchpad?.toggle()
                return true
            }
            #if DEBUG
                if step == "gamepad" {
                    sendVirtualGamepad(.previewToggled)
                    return true
                }
            #endif
            if step.hasPrefix("press:"),
               let control = PlayStationControl(rawValue: String(step.dropFirst(6))) {
                sendVirtualGamepad(.pressed(control, down: true))
                return true
            }
        #endif
        return false
    }
}
