import ChiakiModels
import Foundation

/// Remembers, per console, whether this client's own Remote Play session is playing or ended moments ago.
///
/// A start that follows its own session tells the core so, and the core then retries the console's
/// "Remote Play is already in use" refusal for a short while instead of failing at once. A console that never
/// played here, or whose session ended longer ago than ``window``, starts fresh.
@MainActor
final class RecentConsoleSessions {
    /// Where a console's last session here is.
    enum Standing: Equatable {
        /// A session reached its first frame and has not ended.
        case playing

        /// The session that played ended at this time.
        case ended(ContinuousClock.Instant)
    }

    /// How long after a session ended a new start still counts as following it.
    static let window = Duration.seconds(20)

    private var consoles: [HardwareID: Standing] = [:]

    /// Creates an empty record.
    nonisolated init() {}

    /// Records that a session with a console reached its first frame.
    ///
    /// - Parameter console: The console.
    func began(_ console: HardwareID) {
        consoles[console] = .playing
    }

    /// Records that a session with a console ended; a session that never played leaves no record.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - now: When it ended.
    func finished(_ console: HardwareID, at now: ContinuousClock.Instant = .now) {
        guard consoles[console] == .playing else {
            return
        }
        consoles[console] = .ended(now)
    }

    /// Whether a start now follows this client's own session with the console.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - now: The time of the start.
    /// - Returns: `true` while a session plays or within ``window`` of it ending.
    func justLeft(_ console: HardwareID, at now: ContinuousClock.Instant = .now) -> Bool {
        switch consoles[console] {
        case .playing:
            true
        case .ended(let leftAt):
            leftAt.duration(to: now) < Self.window
        case nil:
            false
        }
    }
}
