import ChiakiModels
import Foundation

/// The controller that drives menu navigation, as the interface sees it.
///
/// Prompts read its family, button layout and connection to pick glyphs, the stream overlays hand it to and
/// take it back from the stream menu, and the controls settings capture its buttons for bindings. The app's
/// input services conform over the controller layer, so features never touch that layer themselves.
@MainActor
public protocol ControllerNavigation: AnyObject, Sendable {
    /// The family of the controller driving menus, which picks button glyphs.
    var navigationFamily: ControllerFamily { get }

    /// Whether the menu controller's face buttons follow their position or their printed labels.
    var navigationButtonLayout: ButtonLayout { get }

    /// Whether any controller currently drives menus.
    var navigationConnected: Bool { get }

    /// Whether the stream menu has the controller instead of the stream.
    var streamNavigationActive: Bool { get set }

    /// Whether a PS button press hands the controller back to the console, press included, while the app has
    /// the controller, as while the hidden-screen notice's Home button holds it.
    var systemButtonReachesStream: Bool { get set }

    /// The preference key of the controller the user picked for menus, or the keyboard-only key.
    var preferredControllerKey: String? { get }

    /// Applies the saved controls settings to menu navigation and to the playing stream's input.
    ///
    /// - Parameter configuration: The controls settings.
    func applyControls(_ configuration: ControlsConfiguration)

    /// Starts capturing the next button press for a binding, replacing any capture in progress.
    ///
    /// - Parameters:
    ///   - device: The controller to listen to, or `nil` for the menu controller.
    ///   - receive: Called with the captured button, or when the capture is cancelled by a long hold.
    /// - Returns: The token that ends this capture with ``endButtonCapture(_:)``.
    func beginButtonCapture(
        device: UInt32?,
        receive: @escaping (ControllerButtonCaptureState.Outcome) -> Void
    ) -> UUID

    /// Ends a button capture if it is still the current one.
    ///
    /// - Parameter id: The token ``beginButtonCapture(device:receive:)`` returned.
    func endButtonCapture(_ id: UUID)

    /// Describes the menu commands a controller sent recently, for tracing why a stream stopped.
    ///
    /// - Parameter seconds: How far back to look.
    /// - Returns: The controller and its commands, or `nil` when none arrived in that time.
    func recentCommand(within seconds: TimeInterval) -> String?
}
