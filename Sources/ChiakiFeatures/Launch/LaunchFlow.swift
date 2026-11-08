import ChiakiModels
import Foundation

/// A resolved request to connect to a console for a command-line launch.
public struct LaunchConnect: Equatable, Sendable {
    /// The launch this connection belongs to.
    public let id: UUID
    /// The profile that owns the console's registration.
    public let profileID: UUID
    /// The console to connect to.
    public let console: RegistrationFlow.ConsoleTarget
    /// Whether to connect locally or remotely.
    public let route: PlaybackRoute

    /// Creates a connection request.
    public init(id: UUID, profileID: UUID, console: RegistrationFlow.ConsoleTarget, route: PlaybackRoute) {
        self.id = id
        self.profileID = profileID
        self.console = console
        self.route = route
    }
}

/// Why the app refused to connect for a launch.
public enum LaunchRejection: Equatable, Sendable {
    /// Another stream is starting or playing.
    case streamActive
    /// The previous stream is still closing.
    case streamClosing
    /// The console is no longer registered to the account.
    case consoleNotLinked
    /// The console has no remote play registration.
    case remoteUnavailable
    /// Remote play needs the account to be signed in.
    case remoteNeedsSignIn
    /// An account is being changed.
    case accountChanging
    /// Something else is open on screen that has to be finished first.
    case screenBusy
}

/// Why a command-line launch did not start a stream, with the text shown to the user.
public enum LaunchFailure: Equatable, Sendable {
    /// No registered console matches the reference.
    case consoleNotFound(LaunchConsoleReference)
    /// The saved consoles could not be loaded.
    case consolesUnavailable
    /// The named console cannot be streamed remotely.
    case remoteUnavailable(String)
    /// Another stream is already starting or playing.
    case busy
    /// The stream did not start before the timeout.
    case notStarted
    /// The app refused the connection for the given reason.
    case rejected(LaunchRejection)

    /// The short heading for the failure notice.
    public var title: LocalizedStringResource {
        switch self {
        case .consoleNotFound:
            .appLaunchConsoleNotFoundTitle
        case .consolesUnavailable:
            .appLaunchConsolesUnavailableTitle
        case .remoteUnavailable, .busy, .notStarted, .rejected:
            .appLaunchStreamFailedTitle
        }
    }

    /// The explanation shown beneath the heading.
    public var message: LocalizedStringResource {
        switch self {
        case .consoleNotFound(let reference):
            .appLaunchConsoleNotFound(reference: reference.description)
        case .consolesUnavailable:
            .appLaunchConsolesUnavailable
        case .remoteUnavailable(let name):
            .appLaunchRemoteUnavailableNamed(name: name)
        case .busy:
            .appLaunchBusy
        case .notStarted:
            .appLaunchNotStarted
        case .rejected(let reason):
            Self.message(for: reason)
        }
    }

    /// The English explanation written to the developer log.
    public var logDescription: String {
        switch self {
        case .consoleNotFound(let reference):
            "No registered console matches \"\(reference.description)\". "
                + "Run chiaki-ng with --list to see them."
        case .consolesUnavailable:
            "Saved consoles could not be loaded, so the requested stream was not started."
        case .remoteUnavailable(let name):
            "\(name) has no remote play registration, so it can’t be streamed remotely."
        case .busy:
            "Another stream is already starting or playing."
        case .notStarted:
            "The stream didn’t start. Try again."
        case .rejected(let reason):
            Self.logDescription(for: reason)
        }
    }

    private static func logDescription(for reason: LaunchRejection) -> String {
        switch reason {
        case .streamActive:
            "Another stream is already starting or playing."
        case .streamClosing:
            "The previous stream is still closing. Try again in a moment."
        case .consoleNotLinked:
            "That console is no longer registered to this account."
        case .remoteUnavailable:
            "That console has no remote play registration, so it can’t be streamed remotely."
        case .remoteNeedsSignIn:
            "Remote play needs this account to be signed in to PlayStation Network."
        case .accountChanging:
            "An account is being changed. Try again when it has finished."
        case .screenBusy:
            "Finish what is open in chiaki-ng, then try again."
        }
    }

    private static func message(for reason: LaunchRejection) -> LocalizedStringResource {
        switch reason {
        case .streamActive:
            .appLaunchBusy
        case .streamClosing:
            .appLaunchStreamClosing
        case .consoleNotLinked:
            .appLaunchConsoleNotLinked
        case .remoteUnavailable:
            .appLaunchRemoteUnavailable
        case .remoteNeedsSignIn:
            .appLaunchRemoteNeedsSignIn
        case .accountChanging:
            .appLaunchAccountChanging
        case .screenBusy:
            .appLaunchScreenBusy
        }
    }
}

/// The state machine for a command-line launch: finds the requested console once the catalog is ready, asks
/// to connect, follows the stream, restores the window and decides when to quit, returning effects for the
/// reducer to run.
public struct LaunchFlow: Equatable, Sendable {
    /// Where the current launch is.
    public enum Phase: Equatable, Sendable {
        /// No launch is in progress.
        case idle
        /// Waiting for the console catalog to resolve the launch's console.
        case resolving(UUID, LaunchStream)
        /// Connecting to the resolved console.
        case connecting(LaunchConnect, LaunchStream)
        /// The launched stream is playing.
        case streaming(UUID, LaunchStream)
    }

    /// How far the console catalog has loaded.
    public enum Catalog: Equatable, Sendable {
        /// The catalog has not loaded yet.
        case pending
        /// The catalog has loaded.
        case loaded
        /// The catalog failed to load.
        case failed
    }

    /// What the app's stream is doing, as reported to the launch flow.
    public enum StreamActivity: Equatable, Sendable {
        /// No stream is active.
        case idle
        /// A previous stream is being resumed.
        case resuming
        /// A stream to the given console is being prepared.
        case preparing(UUID?)
        /// Preparing a stream failed.
        case preparationFailed
        /// A stream to the given console is connecting.
        case connecting(UUID?)
        /// A stream to the given console is playing.
        case playing(UUID?)
        /// A stream to the given console is closing.
        case closing(UUID?)
    }

    /// The registered consoles a launch can be resolved against.
    public struct Consoles: Equatable, Sendable {
        /// Every saved registration.
        public var registrations: [RegistrationFlow.Registration]
        /// The selected profile, preferred when several registrations match.
        public var selectedProfileID: UUID?
        /// How far the catalog has loaded.
        public var catalog: Catalog

        /// Creates a console snapshot.
        public init(
            registrations: [RegistrationFlow.Registration],
            selectedProfileID: UUID?,
            catalog: Catalog = .loaded
        ) {
            self.registrations = registrations
            self.selectedProfileID = selectedProfileID
            self.catalog = catalog
        }
    }

    /// What the launch flow is told.
    public enum Event: Equatable, Sendable {
        /// A launch request arrived with the current consoles and stream activity.
        case requested(UUID, LaunchRequest, Consoles, StreamActivity)
        /// The console catalog changed.
        case consolesChanged(Consoles)
        /// The app refused to connect for the launch with this id.
        case connectRejected(UUID, LaunchRejection)
        /// The timeout for the launch with this id fired.
        case timedOut(UUID)
        /// The app's stream activity changed.
        case stream(StreamActivity)
    }

    /// Work the reducer performs for the launch flow.
    public enum Effect: Equatable, Sendable {
        /// Connect to a console and show the stream as asked.
        case connect(LaunchConnect, LaunchDisplay)
        /// Show the playing stream as asked.
        case present(LaunchDisplay)
        /// Start the timeout for resolving or preparing the launch.
        case scheduleTimeout(UUID)
        /// Start the timeout for connecting the launch.
        case scheduleConnectTimeout(UUID)
        /// Cancel the pending timeout.
        case cancelTimeout
        /// Cancel the connection in progress.
        case cancelConnect
        /// Return the window to how it was before the launch.
        case restoreDisplay
        /// Quit the app.
        case quit
        /// Show a failure notice.
        case report(LaunchFailure)
    }

    private enum Resolution {
        case found(RegistrationFlow.Registration)
        case waiting
        case missing(LaunchFailure)
    }

    /// Where the current launch is.
    public private(set) var phase = Phase.idle
    /// How far the console catalog had loaded at the last update.
    public private(set) var catalog = Catalog.pending
    /// Tracks whether the app should quit when the watched stream ends.
    public private(set) var exitWatch = ExitWatch.disabled
    /// The stream activity last reported.
    public private(set) var activity = StreamActivity.idle

    /// Creates an idle launch flow.
    public init() {
    }

    /// Applies an event and returns the effects to run.
    /// - Parameter event: What happened.
    /// - Returns: The effects, in order.
    public mutating func send(_ event: Event) -> [Effect] {
        switch event {
        case let .requested(id, request, consoles, activity):
            catalog = consoles.catalog
            self.activity = activity
            return requested(id, request, consoles: consoles)
        case .consolesChanged(let consoles):
            catalog = consoles.catalog
            guard case let .resolving(id, stream) = phase else {
                return []
            }
            if let failure = Self.blocked(by: activity) {
                phase = .idle
                return [.cancelTimeout, .report(failure)]
            }
            return resolve(id, stream, consoles: consoles)
        case let .connectRejected(id, reason):
            guard case .connecting(let connect, let stream) = phase, connect.id == id else {
                return []
            }
            phase = .idle
            let ended: ExitWatch.Event = reason == .streamActive
                ? .launchSuperseded(id)
                : .launchEnded(id, stream.exit)
            return [.cancelTimeout, .restoreDisplay, .report(.rejected(reason))] + watch(ended)
        case .timedOut(let id):
            return timedOut(id)
        case .stream(let next):
            return streamChanged(next)
        }
    }

    private mutating func timedOut(_ id: UUID) -> [Effect] {
        switch phase {
        case .connecting(let connect, let stream) where connect.id == id:
            phase = .idle
            return [.cancelConnect, .restoreDisplay, .report(.notStarted)] + watch(.launchEnded(
                id,
                stream.exit
            ))
        case .resolving(id, let stream):
            phase = .idle
            let failure: LaunchFailure
            switch catalog {
            case .loaded:
                failure = .consoleNotFound(stream.console)
            case .pending, .failed:
                failure = .consolesUnavailable
            }
            return [.report(failure)] + watch(.launchEnded(id, stream.exit))
        case .idle, .resolving, .connecting, .streaming:
            return []
        }
    }

    private mutating func requested(_ id: UUID, _ request: LaunchRequest, consoles: Consoles) -> [Effect] {
        switch request {
        case .list:
            return []
        case .session(let exit):
            if exit == .quitApp {
                _ = exitWatch.send(.sessionRequested)
            }
            return []
        case .stream(let stream):
            switch phase {
            case .streaming, .connecting:
                return [.report(.busy)]
            case .idle, .resolving:
                if let failure = Self.blocked(by: activity) {
                    return [.report(failure)]
                }
                return resolve(id, stream, consoles: consoles)
            }
        }
    }

    private static func blocked(by activity: StreamActivity) -> LaunchFailure? {
        switch activity {
        case .connecting, .playing:
            return .busy
        case .closing:
            return .rejected(.streamClosing)
        case .idle, .resuming, .preparing, .preparationFailed:
            return nil
        }
    }

    private mutating func resolve(_ id: UUID, _ stream: LaunchStream, consoles: Consoles) -> [Effect] {
        let registration: RegistrationFlow.Registration
        switch Self.resolution(stream.console, in: consoles) {
        case .found(let found):
            registration = found
        case .missing(let failure):
            phase = .idle
            return [.cancelTimeout, .report(failure)] + watch(.launchEnded(id, stream.exit))
        case .waiting:
            let waiting = phase != .resolving(id, stream)
            phase = .resolving(id, stream)
            return waiting
                ? [.scheduleTimeout(id)]
                : []
        }
        let route: PlaybackRoute
        switch stream.route {
        case .local:
            route = .local
        case .remote:
            guard registration.console.remoteDeviceID != nil else {
                phase = .idle
                let name = registration.console.name ?? registration.console.address
                return [.cancelTimeout, .report(.remoteUnavailable(name))] + watch(.launchEnded(
                    id,
                    stream.exit
                ))
            }
            route = .remote
        }
        let connect = LaunchConnect(
            id: id,
            profileID: registration.profileID,
            console: registration.console,
            route: route
        )
        phase = .connecting(connect, stream)
        if stream.exit == .quitApp {
            _ = exitWatch.send(.launchConnecting(id))
        }
        return [.scheduleConnectTimeout(id), .connect(connect, stream.display)]
    }

    private static func resolution(_ reference: LaunchConsoleReference, in consoles: Consoles) -> Resolution {
        let candidates = candidates(reference, in: consoles)
        switch (candidates.count, consoles.catalog) {
        case (0, .loaded):
            return .missing(.consoleNotFound(reference))
        case (0, .failed):
            return .missing(.consolesUnavailable)
        case (0, .pending):
            return .waiting
        case (1, _), (_, .loaded), (_, .failed):
            return .found(preferred(candidates, selected: consoles.selectedProfileID))
        case (_, .pending):
            return .waiting
        }
    }

    private mutating func streamChanged(_ next: StreamActivity) -> [Effect] {
        let previous = activity
        activity = next
        if case .connecting(let connect, let stream) = phase,
           let effects = preparation(connect, stream, from: previous, to: next) {
            return effects
        }
        var effects: [Effect] = []
        switch (phase, next) {
        case (.connecting(let connect, let stream), .connecting(let console))
            where console == connect.console.id,
             (.connecting(let connect, let stream), .playing(let console))
                 where console == connect.console.id:
            phase = .streaming(connect.id, stream)
            effects.append(contentsOf: [.cancelTimeout, .present(stream.display)])
        case (.connecting(let connect, _), .connecting), (.connecting(let connect, _), .playing):
            phase = .idle
            effects.append(contentsOf: [.cancelTimeout, .cancelConnect, .restoreDisplay])
            effects.append(contentsOf: watch(.launchSuperseded(connect.id)))
        case (.streaming(let id, let stream), .idle):
            phase = .idle
            effects.append(.restoreDisplay)
            effects.append(contentsOf: watch(.launchEnded(id, stream.exit)))
        case (.idle, _), (.resolving, _), (.connecting, _), (.streaming, .connecting), (.streaming, .playing),
             (.streaming, .resuming), (.streaming, .closing), (.streaming, .preparing),
             (.streaming, .preparationFailed):
            break
        }
        switch next {
        case .playing:
            effects.append(contentsOf: watch(.streamPlaying))
        case .idle:
            effects.append(contentsOf: watch(.streamEnded))
        case .resuming, .connecting, .closing, .preparing, .preparationFailed:
            break
        }
        return effects
    }

    private mutating func watch(_ event: ExitWatch.Event) -> [Effect] {
        switch exitWatch.send(event) {
        case .quit:
            return [.quit]
        case .stay:
            return []
        }
    }
}

extension LaunchFlow {
    fileprivate mutating func preparation(
        _ connect: LaunchConnect,
        _ stream: LaunchStream,
        from previous: StreamActivity,
        to next: StreamActivity
    ) -> [Effect]? {
        guard previous != next else {
            return nil
        }
        switch next {
        case .preparing(connect.console.id):
            return [.scheduleTimeout(connect.id)]
        case .preparing:
            phase = .idle
            return [.cancelTimeout, .cancelConnect, .restoreDisplay] + watch(.launchSuperseded(connect.id))
        case .preparationFailed:
            phase = .idle
            return [.cancelTimeout, .restoreDisplay] + watch(.launchEnded(connect.id, stream.exit))
        case .idle where previous == .preparing(connect.console.id):
            return [.scheduleConnectTimeout(connect.id)]
        case .idle, .resuming, .connecting, .playing, .closing:
            return nil
        }
    }
}

extension LaunchFlow {
    /// Finds the registration a console reference names, preferring the selected profile when several match.
    /// - Parameters:
    ///   - reference: The console id or name to match.
    ///   - consoles: The registrations to search.
    /// - Returns: The matching registration, or `nil` when none matches.
    public static func match(
        _ reference: LaunchConsoleReference,
        in consoles: Consoles
    ) -> RegistrationFlow.Registration? {
        let found = candidates(reference, in: consoles)
        guard !found.isEmpty else {
            return nil
        }
        return preferred(found, selected: consoles.selectedProfileID)
    }

    private static func candidates(
        _ reference: LaunchConsoleReference,
        in consoles: Consoles
    ) -> [RegistrationFlow.Registration] {
        consoles.registrations.filter { registration in
            matches(reference, registration.console)
        }
    }

    private static func preferred(
        _ candidates: [RegistrationFlow.Registration],
        selected: UUID?
    ) -> RegistrationFlow.Registration {
        candidates.first {
            $0.profileID == selected
        } ?? candidates[0]
    }

    private static func matches(_ reference: LaunchConsoleReference,
                                _ console: RegistrationFlow.ConsoleTarget) -> Bool {
        switch reference {
        case .id(let id):
            return console.id == id
        case .name(let name):
            let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return [console.name, console.hardwareID, console.address].contains { candidate in
                candidate?.compare(wanted, options: [.caseInsensitive]) == .orderedSame
            }
        }
    }
}
