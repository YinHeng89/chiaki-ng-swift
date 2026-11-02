import ChiakiDiagnostics
import ChiakiModels
import CInput
import Dependencies
import Foundation
import GameController
import Video

/// Chooses where player one's haptic waveform plays and keeps the player configured for it.
///
/// A DualSense plays haptics over USB audio when wired and over Bluetooth haptic reports when wireless,
/// falling back to Core Haptics; other controllers play them on their rumble motors. A native route the
/// controller is not ready for yet is retried by `HapticRouteRetry`. A wired DualSense also plays PS5 cloud
/// controller speaker sounds on its own speaker when they are wanted.
@MainActor
final class HapticRouter {
    /// Where the haptic waveform currently plays.
    private(set) var route = CNHapticRoute.none

    private let environment: InputEnvironment
    private let rumble: RumbleDriver
    private let consoleHaptics: Bool
    private var waveformDevice: UInt32?
    private var speakerDevice: UInt32?
    private let retry = HapticRouteRetry()

    /// Creates the router.
    ///
    /// - Parameters:
    ///   - environment: The player and controllers it configures.
    ///   - rumble: The rumble that hands over to and from the haptic route.
    ///   - consoleHaptics: Whether the console's haptics should play at all.
    init(environment: InputEnvironment, rumble: RumbleDriver, consoleHaptics: Bool) {
        self.environment = environment
        self.rumble = rumble
        self.consoleHaptics = consoleHaptics
    }

    /// Whether the waveform plays natively rather than on the rumble motors.
    var isNative: Bool {
        Self.isNative(route)
    }

    /// Whether a route plays the waveform natively.
    ///
    /// - Parameter route: The route.
    /// - Returns: `true` for USB audio, Bluetooth reports and Core Haptics.
    nonisolated static func isNative(_ route: CNHapticRoute) -> Bool {
        switch route {
        case .usbAudio, .bluetoothReports, .coreHaptics:
            true
        case .none, .rumble:
            false
        @unknown default:
            false
        }
    }

    /// The native route a controller should use.
    ///
    /// - Parameter device: The controller.
    /// - Returns: USB audio for a wired DualSense, Bluetooth reports for one that can play the waveform,
    ///   otherwise Core Haptics.
    nonisolated static func preferredRoute(for device: ControllerDevice) -> CNHapticRoute {
        #if os(iOS)
            return .coreHaptics
        #else
            if device.transport == "USB" {
                return .usbAudio
            }
            return device.waveform
                ? .bluetoothReports
                : .coreHaptics
        #endif
    }

    /// How a route reads in the log.
    ///
    /// - Parameter route: The route.
    /// - Returns: A short description.
    nonisolated static func describe(_ route: CNHapticRoute) -> String {
        switch route {
        case .usbAudio:
            "USB audio"
        case .bluetoothReports:
            "Bluetooth haptic reports"
        case .coreHaptics:
            "Core Haptics"
        case .rumble:
            "the rumble motors"
        case .none:
            "nothing"
        @unknown default:
            "an unknown route"
        }
    }

    private static var coreHapticsAvailable: Bool {
        GCController.controllers().contains { controller in
            guard controller.productCategory.hasPrefix("DualSense"),
                  let localities = controller.haptics?.supportedLocalities else {
                return false
            }
            return localities.contains(.leftHandle) && localities.contains(.rightHandle)
        }
    }

    private nonisolated static func waveformReports(for id: UInt32) -> (UnsafePointer<UInt8>, Float) -> Bool {
        { pcm, gain in
            nx_input_waveform(id, pcm, 256, gain)
        }
    }

    /// Stops every haptic output on player one's controller and forgets the route.
    ///
    /// - Parameters:
    ///   - device: Player one's controller.
    ///   - preferences: Its preferences.
    func clear(device: ControllerDevice?, preferences: ControllerPreferences) {
        retry.cancel()
        environment.player.configureControllerFeedbackDevice(0, route: .none, hapticGain: 0, reports: nil)
        if let device {
            if isNative || preferences.adaptiveTriggersEnabled {
                environment.backend.resetFeedback(device.id)
            } else {
                environment.backend.rumble(device.id, level: .off)
            }
        }
        route = .none
        rumble.silence()
    }

    /// Plays player one's haptics where its preferences ask.
    ///
    /// - Parameters:
    ///   - device: Player one's controller, or `nil` when none plays.
    ///   - preferences: Its preferences.
    ///   - hasInput: Whether the stream has input.
    ///   - isCurrent: Whether a controller is still player one when a retry fires.
    ///   - reconfigure: Configures again when a retry fires.
    func configure(
        device: ControllerDevice?,
        preferences: ControllerPreferences,
        hasInput: Bool,
        isCurrent: @escaping @MainActor (UInt32) -> Bool,
        reconfigure: @escaping @MainActor () -> Void
    ) {
        let timing = SlowStep("setting up haptics")
        defer {
            timing.finish()
        }
        guard hasInput, let device else {
            retry.cancel()
            apply(environment.player.configureControllerFeedbackDevice(
                0,
                route: .none,
                hapticGain: 0,
                reports: nil
            ), device: device, preferences: preferences)
            return
        }
        let output = consoleHaptics
            ? preferences.hapticOutput(for: device)
            : .none
        let gain = preferences.hapticStrength
        let preferred: CNHapticRoute
        var active: CNHapticRoute
        switch output {
        case .none:
            preferred = .none
            active = environment.player.configureControllerFeedbackDevice(
                0,
                route: .none,
                hapticGain: 0,
                reports: nil
            )
        case .rumble:
            preferred = .rumble
            active = environment.player.configureControllerFeedbackDevice(
                device.id, route: .rumble, hapticGain: Float(gain), reports: nil
            )
        case .native:
            preferred = Self.preferredRoute(for: device)
            active = configureNative(device, preferred: preferred, gain: gain)
        }
        apply(active, device: device, preferences: preferences)
        if output == .native {
            retry.schedule(
                requested: preferred,
                active: active,
                device: device.id,
                isCurrent: isCurrent,
                reconfigure: reconfigure
            )
        } else {
            retry.cancel()
        }
        log(device: device, active: active, preferred: preferred, gain: gain)
    }

    private func log(device: ControllerDevice, active: CNHapticRoute, preferred: CNHapticRoute,
                     gain: Double) {
        var message = "haptics for \"\(device.name)\" play over \(Self.describe(active)) "
            + "(requested \(Self.describe(preferred)), device \(device.id), gain "
            + String(format: "%.2f", gain) + ")"
        if preferred == .usbAudio {
            let values = environment.player.controllerFeedbackDiagnostics()
            message += "; USB audio opened \(values["usbAudioOpened"] ?? 0), failed \(values["usbAudioFailed"] ?? 0), "
                + "not ready yet \(values["usbAudioNotReady"] ?? 0)"
        }
        @Dependency(\.logger) var logger
        logger.enqueue(.controllerDiagnostic(message))
    }

    /// Changes how strongly the waveform plays without changing its route.
    ///
    /// - Parameter strength: The haptic strength.
    func setGain(_ strength: Double) {
        environment.player.setControllerHapticGain(Float(strength))
    }

    /// Takes the controller out of Bluetooth waveform mode and switches its speaker off when the stream ends.
    func releaseWaveform() {
        if let waveformDevice {
            _ = nx_input_waveform_mode(waveformDevice, false)
            self.waveformDevice = nil
        }
        routeSpeaker(to: nil)
    }

    private func configureNative(_ device: ControllerDevice, preferred: CNHapticRoute,
                                 gain: Double) -> CNHapticRoute {
        if let waveformDevice, waveformDevice != device.id {
            _ = nx_input_waveform_mode(waveformDevice, false)
            self.waveformDevice = nil
        }
        let waveform = preferred == .bluetoothReports && nx_input_waveform_mode(device.id, true)
        if waveform {
            waveformDevice = device.id
        }
        let next: CNHapticRoute = preferred == .bluetoothReports && !waveform
            ? .coreHaptics
            : preferred
        if route == .rumble, next == .coreHaptics, !Self.coreHapticsAvailable {
            return .rumble
        }
        let active = environment.player.configureControllerFeedbackDevice(
            device.id, route: next, hapticGain: Float(gain),
            reports: next == .bluetoothReports
                ? Self.waveformReports(for: device.id)
                : nil
        )
        guard active == .none, device.rumble else {
            return active
        }
        return environment.player.configureControllerFeedbackDevice(
            device.id, route: .rumble, hapticGain: Float(gain), reports: nil
        )
    }

    private func apply(_ next: CNHapticRoute, device: ControllerDevice?, preferences: ControllerPreferences) {
        if route == .bluetoothReports, next != .bluetoothReports, let waveformDevice {
            _ = nx_input_waveform_mode(waveformDevice, false)
            self.waveformDevice = nil
        }
        if route == .rumble, next != .rumble {
            rumble.hapticsLeftMotors(device: device)
        }
        if next == .usbAudio, route != .usbAudio, let device, device.nativeHaptics {
            rumble.quietForUSBAudio(device: device, preferences: preferences)
        }
        route = next
        rumble.resetHandoff()
        routeSpeaker(to: next == .usbAudio && environment.player.controllerSpeakerWired
            ? device?.id
            : nil)
    }

    private func routeSpeaker(to wanted: UInt32?) {
        guard wanted != speakerDevice else {
            return
        }
        if let speakerDevice {
            environment.backend.controllerSpeaker(speakerDevice, enabled: false)
        }
        if let wanted {
            environment.backend.controllerSpeaker(wanted, enabled: true)
        }
        speakerDevice = wanted
    }

    /// Retries a native haptic route the controller was not ready for, with a growing delay, while the same
    /// controller stays player one.
    ///
    /// A route that keeps failing gives up once every delay in ``retryDelays`` has been tried; a retry for one
    /// controller never fires for another.
    @MainActor
    private final class HapticRouteRetry {
        private enum Wait {
            case idle
            case waiting(device: UInt32, attempt: Int, retry: Task<Void, Never>)
            case retrying(device: UInt32, attempt: Int)
        }

        /// The delays between retries of a native route the controller refused.
        static let retryDelays: [Duration] = [
            .milliseconds(500), .seconds(1), .seconds(1), .seconds(2), .seconds(2), .seconds(4), .seconds(4)
        ]

        private var wait = Wait.idle

        /// Cancels a pending retry.
        func cancel() {
            if case let .waiting(_, _, retry) = wait {
                retry.cancel()
            }
            wait = .idle
        }

        /// Schedules a retry when the route that opened is not the one requested.
        ///
        /// - Parameters:
        ///   - requested: The route asked for.
        ///   - active: The route that opened.
        ///   - device: The controller.
        ///   - isCurrent: Whether a controller is still player one when the retry fires.
        ///   - reconfigure: Configures the route again when the retry fires.
        func schedule(
            requested: CNHapticRoute,
            active: CNHapticRoute,
            device: UInt32,
            isCurrent: @escaping @MainActor (UInt32) -> Bool,
            reconfigure: @escaping @MainActor () -> Void
        ) {
            guard requested != .none, active != requested else {
                cancel()
                return
            }
            let attempt: Int
            switch wait {
            case let .retrying(retried, previous) where retried == device:
                attempt = previous + 1
            case let .waiting(waiting, _, _) where waiting == device:
                return
            case .idle, .waiting, .retrying:
                attempt = 0
            }
            cancel()
            guard attempt < Self.retryDelays.count else {
                return
            }
            let delay = Self.retryDelays[attempt]
            let retry = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self,
                      case .waiting(device: device, attempt: attempt, retry: _) = self.wait,
                      isCurrent(device) else {
                    return
                }
                self.wait = .retrying(device: device, attempt: attempt)
                reconfigure()
            }
            wait = .waiting(device: device, attempt: attempt, retry: retry)
        }
    }
}
