import ChiakiModels
import Foundation

/// Paints the configured lightbar colours on attached controllers while no stream session owns them, and
/// hands colour changes to the live session when one exists.
@MainActor final class ControllerLights {
    private let backend: SDLControllerBackend
    /// The lightbar configuration last shown, or `nil` before any has been applied.
    private(set) var lightbars: ControllerLightbars?
    private var shown: [UInt32: UInt32?] = [:]
    private var devices: [ControllerDevice]?
    private weak var stream: StreamInputSession?

    /// Creates the lights over the app's controller backend.
    ///
    /// - Parameter backend: The backend that paints the controllers.
    init(backend: SDLControllerBackend) {
        self.backend = backend
    }

    /// Applies a new lightbar configuration, reloading the active stream session's lights or repainting idle
    /// controllers.
    /// - Parameter lightbars: The colours to apply; ignored when identical to the current configuration.
    func show(_ lightbars: ControllerLightbars) {
        guard lightbars != self.lightbars else {
            return
        }
        self.lightbars = lightbars
        if let stream {
            stream.reloadLights()
            return
        }
        showIdle()
    }

    /// Forgets the cached controller list and repaints idle controllers after a controller connects or
    /// disconnects.
    func controllersChanged() {
        devices = nil
        showIdle()
    }

    /// Hands the controllers' lights to a stream's input until it ends.
    ///
    /// - Parameter session: The stream's input.
    func streamStarted(_ session: StreamInputSession) {
        stream = session
    }

    /// Takes the controllers' lights back once a stream's input has ended.
    ///
    /// - Parameter session: The stream's input; ignored unless it holds the lights.
    func streamEnded(_ session: StreamInputSession) {
        guard stream === session else {
            return
        }
        stream = nil
        shown = [:]
        showIdle()
    }

    private func showIdle() {
        guard stream == nil, let lightbars else {
            shown = [:]
            return
        }
        let devices = devices ?? ((try? backend.devices()) ?? []).filter { !$0.isKeyboard && $0.lights }
        self.devices = devices.isEmpty
            ? nil
            : devices
        var next: [UInt32: UInt32?] = [:]
        for device in devices {
            let rgb = lightbars.color(for: device, game: nil)
            next[device.id] = rgb
            if let previous = shown[device.id], previous == rgb {
                continue
            }
            if let rgb {
                backend.light(device.id, rgb: rgb)
            } else {
                backend.defaultLight(device.id)
            }
        }
        shown = next
    }
}
