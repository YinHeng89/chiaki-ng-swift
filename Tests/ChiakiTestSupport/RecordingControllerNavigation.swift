import ChiakiClients
import ChiakiModels
import Foundation

/// A controller navigation that only remembers what views set on it, standing in for the app's input services
/// in hosted-window tests.
@MainActor
public final class RecordingControllerNavigation: ControllerNavigation {
    /// The family reported for the menu controller.
    public var navigationFamily = ControllerFamily.playStation

    /// The button layout reported for the menu controller.
    public var navigationButtonLayout = ButtonLayout.position

    /// Whether a controller is reported as driving menus.
    public var navigationConnected = false

    /// Whether views last handed the controller to the stream menu.
    public var streamNavigationActive = false
    /// Whether a PS button press would hand the controller back to the console while the app has the controller.
    public var systemButtonReachesStream = false

    /// The preferred controller of the last controls applied.
    public private(set) var preferredControllerKey: String?

    /// Every controls configuration views applied, oldest first.
    public private(set) var appliedControls: [ControlsConfiguration] = []

    /// The button capture in progress, with the receiver a test can answer through ``finishCapture(_:)``.
    public private(set) var capture: (id: UUID, receive: (ControllerButtonCaptureState.Outcome) -> Void)?

    /// Creates a navigation with no controller connected.
    public init() {
    }

    /// Records the controls and their preferred controller.
    ///
    /// - Parameter configuration: The controls settings.
    public func applyControls(_ configuration: ControlsConfiguration) {
        appliedControls.append(configuration)
        preferredControllerKey = configuration.selectedControllerKey
    }

    /// Records a new capture, replacing any in progress.
    ///
    /// - Parameters:
    ///   - device: Ignored.
    ///   - receive: Kept for ``finishCapture(_:)``.
    /// - Returns: The capture's token.
    public func beginButtonCapture(
        device: UInt32?,
        receive: @escaping (ControllerButtonCaptureState.Outcome) -> Void
    ) -> UUID {
        let id = UUID()
        capture = (id, receive)
        return id
    }

    /// Forgets the capture if it is the current one.
    ///
    /// - Parameter id: The capture's token.
    public func endButtonCapture(_ id: UUID) {
        guard capture?.id == id else {
            return
        }
        capture = nil
    }

    /// Answers the capture in progress as a controller would.
    ///
    /// - Parameter outcome: The captured button or the cancellation.
    public func finishCapture(_ outcome: ControllerButtonCaptureState.Outcome) {
        guard let capture else {
            return
        }
        self.capture = nil
        capture.receive(outcome)
    }

    /// Reports no recent commands.
    ///
    /// - Parameter seconds: Ignored.
    /// - Returns: `nil`.
    public func recentCommand(within seconds: TimeInterval) -> String? {
        nil
    }
}
