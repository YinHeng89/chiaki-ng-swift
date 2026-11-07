import ChiakiModels
import SwiftUI

/// Whether the local network scan sees a paired console, and whether it rests.
public enum ConsolePresence: Equatable {
    /// The scan has not answered yet.
    case unknown
    /// The console answers and is awake.
    case ready
    /// The console answers from rest mode.
    case restMode
    /// The scan does not see the console.
    case notNearby

    /// The presence of a paired console in a scan.
    ///
    /// - Parameters:
    ///   - console: The paired console.
    ///   - snapshot: What the scan currently sees.
    ///   - searched: Whether the scan has listened long enough that a console it does not see is away.
    /// - Returns: Ready or rest mode when the scan sees the console, not nearby when it searched without
    ///   seeing it, otherwise unknown, so nothing is disabled on a guess.
    public static func of(
        _ console: RegistrationFlow.ConsoleTarget,
        in snapshot: DiscoverySnapshot,
        searched: Bool
    ) -> ConsolePresence {
        guard let match = snapshot.match(for: console) else {
            return searched
                ? .notNearby
                : .unknown
        }
        return match.standby
            ? .restMode
            : .ready
    }

    /// The status label, or `nil` while the presence is unknown.
    public var title: LocalizedStringResource? {
        switch self {
        case .unknown:
            nil
        case .ready:
            .consolesDiscoveredReady
        case .restMode:
            .consolesDiscoveredRestMode
        case .notNearby:
            .consolesPresenceNotNearby
        }
    }

    /// The colour of the status dot: green when ready, amber in rest mode, grey otherwise.
    public var color: Color {
        switch self {
        case .unknown, .notNearby:
            .secondary
        case .ready:
            Color(red: 0.45, green: 0.92, blue: 0.18)
        case .restMode:
            Color(red: 0.95, green: 0.72, blue: 0.29)
        }
    }
}
