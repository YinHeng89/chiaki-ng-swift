/// Re-applies a focus stop once a rebuilt view has been inserted, because SwiftUI drops a focus request made while
/// the view is being inserted, as when the Notifications panel swaps a conversation back for its list.
enum FocusRestore {
    /// Sets the stop again after a few turns of the main actor, unless focus moved meanwhile.
    ///
    /// - Parameters:
    ///   - stop: The stop that was requested.
    ///   - read: Reads the view's focus.
    ///   - write: Sets the view's focus.
    @MainActor static func settle<Stop: Equatable>(
        _ stop: Stop,
        read: @escaping @MainActor () -> Stop?,
        write: @escaping @MainActor (Stop?) -> Void
    ) {
        Task { @MainActor in
            for _ in 0..<3 {
                await Task.yield()
            }
            guard read() == stop else {
                return
            }
            write(nil)
            await Task.yield()
            guard read() == nil else {
                return
            }
            write(stop)
        }
    }
}
