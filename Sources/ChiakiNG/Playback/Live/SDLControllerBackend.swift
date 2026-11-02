import ChiakiClients
import ChiakiModels
import ChiakiDiagnostics
import Foundation
import CryptoKit
import CInput

/// Extends the controllers client with its native implementation.
extension ControllersClient {
    /// The controllers client backed by the SDL input layer.
    ///
    /// - Parameters:
    ///   - backend: The app's controller backend.
    ///   - lights: The lightbar colours shown on the connected controllers.
    /// - Returns: The live client.
    static func native(_ backend: SDLControllerBackend, lights: ControllerLights) -> Self {
        Self(
            devices: {
                try await backend.devices()
            },
            testRumble: { id, strength in
                try await backend.testRumble(id, strength: strength)
            },
            showLights: { lightbars in
                lights.show(lightbars)
            }
        )
    }
}
/// Wraps the native SDL input layer for listing controllers and driving their rumble, lights, motion sensors,
/// touchpads and adaptive triggers.
///
/// The rumble, HD Rumble and trigger calls only queue commands for the input layer's own thread, so they are
/// nonisolated and the real-time input clock calls them directly.
@MainActor final class SDLControllerBackend {
    private static let eventCapacity = 256
    private static let fingerCapacity = 8
    private var eventBuffer = [nx_input_event](repeating: nx_input_event(), count: eventCapacity)
    private var fingerBuffer = [nx_input_event](repeating: nx_input_event(), count: fingerCapacity)
    /// Shuts down the SDL input layer.
    func shutdown() {
        nx_input_quit()
    }
    /// Lists the connected controllers with their capabilities and a preference key that identifies a unit by
    /// serial or, when it has none, a model by GUID.
    /// - Returns: The connected controllers.
    /// - Throws: `InputFailure.unavailable` when the input layer cannot enumerate devices.
    func devices() throws -> [ControllerDevice] {
        let timing = SlowStep("listing controllers")
        defer {
            timing.finish()
        }
        var devices = [nx_input_device](repeating: nx_input_device(), count: 32)
        let count = nx_input_devices(&devices, Int32(devices.count))
        guard count >= 0 else {
            throw InputFailure.unavailable
        }
        return devices.prefix(Int(count)).map { device in
            let serial = Self.canonicalSerial(string(device.serial))
            let identity = "\(device.vendor):\(device.product):\(serial)"
            let key = serial.isEmpty
                ? "model:" + string(device.guid)
                : "unit:" + Self.identityHash(identity)
            let transport: String
            switch device.connection {
            case 1:
                transport = "USB"
            case 2:
                transport = "Wireless"
            default:
                transport = "Unknown connection"
            }
            return ControllerDevice(id: device.instance, preferenceKey: key, name: string(device.name),
                                    transport: transport, individual: !serial.isEmpty, rumble: device.rumble,
                                    lights: device.rgb, motion: device.gyro, touchpad: device.touchpad,
                                    waveform: device.waveform, adaptiveTriggers: device.triggers,
                                    family: ControllerFamily(rawValue: Int(device.family)) ?? .generic,
                                    hdRumble: device.hd_rumble)
        }
    }
    /// Normalises a Bluetooth address style serial to lowercase hyphen-separated pairs so the same controller
    /// matches across connections.
    /// - Parameter serial: The serial reported by SDL.
    /// - Returns: The canonical serial, or the input unchanged when it is not a six-pair address.
    nonisolated static func canonicalSerial(_ serial: String) -> String {
        let pairs = serial.split(separator: ":", omittingEmptySubsequences: false)
        guard pairs.count == 6, pairs.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else {
            return serial
        }
        return pairs.map { $0.lowercased() }.joined(separator: "-")
    }
    /// Hashes a controller's vendor, product and serial so its preference key does not reveal the serial.
    /// - Parameter identity: The `vendor:product:serial` text.
    /// - Returns: The SHA-256 of the identity as lowercase hex.
    nonisolated static func identityHash(_ identity: String) -> String {
        Hex.encode(SHA256.hash(data: Data(identity.utf8)))
    }
    /// Rumbles a controller at full level for 250 ms so the user can feel the chosen strength.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - strength: The rumble strength setting from 0 to 1.
    /// - Throws: `InputFailure.unavailable` when the controller cannot rumble.
    func testRumble(_ id: UInt32, strength: Double) async throws {
        let level = RumbleLevel(left: 255, right: 255, strength: strength)
        let byte = UInt8(level.low >> 8)
        if nx_input_dualsense_rumble(id, byte, byte, 1, 1) {
            try? await Task.sleep(for: .milliseconds(250))
            _ = nx_input_dualsense_rumble(id, 0, 0, 1, 1)
            return
        }
        guard rumble(id, level: level, duration: 250) else {
            throw InputFailure.unavailable
        }
    }
    /// Plays a rumble level, using DualSense native haptics with the console's trigger and haptic intensities
    /// when the controller supports them.
    /// - Parameters:
    ///   - device: The controller to rumble.
    ///   - level: The low and high frequency motor levels.
    ///   - console: The console's feedback intensity settings.
    /// - Returns: `true` when the controller accepted the rumble.
    @discardableResult nonisolated func rumble(_ device: ControllerDevice, level: RumbleLevel,
                                               console: ConsoleFeedbackIntensity) -> Bool {
        guard device.nativeHaptics else {
            return rumble(device.id, level: level)
        }
        return nx_input_dualsense_rumble(
            device.id, UInt8(level.low >> 8), UInt8(level.high >> 8), console.trigger, console.haptic
        )
    }
    /// Plays a rumble level through SDL for the given duration.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - level: The low and high frequency motor levels.
    ///   - duration: How long the rumble lasts in milliseconds.
    /// - Returns: `true` when the controller accepted the rumble.
    @discardableResult nonisolated func rumble(_ id: UInt32, level: RumbleLevel,
                                               duration: UInt32 = RumbleMix.durationMilliseconds) -> Bool {
        nx_input_rumble(id, level.low, level.high, duration)
    }
    /// Plays an HD Rumble tone on a Nintendo Switch controller.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - tone: The left and right amplitudes to play.
    /// - Returns: `true` when the controller accepted the tone.
    @discardableResult nonisolated func hdRumble(_ id: UInt32, tone: HDRumbleTone) -> Bool {
        let amplitude = [tone.left, tone.right]
        return nx_input_switch_rumble(id, amplitude)
    }
    /// Turns a controller's gyroscope and accelerometer reports on or off.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - enabled: Whether motion sensors should report.
    func setMotion(_ id: UInt32, enabled: Bool) {
        _ = nx_input_motion(id, enabled)
    }
    /// Returns the current touchpad finger events for a controller, up to eight, reading them through a buffer
    /// the backend keeps so an untouched touchpad allocates nothing.
    /// - Parameter id: The SDL instance id of the controller.
    /// - Returns: One event per reported finger.
    func touchFingers(_ id: UInt32) -> [nx_input_event] {
        let count = Int(max(0, nx_input_touch_fingers(id, &fingerBuffer, Int32(Self.fingerCapacity))))
        guard count > 0 else {
            return []
        }
        return Array(fingerBuffer.prefix(count))
    }
    /// Turns a controller's microphone mute light on or off.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - lit: Whether the light should be on.
    func microphoneLight(_ id: UInt32, lit: Bool) {
        _ = nx_input_mic_light(id, lit)
    }
    /// Switches a DualSense's built-in speaker on at a fixed volume, or back off.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - enabled: Whether the speaker should play.
    func controllerSpeaker(_ id: UInt32, enabled: Bool) {
        _ = nx_input_dualsense_speaker(id, enabled)
    }
    /// Clears any rumble and trigger feedback the controller is playing.
    /// - Parameter id: The SDL instance id of the controller.
    func resetFeedback(_ id: UInt32) {
        nx_input_reset_feedback(id)
    }
    /// Sets a controller's lightbar colour.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - rgb: The colour packed as `0xRRGGBB`.
    func light(_ id: UInt32, rgb: UInt32) {
        _ = nx_input_light(id, rgb)
    }
    /// Sets the player number a controller shows on its player indicator.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - index: The zero-based player index.
    func player(_ id: UInt32, index: Int) {
        _ = nx_input_player(id, Int32(index))
    }
    /// Returns the player number SDL has assigned to a controller.
    /// - Parameter id: The SDL instance id of the controller.
    /// - Returns: The zero-based player index, or a negative value when none is assigned.
    func playerIndex(_ id: UInt32) -> Int {
        Int(nx_input_player_index(id))
    }
    /// Restores a controller's lightbar to its system default colour.
    /// - Parameter id: The SDL instance id of the controller.
    func defaultLight(_ id: UInt32) {
        _ = nx_input_default_light(id)
    }
    /// Applies the adaptive trigger effects from a console DualSense feedback packet, turning effects off when
    /// the console asks for none.
    /// - Parameters:
    ///   - id: The SDL instance id of the controller.
    ///   - packet: The 279-byte extended feedback packet from the console; other sizes are ignored.
    ///   - preferences: The controller preferences that decide whether adaptive triggers are enabled.
    /// - Returns: The 22 trigger effect bytes the console sent, for logging mode changes, or `nil` when the
    ///   packet carries no trigger effects.
    nonisolated func extendedFeedback(
        _ id: UInt32,
        packet: Data,
        preferences: ControllerPreferences
    ) -> [UInt8]? {
        guard packet.count == 279 else {
            return nil
        }
        return packet.withUnsafeBytes { raw -> [UInt8]? in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes[0] & 2 != 0 else {
                return nil
            }
            let console = Array(bytes[257..<279])
            if preferences.adaptiveTriggersEnabled {
                var effects = console
                if (bytes[0] >> 4) & 3 == 0 {
                    effects = [UInt8](repeating: 0, count: 22)
                    effects[0] = 5
                    effects[11] = 5
                }
                let level = preferences.triggerStrength.applied(toConsoleLevel: (bytes[0] >> 4) & 3)
                _ = nx_input_triggers(id, &effects, level, (bytes[0] >> 2) & 3)
            }
            return console
        }
    }
    /// Drains up to 256 pending controller events from the SDL input layer into a caller-owned buffer, reading
    /// them through a buffer the backend keeps so a poll allocates nothing once both have grown.
    /// - Parameter events: Replaced with the events in arrival order; its capacity is kept.
    func readEvents(into events: inout [nx_input_event]) {
        let timing = SlowStep("reading controller events")
        defer {
            timing.finish()
        }
        events.removeAll(keepingCapacity: true)
        let count = Int(max(0, nx_input_events(&eventBuffer, Int32(Self.eventCapacity))))
        events.append(contentsOf: eventBuffer.prefix(count))
    }
    private func string<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }
}
