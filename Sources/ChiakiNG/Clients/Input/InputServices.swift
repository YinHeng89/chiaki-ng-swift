import ChiakiClients
import ChiakiClientsLive
import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import Foundation
import MenuFocus

/// The app's controller services, built once by the composition root.
///
/// Every stream's input receives them through ``InputEnvironment``, the menu navigator answers its input
/// questions through them, and views see them only as `ChiakiClients/ControllerNavigation`.
@MainActor
final class InputServices: ControllerNavigation {
    /// The connected controllers and their outputs.
    let backend: SDLControllerBackend

    /// The lanes that turn controller events into console states.
    let pipeline: GameInputPipeline

    /// The lightbar colours shown while no stream owns the controllers.
    let lights: ControllerLights

    /// The app-wide controller routing between menus and the stream.
    let coordinator: SDLInputCoordinator

    /// The pad state the on-screen gamepad last published, and the touchpad lent to its views.
    let virtualGamepadLink: VirtualGamepadLink

    /// Sends an action to the on-screen gamepad's feature in the root store.
    let sendVirtualGamepad: @MainActor (VirtualGamepadFeature.Action) -> Void

    /// The microphone light on the controller that owns the microphone button.
    let microphoneLight: MicrophoneLight

    /// Keeps the system from taking the controllers' home and share buttons.
    let systemGestures: ControllerSystemGestureOwner

    /// The menu navigator that drives controller and keyboard focus in every window.
    let menuNavigator: PlatformMenuNavigator

    #if os(iOS)
        /// The phone's own rumble, used when no controller is connected.
        let phoneRumble: PhoneRumble

        /// The phone's own motion sensors.
        let phoneMotion: PhoneMotion
    #endif

    private let leases: StreamLeases

    /// Builds every controller service and the menu navigator over them.
    ///
    /// - Parameters:
    ///   - leases: The stream lease, whose playing stream's input takes new controls settings.
    ///   - sendVirtualGamepad: Sends an action to the on-screen gamepad's feature in the root store.
    init(
        leases: StreamLeases,
        sendVirtualGamepad: @escaping @MainActor (VirtualGamepadFeature.Action) -> Void
    ) {
        self.leases = leases
        let backend = SDLControllerBackend()
        let pipeline = GameInputPipeline()
        let lights = ControllerLights(backend: backend)
        let coordinator = SDLInputCoordinator(backend: backend, pipeline: pipeline, lights: lights)
        let virtualGamepadLink = VirtualGamepadLink()
        let navigator = PlatformMenuNavigator(
            policy: PlaybackMenuInputPolicy(
                coordinator: coordinator,
                virtualGamepadLink: virtualGamepadLink,
                sendVirtualGamepad: sendVirtualGamepad
            ),
            diagnostics: MenuFocusDiagnostics { message in
                @Dependency(\.logger) var logger
                logger.enqueue(.diagnostic(.controller, .debug, message))
            }
        )
        navigator.focusFallback = { window in
            NotificationCenter.default.post(name: .focusLibraryContent, object: window)
        }
        coordinator.menuNavigator = navigator
        self.backend = backend
        self.pipeline = pipeline
        self.lights = lights
        self.coordinator = coordinator
        self.virtualGamepadLink = virtualGamepadLink
        self.sendVirtualGamepad = sendVirtualGamepad
        microphoneLight = MicrophoneLight(backend: backend)
        systemGestures = ControllerSystemGestureOwner()
        menuNavigator = navigator
        #if os(iOS)
            phoneRumble = PhoneRumble()
            phoneMotion = PhoneMotion(pipeline: pipeline)
        #endif
    }

    /// Starts polling controllers and the menu navigator.
    func start() {
        coordinator.start()
    }

    /// Stops polling controllers and shuts the controller layer down.
    func stop() {
        coordinator.stop()
        backend.shutdown()
    }

    /// The family of the controller driving menus.
    var navigationFamily: ControllerFamily {
        coordinator.navigationFamily
    }

    /// Whether the menu controller's face buttons follow their position or their printed labels.
    var navigationButtonLayout: ButtonLayout {
        coordinator.navigationButtonLayout
    }

    /// Whether any controller currently drives menus.
    var navigationConnected: Bool {
        coordinator.navigationConnected
    }

    /// Whether the stream menu has the controller instead of the stream.
    var streamNavigationActive: Bool {
        get {
            coordinator.streamNavigationActive
        }
        set {
            coordinator.streamNavigationActive = newValue
        }
    }

    /// Whether a PS button press hands the controller back to the console, press included, while the app has
    /// the controller.
    var systemButtonReachesStream: Bool {
        get {
            coordinator.systemButtonReachesStream
        }
        set {
            coordinator.systemButtonReachesStream = newValue
        }
    }

    /// The preference key of the controller the user picked for menus.
    var preferredControllerKey: String? {
        coordinator.preferredControllerKey
    }

    /// Hands the controls settings to menu navigation and to the playing stream's input.
    ///
    /// - Parameter configuration: The controls settings.
    func applyControls(_ configuration: ControlsConfiguration) {
        coordinator.preferredControllerKey = configuration.selectedControllerKey
        coordinator.controlsConfiguration = configuration
        NativeStreamPlayer.attachedInput(in: leases)?.reload(configuration: configuration)
    }

    /// Starts capturing the next button press for a binding.
    ///
    /// - Parameters:
    ///   - device: The controller to listen to, or `nil` for the menu controller.
    ///   - receive: Called with the captured button or the cancellation.
    /// - Returns: The capture's token.
    func beginButtonCapture(
        device: UInt32?,
        receive: @escaping (ControllerButtonCaptureState.Outcome) -> Void
    ) -> UUID {
        coordinator.beginButtonCapture(device: device, receive: receive)
    }

    /// Ends a button capture if it is still the current one.
    ///
    /// - Parameter id: The capture's token.
    func endButtonCapture(_ id: UUID) {
        coordinator.endButtonCapture(id)
    }

    /// Describes the menu commands a controller sent recently.
    ///
    /// - Parameter seconds: How far back to look.
    /// - Returns: The description, or `nil` when none arrived.
    func recentCommand(within seconds: TimeInterval) -> String? {
        coordinator.recentCommand(within: seconds)
    }
}
