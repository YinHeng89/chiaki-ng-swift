import ChiakiFeatures
import ChiakiModels
import Video

/// Everything one stream's input reaches: its native player, where its events go, and the app's controller
/// services.
///
/// The player builds the environment over the composition root's ``InputServices`` and hands it to the
/// ``StreamInputSession`` it starts; every input part receives it through its initialiser instead of reaching
/// for a shared instance itself.
@MainActor
struct InputEnvironment {
    /// The native player the stream's input goes to.
    let player: CNLiveVideoPlayer

    /// Where the input reports couch and light events for the session.
    let report: @Sendable (StreamSessionEvent) async -> Void

    /// The connected controllers and their outputs.
    let backend: SDLControllerBackend

    /// The lanes that turn controller events into console states.
    let pipeline: GameInputPipeline

    /// The app-wide controller routing between menus and the stream.
    let coordinator: SDLInputCoordinator

    /// The pad state the on-screen gamepad last published, and the touchpad lent to its views.
    let virtualGamepadLink: VirtualGamepadLink

    /// Sends an action to the on-screen gamepad's feature in the root store.
    let sendVirtualGamepad: @MainActor (VirtualGamepadFeature.Action) -> Void

    /// The lightbar colours shown while no stream owns the controllers.
    let lights: ControllerLights

    /// The microphone light on the controller that owns the microphone button.
    let microphoneLight: MicrophoneLight

    /// Keeps the system from taking the controllers' home and share buttons.
    let systemGestures: ControllerSystemGestureOwner

    #if os(iOS)
        /// The phone's own rumble, used when no controller is connected.
        let phoneRumble: PhoneRumble

        /// The phone's own motion sensors.
        let phoneMotion: PhoneMotion
    #endif

    /// Creates the environment of one stream's input over the app's controller services.
    ///
    /// - Parameters:
    ///   - player: The stream's player.
    ///   - services: The composition root's controller services.
    ///   - report: Where the session's input events go.
    init(
        player: CNLiveVideoPlayer,
        services: InputServices,
        report: @escaping @Sendable (StreamSessionEvent) async -> Void = { _ in
        }
    ) {
        self.player = player
        self.report = report
        backend = services.backend
        pipeline = services.pipeline
        coordinator = services.coordinator
        virtualGamepadLink = services.virtualGamepadLink
        sendVirtualGamepad = services.sendVirtualGamepad
        lights = services.lights
        microphoneLight = services.microphoneLight
        systemGestures = services.systemGestures
        #if os(iOS)
            phoneRumble = services.phoneRumble
            phoneMotion = services.phoneMotion
        #endif
    }

    /// The controllers connected now, or none when the backend cannot list them.
    ///
    /// - Returns: The connected controllers and the keyboard.
    func connectedDevices() -> [ControllerDevice] {
        (try? backend.devices()) ?? []
    }
}
