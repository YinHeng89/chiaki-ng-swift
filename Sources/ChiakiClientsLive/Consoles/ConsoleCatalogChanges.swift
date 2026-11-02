import Foundation
import Synchronization

/// Fans out "the saved pairings changed" to every catalog that observes them.
public final class ConsoleCatalogChanges: Sendable {
    private let observers = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    /// Creates a broadcaster with no observers.
    public init() {}

    /// Observes changes.
    ///
    /// - Returns: A stream that yields once per change; ending its iteration stops observing.
    public func stream() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in
            self?.observers.withLock {
                $0[id] = nil
            }
        }
        observers.withLock {
            $0[id] = continuation
        }
        return stream
    }

    /// Tells every observer that the pairings changed.
    public func post() {
        let current = observers.withLock {
            Array($0.values)
        }
        for continuation in current {
            continuation.yield()
        }
    }
}
