import Foundation

/// Limits how many catalog image fetches run at once, queueing the rest in arrival order.
public actor CoreImageCalls {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let limit: Int
    private var running = 0
    private var waiting: [Waiter] = []

    /// Creates a limiter.
    ///
    /// - Parameter limit: How many fetches may run at once; at least one.
    public init(limit: Int) {
        self.limit = max(limit, 1)
    }

    /// How many fetches are running.
    public var inFlight: Int {
        running
    }

    /// How many fetches are waiting for a slot.
    public var queued: Int {
        waiting.count
    }

    /// Runs one fetch once a slot is free.
    ///
    /// - Parameter body: The fetch.
    /// - Returns: What the fetch returned.
    /// - Throws: `CancellationError` when the task was cancelled while waiting, or what the fetch threw.
    public func run<Value: Sendable>(_ body: @Sendable () async throws -> Value) async throws -> Value {
        try await enter()
        defer {
            leave()
        }
        return try await body()
    }

    private func enter() async throws {
        if waiting.isEmpty, running < limit {
            running += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiting.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task {
                await self.withdraw(id)
            }
        }
    }

    private func withdraw(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func leave() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().continuation.resume()
        }
    }
}
