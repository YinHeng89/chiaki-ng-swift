import CInput
import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels

/// Fuses one controller's accelerometer and gyroscope samples into motion the console understands.
final class ControllerMotionTracker {
    private var fusion = ControllerMotionFusion()

    /// Creates an empty tracker.
    init() {}

    /// The fused motion, or `nil` until the tracker has enough samples.
    var motion: ControllerMotion? {
        fusion.motion
    }

    /// Feeds a sensor event; other events are ignored.
    ///
    /// - Parameter event: A controller event.
    func accept(_ event: nx_input_event) {
        guard ControllerInputEvent.isSensor(event) else {
            return
        }
        let sample = SIMD3(event.data.0, event.data.1, event.data.2)
        switch event.control {
        case Int32(NX_INPUT_SENSOR_ACCEL):
            fusion.accelerometer(sample, at: event.timestamp_us)
        case Int32(NX_INPUT_SENSOR_GYRO):
            fusion.gyroscope(sample, at: event.timestamp_us)
        default:
            break
        }
    }

    /// Feeds one device motion sample.
    ///
    /// - Parameters:
    ///   - gyro: Angular velocity.
    ///   - accel: Acceleration.
    ///   - timestamp: When the sample was taken, in microseconds.
    func feed(gyro: SIMD3<Float>, accel: SIMD3<Float>, at timestamp: UInt64) {
        fusion.accelerometer(accel, at: timestamp)
        fusion.gyroscope(gyro, at: timestamp)
    }

    /// Forgets the fused orientation.
    func reset() {
        fusion.recentre()
    }

    /// Applies the processing the console asked for.
    ///
    /// - Parameter processing: The processing.
    func configure(_ processing: ControllerMotionProcessing) {
        fusion.tune(
            tiltCorrection: processing.tiltCorrection,
            angularVelocityDeadband: processing.angularVelocityDeadband
        )
    }
}

/// How the console wants controller motion processed before it is sent.
struct ControllerMotionProcessing: Equatable {
    /// Tilt correction and the angular velocity deadband both on.
    static let standard = ControllerMotionProcessing(tiltCorrection: true, angularVelocityDeadband: true)

    /// Whether tilt is corrected against gravity.
    var tiltCorrection: Bool

    /// Whether small angular velocities are ignored.
    var angularVelocityDeadband: Bool

    /// Creates the processing.
    ///
    /// - Parameters:
    ///   - tiltCorrection: Whether tilt is corrected.
    ///   - angularVelocityDeadband: Whether the deadband is applied.
    init(tiltCorrection: Bool, angularVelocityDeadband: Bool) {
        self.tiltCorrection = tiltCorrection
        self.angularVelocityDeadband = angularVelocityDeadband
    }

    /// Decodes the processing the player took from the console.
    ///
    /// - Parameter value: The player's value; negative when the console sent nothing new.
    init?(taken value: Int) {
        guard value >= 0 else {
            return nil
        }
        tiltCorrection = value & 2 != 0
        angularVelocityDeadband = value & 1 != 0
    }
}
