/// Moves a window into full screen for a launched stream and back out when the stream ends.
///
/// The window server answers each toggle asynchronously and can miss one, so every toggle is numbered and
/// bounded by a timeout. A restore asked for while the window is still entering full screen leaves it as soon
/// as it arrives, and a present asked for while it is leaving enters again.
public struct WindowFullScreenMachine: Equatable, Sendable {
    /// Where the window is.
    public enum Phase: Equatable, Sendable {
        /// The machine has not moved the window.
        case untouched
        /// The toggle with this number is entering full screen.
        case entering(attempt: Int)
        /// The toggle with this number is entering full screen, and the window leaves once it arrives.
        case leavingAfterEntry(attempt: Int)
        /// The window is in full screen.
        case entered
        /// The toggle with this number is leaving full screen.
        case exiting(attempt: Int)
        /// The toggle with this number is leaving full screen, and the window enters again once it leaves.
        case reenteringAfterExit(attempt: Int)
        /// A toggle timed out before the window arrived in full screen; it may still arrive.
        case lateEntry(exitOnArrival: Bool)
    }

    /// What happened to the window or the stream.
    public enum Event: Equatable, Sendable {
        /// The stream wants full screen.
        case present(windowIsFullScreen: Bool)
        /// The stream ended and the window returns to how it was.
        case restore(windowIsFullScreen: Bool)
        /// The window finished entering full screen.
        case entered
        /// The window finished leaving full screen.
        case exited
        /// The toggle with this number did not finish in time.
        case timedOut(attempt: Int, windowIsFullScreen: Bool)
    }

    /// What the window controller does next.
    public enum Command: Equatable, Sendable {
        /// Toggles the window's full screen state.
        case toggle
        /// Starts observing the window's full screen notifications.
        case observe
        /// Stops observing them.
        case stopObserving
        /// Times out the toggle with this number.
        case scheduleTimeout(Int)
    }

    /// Where the window is.
    public private(set) var phase = Phase.untouched
    private var attempts = 0

    /// Creates a machine that has not moved the window.
    public init() {
    }

    /// Moves the machine on by one event.
    ///
    /// - Parameter event: What happened.
    /// - Returns: What the window controller does next.
    public mutating func handle(_ event: Event) -> [Command] {
        switch event {
        case .present(let windowIsFullScreen):
            present(windowIsFullScreen: windowIsFullScreen)
        case .restore(let windowIsFullScreen):
            restore(windowIsFullScreen: windowIsFullScreen)
        case .entered:
            entryFinished()
        case .exited:
            exitFinished()
        case let .timedOut(attempt, windowIsFullScreen):
            timeOut(attempt, windowIsFullScreen: windowIsFullScreen)
        }
    }

    private mutating func present(windowIsFullScreen: Bool) -> [Command] {
        switch phase {
        case .untouched:
            guard !windowIsFullScreen else {
                return []
            }
            return [.observe] + toggle(into: Phase.entering)
        case .leavingAfterEntry(let attempt):
            phase = .entering(attempt: attempt)
            return []
        case .exiting(let attempt):
            phase = .reenteringAfterExit(attempt: attempt)
            return []
        case .lateEntry:
            phase = .lateEntry(exitOnArrival: false)
            return []
        case .entering, .entered, .reenteringAfterExit:
            return []
        }
    }

    private mutating func restore(windowIsFullScreen: Bool) -> [Command] {
        switch phase {
        case .entering(let attempt):
            phase = .leavingAfterEntry(attempt: attempt)
            return []
        case .entered:
            return windowIsFullScreen
                ? toggle(into: Phase.exiting)
                : finish()
        case .reenteringAfterExit(let attempt):
            phase = .exiting(attempt: attempt)
            return []
        case .lateEntry:
            phase = .lateEntry(exitOnArrival: true)
            return []
        case .untouched, .leavingAfterEntry, .exiting:
            return []
        }
    }

    private mutating func entryFinished() -> [Command] {
        switch phase {
        case .entering:
            phase = .entered
            return []
        case .leavingAfterEntry, .lateEntry(exitOnArrival: true):
            return toggle(into: Phase.exiting)
        case .lateEntry(exitOnArrival: false):
            phase = .entered
            return []
        case .untouched, .entered, .exiting, .reenteringAfterExit:
            return []
        }
    }

    private mutating func exitFinished() -> [Command] {
        switch phase {
        case .exiting, .entered:
            return finish()
        case .reenteringAfterExit:
            return toggle(into: Phase.entering)
        case .untouched, .entering, .leavingAfterEntry, .lateEntry:
            return []
        }
    }

    private mutating func toggle(into next: (Int) -> Phase) -> [Command] {
        attempts += 1
        phase = next(attempts)
        return [.toggle, .scheduleTimeout(attempts)]
    }

    private mutating func finish() -> [Command] {
        phase = .untouched
        return [.stopObserving]
    }

    private mutating func timeOut(_ attempt: Int, windowIsFullScreen: Bool) -> [Command] {
        switch phase {
        case .entering(attempt):
            phase = windowIsFullScreen
                ? .entered
                : .lateEntry(exitOnArrival: false)
            return []
        case .leavingAfterEntry(attempt):
            if windowIsFullScreen {
                return toggle(into: Phase.exiting)
            }
            phase = .lateEntry(exitOnArrival: true)
            return []
        case .exiting(attempt):
            return windowIsFullScreen
                ? toggle(into: Phase.exiting)
                : finish()
        case .reenteringAfterExit(attempt):
            if windowIsFullScreen {
                phase = .entered
                return []
            }
            return toggle(into: Phase.entering)
        default:
            return []
        }
    }
}
