import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels

/// The vibration and trigger strength the console asked for.
struct ConsoleFeedbackIntensity: Equatable {
    /// The console's vibration intensity byte.
    var haptic: UInt8 = 1

    /// The console's trigger effect intensity byte.
    var trigger: UInt8 = 1

    /// How much to scale rumble in software for a controller.
    ///
    /// - Parameter device: The controller.
    /// - Returns: `1` for controllers that apply the console's intensity themselves, otherwise the scale the
    ///   intensity byte stands for.
    func softwareScale(for device: ControllerDevice) -> Double {
        device.nativeHaptics
            ? 1
            : Double(chiaki_bridge.ConsoleFeedback.scale_of(haptic))
    }

    /// The intensity with its trigger level no stronger than a controller's trigger strength.
    ///
    /// - Parameter strength: The controller's trigger strength.
    /// - Returns: The limited intensity.
    func limited(by strength: TriggerStrength) -> ConsoleFeedbackIntensity {
        var limited = self
        limited.trigger = strength.applied(toConsoleLevel: trigger)
        return limited
    }
}
