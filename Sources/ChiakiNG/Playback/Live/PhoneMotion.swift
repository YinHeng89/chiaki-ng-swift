import ChiakiModels
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
#if os(iOS)
    import CoreMotion
    import UIKit

    /// Streams the iPhone or iPad's own motion sensors into player one's controller at 100 Hz, rotated to
    /// match the current interface orientation.
    @MainActor final class PhoneMotion {
        /// The device motion sampling interval in seconds.
        static let interval: TimeInterval = 1.0 / 100

        private enum Phase {
            case idle
            case running(UInt64)
        }

        private let manager = CMMotionManager()
        private let pipeline: GameInputPipeline
        private var phase = Phase.idle
        private var generation: UInt64 = 0

        /// Creates the motion source over the pipeline its samples go to.
        ///
        /// - Parameter pipeline: The game input pipeline that hands the samples to player one.
        init(pipeline: GameInputPipeline) {
            self.pipeline = pipeline
        }

        /// Whether the device has motion sensors that can be streamed.
        var available: Bool {
            manager.isDeviceMotionAvailable
        }

        /// Starts device motion updates if idle and available; samples from an earlier run are discarded.
        func start() {
            guard case .idle = phase, available else {
                return
            }
            generation += 1
            let run = generation
            phase = .running(run)
            manager.deviceMotionUpdateInterval = Self.interval
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion else {
                    return
                }
                MainActor.assumeIsolated {
                    self?.deliver(motion, run: run)
                }
            }
        }

        /// Stops device motion updates if they are running.
        func stop() {
            guard case .running = phase else {
                return
            }
            phase = .idle
            manager.stopDeviceMotionUpdates()
        }

        private func deliver(_ motion: CMDeviceMotion, run: UInt64) {
            guard case let .running(current) = phase, current == run else {
                return
            }
            let orientation = Self.orientation()
            let rate = motion.rotationRate
            let gyro = orientation.controllerAxes(SIMD3(Float(rate.x), Float(rate.y), Float(rate.z)))
            let accel = orientation.controllerAcceleration(
                gravity: SIMD3(Float(motion.gravity.x), Float(motion.gravity.y), Float(motion.gravity.z)),
                user: SIMD3(
                    Float(motion.userAcceleration.x),
                    Float(motion.userAcceleration.y),
                    Float(motion.userAcceleration.z)
                )
            )
            pipeline.deviceMotion(
                gyro: gyro,
                accel: accel,
                at: UInt64(motion.timestamp * 1_000_000)
            )
        }

        private static func orientation() -> DeviceOrientation {
            let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
            switch scene?.effectiveGeometry.interfaceOrientation {
            case .portraitUpsideDown:
                return .portraitUpsideDown
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            default:
                return .portrait
            }
        }
    }
#endif
