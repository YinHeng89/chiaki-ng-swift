import ChiakiBridge
import Dispatch

/// A cancellation handle the core checks while one operation runs.
///
/// It owns one core request for its whole life; every copy the bridge takes shares the same stop flag, so
/// cancelling after the operation finished is harmless.
final class CoreCancellation: @unchecked Sendable {
    /// The core's request, passed to the operation it cancels.
    let handle = chiaki_bridge.Request()

    /// Creates a handle no operation has used yet.
    init() {}

    /// Asks the operation using this handle to stop.
    func cancel() {
        handle.cancel()
    }

    /// Runs blocking core work on a dispatch queue while the calling task waits, cancelling the core request
    /// when the task is cancelled.
    ///
    /// - Parameters:
    ///   - qos: The quality of service the work runs at.
    ///   - work: The blocking work, handed the request to pass to the core.
    /// - Returns: What the work returned.
    static func run<Value: Sendable>(
        qos: DispatchQoS.QoSClass = .userInitiated,
        _ work: @escaping @Sendable (chiaki_bridge.Request) -> Value
    ) async -> Value {
        let cancellation = CoreCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
                DispatchQueue.global(qos: qos).async {
                    continuation.resume(returning: work(cancellation.handle))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}
