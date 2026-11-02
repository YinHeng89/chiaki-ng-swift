@testable import ChiakiPersistence
import Synchronization

final class ReportedFailures: Sendable {
    private let failures = Mutex<[PersistenceError]>([])

    var all: [PersistenceError] {
        failures.withLock {
            $0
        }
    }

    var record: @Sendable (PersistenceError) -> Void {
        { [self] failure in
            failures.withLock {
                $0.append(failure)
            }
        }
    }
}
