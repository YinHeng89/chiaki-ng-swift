import ChiakiModels
import Foundation

/// Connecting to a console without the user picking it, as a finite state machine.
///
/// Each active state carries the run id that started it, so a step or deadline of an abandoned run cannot
/// move it.
public enum AutoConnect: Equatable, Sendable {
    /// What an automatic connection does once it finds the console.
    public enum StartMode: Equatable, Sendable {
        /// Starts a stream over this route once the console is awake, or when the search times out.
        case stream(PlaybackRoute)
        /// Only wakes the console from rest mode, without streaming.
        case wake
    }
    /// What started an automatic connection.
    public enum Request: Equatable, Sendable {
        /// The app launched, and the connect-at-launch setting decides which console, if any, to connect to.
        case launchSetting
        /// The console with this id was asked for, to be started in this mode.
        case console(UUID, StartMode)
    }
    /// The resolved account, console and start mode of one automatic connection.
    public struct Plan: Equatable, Sendable {
        /// The account whose pairing is used.
        public let account: UUID
        /// The id of the saved console.
        public let consoleID: UUID
        /// The paired console, with its address and identifiers.
        public let console: RegistrationFlow.ConsoleTarget
        /// Whether the console is streamed or only woken.
        public let mode: StartMode

        /// The console's name, or its address when it has none, for messages.
        public var name: String {
            console.name ?? console.address
        }
    }
    /// A step of a run that has a deadline.
    public enum Step: Equatable, Sendable {
        /// Waiting for the library, looking for the console on the network, or waiting for it to wake.
        case library, discovery, wake
    }
    /// Why an automatic connection ended without reaching the console.
    public enum Failure: Error, Equatable, Sendable {
        /// No account is paired with the console, the console has no remote route, a stream already runs, the
        /// saved
        /// data could not be read, the wake request failed, the console did not wake in time, or the console
        /// was not found.
        case notRegistered, remoteUnavailable, busy, storage, wakeFailed, wakeTimedOut, notFound
    }
    /// Whether the connect-at-launch setting was already checked this run of the app.
    public enum LaunchCheck: Equatable, Sendable {
        /// Not checked yet, or checked.
        case pending, done
    }

    /// Whether a stream already holds the app, which keeps an automatic connection from starting.
    public enum Activity: Equatable, Sendable {
        /// Nothing streams.
        case free

        /// A stream runs or is being shown.
        case streaming
    }

    /// Nothing is connecting.
    case idle
    /// The run waits for the saved accounts and consoles before it can resolve the request.
    case awaitingLibrary(UUID, Request)
    /// The run reads the connect-at-launch setting.
    case checkingLaunchSetting(UUID)
    /// The run looks for the console on the local network.
    case discovering(UUID, Plan)
    /// The run sends a wake request to the console in rest mode.
    case waking(UUID, Plan)
    /// The wake request was sent and the run waits for the console to come out of rest mode.
    case awaitingWake(UUID, Plan)
    /// The connection failed, with the console's name when it was known.
    case failed(String?, Failure)

    /// How long a run looks for the console on the local network.
    public static let discoveryTimeout: Duration = .seconds(15)
    /// How long a run waits for the console to wake.
    public static let wakeTimeout: Duration = .seconds(25)
    /// How long a run waits for the saved accounts and consoles.
    public static let libraryTimeout: Duration = .seconds(30)

    /// The id of the active run, or `nil` when nothing is connecting.
    public var run: UUID? {
        switch self {
        case .awaitingLibrary(let run, _), .checkingLaunchSetting(let run), .discovering(let run, _),
             .waking(let run, _), .awaitingWake(let run, _):
            run
        case .idle, .failed:
            nil
        }
    }

    /// The plan of a run that has resolved its console.
    public var plan: Plan? {
        switch self {
        case .discovering(_, let plan), .waking(_, let plan), .awaitingWake(_, let plan):
            plan
        case .idle, .awaitingLibrary, .checkingLaunchSetting, .failed:
            nil
        }
    }

    /// The id of the console the active run connects to, once known.
    public var consoleID: UUID? {
        switch self {
        case .awaitingLibrary(_, .console(let id, _)):
            id
        case .discovering(_, let plan), .waking(_, let plan), .awaitingWake(_, let plan):
            plan.consoleID
        case .idle, .awaitingLibrary, .checkingLaunchSetting, .failed:
            nil
        }
    }

    /// Whether a run is in progress; the idle and failed states are not.
    public var isActive: Bool {
        switch self {
        case .idle, .failed:
            false
        case .awaitingLibrary, .checkingLaunchSetting, .discovering, .waking, .awaitingWake:
            true
        }
    }
}

extension DiscoverySnapshot {
    /// The discovered console that is a paired console, by hardware id or, without one, by address.
    ///
    /// - Parameter console: The paired console.
    /// - Returns: The matching discovered console, if the scan sees it.
    public func match(for console: RegistrationFlow.ConsoleTarget) -> DiscoveredConsole? {
        consoles.first { discovered in
            if let hardwareID = console.hardwareID {
                return Self.hexDigits(hardwareID) == Self.hexDigits(discovered.id)
            }
            return console.address == discovered.address
        }
    }

    private static func hexDigits(_ value: String) -> String {
        value.lowercased().filter {
            $0.isHexDigit
        }
    }
}
