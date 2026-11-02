import Dependencies
import ChiakiDiagnostics
import Foundation

/// Times a controller step and logs it as slow when it takes longer than ``SlowStep/threshold``.
struct SlowStep {
    /// The duration at or above which a step is reported as slow.
    static let threshold = Duration.milliseconds(50)

    /// The step label written to the slow-step log entry.
    let name: String
    private let start = ContinuousClock.now

    /// Starts timing a step from the moment of creation.
    /// - Parameter name: The label used when the step is reported.
    init(_ name: String) {
        self.name = name
    }

    /// Stops timing and logs a slow-step entry if the elapsed time reached ``SlowStep/threshold``.
    func finish() {
        let elapsed = ContinuousClock.now - start
        guard elapsed >= Self.threshold else {
            return
        }
        let milliseconds = Int(elapsed.components.seconds * 1000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        let step = name
        @Dependency(\.logger) var logger
        logger.enqueue(.slowControllerStep(step: step, milliseconds: milliseconds))
    }
}
