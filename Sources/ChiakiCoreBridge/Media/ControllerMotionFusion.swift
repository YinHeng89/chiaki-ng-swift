import ChiakiBridge
import ChiakiModels

/// Fuses one controller's accelerometer and gyroscope samples into the motion the console understands.
///
/// The core's motion tracker does the fusion; this value only feeds it and reads the result.
public struct ControllerMotionFusion {
    private var fusion = chiaki_bridge.MotionFusion()

    /// Creates an empty fusion.
    public init() {}

    /// The fused motion, or `nil` until enough samples arrived.
    public var motion: ControllerMotion? {
        guard let read = fusion.read().value else {
            return nil
        }
        return ControllerMotion(
            gyro: SIMD3(read.gyro_x, read.gyro_y, read.gyro_z),
            accel: SIMD3(read.accel_x, read.accel_y, read.accel_z),
            orientation: SIMD4(read.orient_x, read.orient_y, read.orient_z, read.orient_w)
        )
    }

    /// Feeds an accelerometer sample.
    ///
    /// - Parameters:
    ///   - sample: The acceleration.
    ///   - timestamp: When it was taken, in microseconds.
    public mutating func accelerometer(_ sample: SIMD3<Float>, at timestamp: UInt64) {
        fusion.accelerometer(sample.x, sample.y, sample.z, timestamp)
    }

    /// Feeds a gyroscope sample.
    ///
    /// - Parameters:
    ///   - sample: The angular velocity.
    ///   - timestamp: When it was taken, in microseconds.
    public mutating func gyroscope(_ sample: SIMD3<Float>, at timestamp: UInt64) {
        fusion.gyroscope(sample.x, sample.y, sample.z, timestamp)
    }

    /// Forgets the fused orientation.
    public mutating func recentre() {
        fusion.recentre()
    }

    /// Applies the processing the console asked for.
    ///
    /// - Parameters:
    ///   - tiltCorrection: Whether tilt is corrected against gravity.
    ///   - angularVelocityDeadband: Whether small rotations are ignored.
    public mutating func tune(tiltCorrection: Bool, angularVelocityDeadband: Bool) {
        fusion.tune(tiltCorrection, angularVelocityDeadband)
    }
}
