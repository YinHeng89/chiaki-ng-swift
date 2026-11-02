import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation

/// Builds an account's recently played rails from the titles PSN lists and the account's paired PS5s, and
/// launches titles.
public struct RecentlyPlayedService: Sendable {
    /// Talks to PSN and the consoles.
    public var transport: ConsoleTitlesTransport
    /// The PSN account id of a saved account.
    public var account: @Sendable (UUID) async throws -> Data
    /// The paired PS5s of a saved account that have a hardware id.
    public var consoles: @Sendable (UUID) async throws -> [RecentlyPlayedConsole]
    /// Writes a diagnostic line at a level.
    public var log: @Sendable (LogLevel, String) async -> Void
    /// Creates a service.
    ///
    /// - Parameters:
    ///   - transport: Talks to PSN and the consoles.
    ///   - account: Reads an account's PSN account id.
    ///   - consoles: Reads an account's paired PS5s.
    ///   - log: Writes diagnostic lines; discards them by default.
    public init(
        transport: ConsoleTitlesTransport,
        account: @escaping @Sendable (UUID) async throws -> Data,
        consoles: @escaping @Sendable (UUID) async throws -> [RecentlyPlayedConsole],
        log: @escaping @Sendable (LogLevel, String) async -> Void = { _, _ in }
    ) {
        self.transport = transport
        self.account = account
        self.consoles = consoles
        self.log = log
    }

    /// Fetches an account's recently played titles, one rail per paired PS5 that PSN lists titles for.
    ///
    /// - Parameter id: The saved account.
    /// - Returns: The rails; none when the account has no paired PS5.
    /// - Throws: The transport's failure, or `ConsoleTitlesFailure.signedOut` when the account is missing.
    public func fetch(account id: UUID) async throws -> RecentlyPlayedFetch {
        let consoles = try await consoles(id)
        guard !consoles.isEmpty else {
            return RecentlyPlayedFetch(rails: [])
        }
        let listed = try await transport.fetch(account(id))
        try Task.checkCancellation()
        let rails = consoles.compactMap { console -> RecentlyPlayedRail? in
            guard let titles = listed.first(where: { $0.hardwareID.data == console.hardwareID }) else {
                return nil
            }
            return RecentlyPlayedRail(
                consoleID: console.consoleID, hardwareID: console.hardwareID, titles: titles.titles
            )
        }
        await log(
            rails.count == consoles.count
                ? .info
                : .warning,
            "\(consoles.count) registered PS5(s), titles listed for \(listed.count), matched \(rails.count)"
        )
        await log(.info, Self.loadedLine(rails))
        return RecentlyPlayedFetch(rails: rails)
    }

    /// The diagnostic summary of loaded rails: each console's title count and how many it played itself.
    ///
    /// - Parameter rails: The loaded rails.
    /// - Returns: One log line.
    static func loadedLine(_ rails: [RecentlyPlayedRail]) -> String {
        guard !rails.isEmpty else {
            return "Recently played loaded: no console listed titles"
        }
        let consoles = rails.map { rail in
            let own = rail.titles.filter(\.playedOnThisConsole).count
            return "console \(LogFormat.hexPrefix(rail.hardwareID)) \(rail.titles.count) title(s), "
                + "\(own) with the console's own time"
        }
        return "Recently played loaded: " + consoles.joined(separator: "; ")
    }

    /// Asks a console to launch a title as an account.
    ///
    /// - Parameters:
    ///   - id: The saved account.
    ///   - hardwareID: The console's hardware id.
    ///   - title: The title to launch.
    /// - Returns: What the console did with the request.
    /// - Throws: The transport's failure.
    public func launch(account id: UUID, hardwareID: Data,
                       title: RecentTitle) async throws -> ConsoleLaunchState {
        try await transport.launch(account(id), hardwareID, title)
    }
}

extension RecentlyPlayedService {
    /// The service over the core and the app's database.
    ///
    /// - Returns: The service.
    static func live() -> RecentlyPlayedService {
        RecentlyPlayedService(
            transport: .native,
            account: { id in
                @Dependency(\.accountService) var accountService
                guard let profile = try await accountService.storage().accounts.list()
                    .first(where: { $0.id == id })
                else {
                    throw ConsoleTitlesFailure.signedOut
                }
                return profile.accountID.data
            },
            consoles: { account in
                @Dependency(\.accountService) var accountService
                return try await accountService.storage().consoles.registeredConsoles().filter {
                    $0.accountID == account && $0.ps5
                }.compactMap { console in
                    console.hardwareID.flatMap { HardwareID(hex: $0)?.data }.map {
                        RecentlyPlayedConsole(consoleID: console.id, hardwareID: $0)
                    }
                }
            },
            log: { level, message in
                @Dependency(\.logger) var logger
                await logger.log(.diagnostic(.recentlyPlayed, level, message))
            }
        )
    }
}

/// A paired PS5 whose recently played titles the rails show.
public struct RecentlyPlayedConsole: Equatable, Sendable {
    /// The id of the saved console.
    public let consoleID: UUID
    /// The console's hardware id, which matches it to the titles PSN lists.
    public let hardwareID: Data
    /// Creates a console.
    ///
    /// - Parameters:
    ///   - consoleID: The id of the saved console.
    ///   - hardwareID: The console's hardware id.
    public init(consoleID: UUID, hardwareID: Data) {
        self.consoleID = consoleID
        self.hardwareID = hardwareID
    }
}

/// Asks PlayStation Network for recently played titles and asks a console to launch one, by raw identifiers.
public struct ConsoleTitlesTransport: Sendable {
    /// Lists, for an account id, the recently played titles of each of its consoles.
    public var fetch: @Sendable (Data) async throws -> [ConsoleTitles]
    /// Asks a console, by hardware id, to launch a title as an account id, and reports what the console did.
    public var launch: @Sendable (Data, Data, RecentTitle) async throws -> ConsoleLaunchState
    /// Creates a transport.
    ///
    /// - Parameters:
    ///   - fetch: Lists an account's recently played titles per console.
    ///   - launch: Launches a title on a console.
    public init(
        fetch: @escaping @Sendable (Data) async throws -> [ConsoleTitles],
        launch: @escaping @Sendable (Data, Data, RecentTitle) async throws -> ConsoleLaunchState
    ) {
        self.fetch = fetch
        self.launch = launch
    }
}

extension ConsoleTitlesTransport {
    /// Talks to PSN and the consoles through the core, logging failures; a cancelled request throws
    /// `CancellationError`.
    static let native = Self(
        fetch: { account in
            guard let account = AccountID(bytes: account) else {
                throw ConsoleTitlesFailure.signedOut
            }
            do throws(ConsoleTitlesFailure) {
                return try await ConsoleTitlesBridge().recentlyPlayed(account: account)
            } catch {
                throw await logged(error, "Fetching recently played titles")
            }
        },
        launch: { account, hardwareID, title in
            guard let account = AccountID(bytes: account), let console = HardwareID(bytes: hardwareID) else {
                throw ConsoleTitlesFailure.unavailable
            }
            do throws(ConsoleTitlesFailure) {
                return try await ConsoleTitlesBridge().start(
                    titleID: title.titleID, launchID: title.launchID, on: console, as: account
                )
            } catch {
                throw await logged(error, "Launching \(title.titleID)")
            }
        }
    )

    private static func logged(_ failure: ConsoleTitlesFailure, _ label: String) async -> any Error {
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(
            .recentlyPlayed,
            failure == .cancelled
                ? .debug
                : .warning,
            "\(label) failed: \(failure)"
        ))
        return failure == .cancelled
            ? CancellationError()
            : failure
    }
}
