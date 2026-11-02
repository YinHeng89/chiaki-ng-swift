/// How far a launch, console stream start or pairing has got, as the core last reported it.
public struct OperationProgress: Equatable, Sendable, StreamProgressDetail {
    /// Why the operation is paused.
    public typealias WaitReason = ProgressWaitReason

    /// What a cloud launch is doing.
    public typealias LaunchActivity = ChiakiModels.LaunchActivity

    /// What a console stream start is doing.
    public typealias ConnectStep = ChiakiModels.ConnectStep

    /// What a pairing is doing.
    public typealias PairingStep = ChiakiModels.PairingStep

    /// What a route setup is doing.
    public typealias RouteStep = InternetRoute.Step

    /// What a route carries.
    public typealias RoutePurpose = InternetRoute.Purpose

    /// How a chosen route reaches the console.
    public typealias RouteKind = InternetRoute.Kind

    /// What went wrong on this side in a failed attempt.
    public typealias FailureCause = StreamOutcome.Cause

    /// Why the console quit a failed attempt.
    public typealias ConsoleQuit = StreamOutcome.QuitReason

    /// Where the operation is in a counted sequence.
    public typealias Position = ProgressPosition

    /// A pause in the operation.
    public typealias Wait = ProgressWait

    /// How many addresses a route setup gathered.
    public typealias Candidates = InternetRoute.Candidates

    /// How far an internet route has got.
    public typealias Route = InternetRoute

    /// Why the previous attempt failed.
    public typealias Failure = AttemptFailure

    /// The operation's current step.
    public enum Step: Equatable, Sendable {
        /// A cloud launch step.
        case launch(LaunchActivity)

        /// A console stream start step.
        case connect(ConnectStep)

        /// A pairing step.
        case pairing(PairingStep)
    }

    /// The current step.
    public var step: Step

    /// Where the step is in a counted sequence.
    public var position: Position?

    /// Which attempt this is.
    public var attempt: Int

    /// How long the operation has run, in milliseconds.
    public var elapsedMilliseconds: Int?

    /// The pause the operation is in, when it is paused.
    public var wait: Wait?

    /// How far an internet route has got, when one is being set up.
    public var route: Route?

    /// How many datacenters were measured.
    public var measured: Position?

    /// Whether a lost stream is being reconnected.
    public var reconnecting: Bool

    /// Why the previous attempt failed.
    public var previousFailure: Failure?

    /// The place in the server queue.
    public var queuePosition: Int?

    /// The stream service's estimate of the server queue wait, in seconds.
    public var waitTimeEstimateSeconds: Int?

    /// How much of the account's data has moved, in percent.
    public var migrationPercent: Int?

    /// The bandwidth a cloud launch measured, in kilobits per second.
    public var bandwidthKbps: Int?

    /// How old that measurement is, in seconds.
    public var bandwidthAgeSeconds: Int?

    /// Describes progress.
    ///
    /// - Parameters:
    ///   - step: The current step.
    ///   - position: Where the step is in a sequence.
    ///   - attempt: Which attempt this is.
    ///   - elapsedMilliseconds: How long the operation has run.
    ///   - wait: The pause it is in.
    ///   - route: How far an internet route has got.
    ///   - measured: How many datacenters were measured.
    ///   - reconnecting: Whether a lost stream is being reconnected.
    ///   - previousFailure: Why the previous attempt failed.
    ///   - queuePosition: The place in the server queue.
    ///   - waitTimeEstimateSeconds: The stream service's estimate of the server queue wait, in seconds.
    ///   - migrationPercent: How much data has moved.
    public init(
        step: Step,
        position: Position? = nil,
        attempt: Int = 1,
        elapsedMilliseconds: Int? = nil,
        wait: Wait? = nil,
        route: Route? = nil,
        measured: Position? = nil,
        reconnecting: Bool = false,
        previousFailure: Failure? = nil,
        queuePosition: Int? = nil,
        waitTimeEstimateSeconds: Int? = nil,
        migrationPercent: Int? = nil
    ) {
        self.step = step
        self.position = position
        self.attempt = attempt
        self.elapsedMilliseconds = elapsedMilliseconds
        self.wait = wait
        self.route = route
        self.measured = measured
        self.reconnecting = reconnecting
        self.previousFailure = previousFailure
        self.queuePosition = queuePosition
        self.waitTimeEstimateSeconds = waitTimeEstimateSeconds
        self.migrationPercent = migrationPercent
    }

    /// Whether the operation is paused.
    public var isWaiting: Bool {
        wait != nil
    }

    /// The bandwidth a cloud launch reported, or `nil` when this step reported none.
    public var bandwidth: CloudBandwidthReport? {
        guard let bandwidthKbps else {
            return nil
        }
        return CloudBandwidthReport(kbps: bandwidthKbps, ageSeconds: bandwidthAgeSeconds)
    }
}

/// Why the previous start attempt failed.
public struct AttemptFailure: Hashable, Sendable {
    /// What went wrong on this side, when that is what ended the attempt.
    public let cause: StreamOutcome.Cause?

    /// Why the console quit, when the console ended the attempt.
    public let consoleQuit: StreamOutcome.QuitReason?

    /// Whether the attempt failed because this machine had no network, so it never reached PSN or the console.
    public let offline: Bool

    /// Describes a failed attempt.
    ///
    /// - Parameters:
    ///   - cause: What went wrong.
    ///   - consoleQuit: Why the console quit.
    ///   - offline: Whether this machine had no network.
    public init(
        cause: StreamOutcome.Cause? = nil,
        consoleQuit: StreamOutcome.QuitReason? = nil,
        offline: Bool = false
    ) {
        self.cause = cause
        self.consoleQuit = consoleQuit
        self.offline = offline
    }
}

/// What a console stream start is doing.
public enum ConnectStep: Hashable, Sendable, CaseIterable {
    /// Finding the console.
    case findingConsole

    /// Opening the account session.
    case openingAccountSession

    /// Waking the console.
    case wakingConsole

    /// Pairing with the console.
    case pairing

    /// Reaching the console.
    case reachingConsole

    /// Opening the stream route.
    case openingStreamRoute

    /// Requesting the session.
    case requestingSession

    /// Opening the control connection.
    case openingControl

    /// Measuring the connection.
    case measuringConnection

    /// Starting the stream.
    case startingStream
}

/// What a cloud launch is doing.
public enum LaunchActivity: Hashable, Sendable, CaseIterable {
    /// Checking the title with the catalog.
    case clearingWithCatalog

    /// Checking this device.
    case checkingDevice

    /// Opening the title session.
    case openingTitleSession

    /// Finding the title.
    case resolvingTitle

    /// Taking the free licence.
    case takingFreeLicence

    /// Opening the account session.
    case openingAccountSession

    /// Reserving a server.
    case reservingServer

    /// Measuring datacenters.
    case measuringDatacenters

    /// Waiting for a datacenter to be chosen.
    case waitingForDatacenterChoice

    /// Allocating a server.
    case allocatingServer

    /// Moving the account's data.
    case migratingData

    /// Connecting to the server.
    case connectingToServer

    /// Measuring the connection.
    case measuringBandwidth

    /// Loading the library.
    case loadingLibrary

    /// Checking the membership.
    case checkingMembership

    /// Checking that cloud streaming is available.
    case checkingCloudStreaming

    /// Checking ownership.
    case checkingOwnership

    /// Checking the account's copy.
    case checkingEntitlement

    /// Finding the cloud game.
    case resolvingCloudGame

    /// Checking PlayStation's restrictions.
    case checkingExclusions

    /// Checking the release date.
    case checkingRelease
}

/// Where an operation is in a counted sequence, such as step 2 of 5.
public struct ProgressPosition: Hashable, Sendable {
    /// The current item, counting from one.
    public let number: Int

    /// How many items there are.
    public let total: Int

    /// Describes a position.
    ///
    /// - Parameters:
    ///   - number: The current item.
    ///   - total: How many items there are.
    public init(number: Int, total: Int) {
        self.number = number
        self.total = total
    }
}

/// A pause in an operation, with its cause and, when known, how long until it acts again.
public struct ProgressWait: Hashable, Sendable {
    /// What is being waited for.
    public let reason: ProgressWaitReason

    /// Time until the operation acts again, when the wait has a known end.
    public let nextTry: Duration?

    /// Describes a pause.
    ///
    /// - Parameters:
    ///   - reason: What is being waited for.
    ///   - nextTry: Time until the next try, if known.
    public init(reason: ProgressWaitReason, nextTry: Duration? = nil) {
        self.reason = reason
        self.nextTry = nextTry
    }

    /// Time until the next try in whole milliseconds, when the wait has a known end.
    public var nextTryMilliseconds: Int? {
        nextTry.map { remaining in
            Int(remaining.components.seconds) * 1000
                + Int(remaining.components.attoseconds / 1_000_000_000_000_000)
        }
    }
}

/// Why an operation is paused instead of advancing.
public enum ProgressWaitReason: Hashable, Sendable, CaseIterable {
    /// A cloud session the account had open is still closing.
    case previousSessionClosing

    /// The account is queued for a cloud server.
    case serverQueue

    /// The cloud service is moving the account's data before it can allocate a server.
    case dataMigration

    /// Cloud datacenters were offered and the user has not chosen yet.
    case datacenterChoice

    /// The cloud title is not ready to start yet.
    case titleNotReady

    /// The network cannot be reached at the moment.
    case networkUnreachable

    /// The console was sent a wake signal and is starting up.
    case consoleWaking

    /// The console is being waited for to join over the internet.
    case consoleJoining

    /// The console is being waited for to answer a pairing request.
    case consoleAnswering

    /// The operation is resting between connection attempts.
    case connectionRetry

    /// The account's last cloud stream ended moments ago, and the stream service still refuses a new one until it has
    /// closed it.
    case recentCloudSession
}

/// How far an internet route to a console has got.
public struct InternetRoute: Hashable, Sendable {
    /// What the route setup is doing.
    public enum Step: Hashable, Sendable, CaseIterable {
        /// Opening the account session.
        case openingAccountSession

        /// Waiting for the console to join.
        case waitingForConsole

        /// Gathering addresses.
        case gatheringCandidates

        /// Exchanging offers with the console.
        case exchangingOffers

        /// Testing the addresses.
        case testingCandidates

        /// A route was chosen.
        case routeChosen

        /// Confirming the chosen route.
        case confirmingRoute

        /// Moving control onto the stream route.
        case switchingControl
    }

    /// What the route carries.
    public enum Purpose: Hashable, Sendable, CaseIterable {
        /// The control connection.
        case control

        /// The stream.
        case stream
    }

    /// How a chosen route reaches the console.
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// Over the local network.
        case local

        /// Over the public address.
        case publicAddress

        /// Over a guessed port.
        case portGuessed

        /// Over an address the console answered from.
        case discovered
    }

    /// How many addresses of each kind were gathered.
    public struct Candidates: Hashable, Sendable {
        /// Local addresses.
        public let local: Int

        /// Public addresses.
        public let publicAddress: Int

        /// Guessed ports.
        public let portGuessed: Int

        /// Describes the gathered addresses.
        ///
        /// - Parameters:
        ///   - local: Local addresses.
        ///   - publicAddress: Public addresses.
        ///   - portGuessed: Guessed ports.
        public init(local: Int, publicAddress: Int, portGuessed: Int) {
            self.local = local
            self.publicAddress = publicAddress
            self.portGuessed = portGuessed
        }

        /// Every address gathered.
        public var total: Int {
            local + publicAddress + portGuessed
        }
    }

    /// What the route setup is doing.
    public let step: Step

    /// What the route carries.
    public let purpose: Purpose

    /// The addresses gathered, once known.
    public let candidates: Candidates?

    /// The route chosen, once chosen.
    public let chosen: Kind?

    /// Describes a route.
    ///
    /// - Parameters:
    ///   - step: What the setup is doing.
    ///   - purpose: What the route carries.
    ///   - candidates: The addresses gathered.
    ///   - chosen: The route chosen.
    public init(step: Step, purpose: Purpose, candidates: Candidates? = nil, chosen: Kind? = nil) {
        self.step = step
        self.purpose = purpose
        self.candidates = candidates
        self.chosen = chosen
    }
}
