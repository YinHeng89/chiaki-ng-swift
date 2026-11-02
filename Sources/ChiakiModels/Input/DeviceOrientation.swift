/// How the device is held, which decides how its motion axes map onto a controller's.
public enum DeviceOrientation: Equatable, Sendable {
    /// Upright.
    case portrait

    /// Upside down.
    case portraitUpsideDown

    /// Rotated with the top to the left.
    case landscapeLeft

    /// Rotated with the top to the right.
    case landscapeRight

    /// A device vector in controller axes.
    ///
    /// - Parameter vector: The vector in device axes.
    /// - Returns: The vector in controller axes.
    public func controllerAxes(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .portrait:
            vector
        case .portraitUpsideDown:
            SIMD3(-vector.x, -vector.y, vector.z)
        case .landscapeLeft:
            SIMD3(vector.y, -vector.x, vector.z)
        case .landscapeRight:
            SIMD3(-vector.y, vector.x, vector.z)
        }
    }

    /// The acceleration a controller would report, from the device's gravity and user acceleration.
    ///
    /// - Parameters:
    ///   - gravity: The device's gravity.
    ///   - user: The device's user acceleration.
    /// - Returns: The reading in controller axes.
    public func controllerAcceleration(gravity: SIMD3<Float>, user: SIMD3<Float>) -> SIMD3<Float> {
        controllerAxes(-(gravity + user))
    }
}
