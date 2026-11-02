/// The recently played titles one console reported.
public struct ConsoleTitles: Equatable, Sendable {
    /// The console.
    public let hardwareID: HardwareID

    /// Its titles, most recent first.
    public var titles: [RecentTitle]

    /// Describes one console's titles.
    ///
    /// - Parameters:
    ///   - hardwareID: The console.
    ///   - titles: Its titles.
    public init(hardwareID: HardwareID, titles: [RecentTitle]) {
        self.hardwareID = hardwareID
        self.titles = titles
    }
}

/// Why a console's titles could not be listed or started.
public enum ConsoleTitlesFailure: Error, Equatable, Sendable {
    /// The account has no PSN sign-in.
    case signedOut

    /// PSN refused the account's credentials.
    case auth

    /// The console or PSN refused the request.
    case rejected

    /// PSN or the console could not be reached.
    case unavailable

    /// The reply could not be read.
    case invalidDocument

    /// The request was cancelled.
    case cancelled

    /// Something inside the app failed.
    case internalFailure
}

/// How far a console got starting a title.
public enum ConsoleLaunchState: Equatable, Sendable, CaseIterable {
    /// The request was accepted and is waiting.
    case pending

    /// The console is starting the title.
    case starting

    /// The title started.
    case completed

    /// The console could not start the title.
    case failed
}

/// The recently played titles of an account, one rail per console.
public struct RecentlyPlayedFetch: Equatable, Sendable {
    /// The rails, one per console the account played on.
    public let rails: [RecentlyPlayedRail]
    /// Creates a fetch result.
    ///
    /// - Parameter rails: The rails, one per console.
    public init(rails: [RecentlyPlayedRail]) {
        self.rails = rails
    }
}
