import ChiakiModels
import Foundation

/// Turns the motion sensors on for exactly the controllers whose motion reaches the stream, and applies the
/// motion processing and resets the console asks for.
@MainActor
final class MotionInput {
    private let environment: InputEnvironment
    private var sensing: Set<UInt32> = []

    /// Creates the motion input.
    ///
    /// - Parameter environment: The player, controllers and lanes it drives.
    init(environment: InputEnvironment) {
        self.environment = environment
    }

    /// The controllers whose motion should reach the stream.
    ///
    /// - Parameters:
    ///   - playerOne: Player one's controller id.
    ///   - active: Whether the stream has input.
    ///   - seats: The seated controllers' ids.
    ///   - seatsActive: Whether the seats reach the stream.
    /// - Returns: The ids to sense.
    nonisolated static func wanted(playerOne: UInt32?, active: Bool, seats: Set<UInt32>,
                                   seatsActive: Bool) -> Set<UInt32> {
        var wanted = Set<UInt32>()
        if seatsActive {
            wanted.formUnion(seats)
        }
        if active, let playerOne {
            wanted.insert(playerOne)
        }
        return wanted
    }

    /// Whether the device's own motion sensors can drive the gyro.
    var deviceMotionAvailable: Bool {
        #if os(iOS)
            environment.phoneMotion.available
        #else
            false
        #endif
    }

    /// Senses motion on exactly the given controllers, restarting the fusion of any that start.
    ///
    /// - Parameter wanted: The controllers to sense.
    func sense(_ wanted: Set<UInt32>) {
        let timing = SlowStep("turning motion sensors on or off")
        defer {
            timing.finish()
        }
        for id in sensing.subtracting(wanted) {
            environment.backend.setMotion(id, enabled: false)
        }
        for id in wanted.subtracting(sensing) {
            environment.backend.setMotion(id, enabled: true)
            environment.pipeline.restartMotion(device: id)
        }
        sensing = wanted
    }

    /// Starts or stops the device's own motion sensors.
    ///
    /// - Parameter enabled: Whether device motion should drive the gyro.
    func senseDevice(_ enabled: Bool) {
        #if os(iOS)
            if enabled {
                environment.phoneMotion.start()
            } else {
                environment.phoneMotion.stop()
            }
        #endif
    }

    /// Applies the motion processing and reset the console sent since the last poll.
    func applyConsoleRequests() {
        if let processing = ControllerMotionProcessing(taken: environment.player.takeMotionSettings()) {
            environment.pipeline.process(motion: processing)
        }
        guard environment.player.takeMotionReset() else {
            return
        }
        environment.pipeline.resetMotion()
    }
}
