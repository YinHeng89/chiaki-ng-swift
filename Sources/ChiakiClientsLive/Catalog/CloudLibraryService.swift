import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation

/// Fetches each account's cloud library from the core, following the core's fetch states and logging how each
/// fetch went, and refreshes single titles.
///
/// The core runs one fetch per account and joins every further caller to it, so the service keeps no fetches of
/// its own.
public struct CloudLibraryService: Sendable {
    /// A service fetching from the core's catalog; the composition root builds one for the app.
    ///
    /// - Returns: The service.
    public static func overCore() -> CloudLibraryService {
        CloudLibraryService()
    }

    /// Fetches the cloud library of one account, joining the core's fetch when one is already running.
    ///
    /// The observer is first told the state of a fetch already running, read from the core, and then every state
    /// the core reports for the fetch this call leads or joins.
    ///
    /// - Parameters:
    ///   - account: The account whose library is fetched.
    ///   - force: Whether the catalog must be fetched again instead of answered from its cache.
    ///   - locale: The locale the catalog is listed in, such as `"en-GB"`.
    ///   - observe: Told every state of the core's fetch, in order; never called after this returns.
    /// - Returns: The library snapshot.
    /// - Throws: `CancellationError` when the caller is cancelled, or the fetch's failure.
    func fetch(
        account: UUID,
        force: Bool,
        locale: String,
        observe: @escaping @Sendable (CloudLibraryFetchState) -> Void
    ) async throws -> CloudLibrarySnapshot {
        try await Self.catalog(account: account, force: force, locale: locale, observe: observe)
    }

    private static func catalog(
        account: UUID,
        force: Bool,
        locale: String,
        observe: @escaping @Sendable (CloudLibraryFetchState) -> Void
    ) async throws -> CloudLibrarySnapshot {
        let who = "account \(LogFormat.idPrefix(account))"
        let clock = ContinuousClock()
        let start = clock.now
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(
            .cloudLibrary,
            .info,
            CloudLibraryLog.started(who, locale, force)
        ))
        do {
            @Dependency(\.accountService) var accountService
            guard let bytes = try await accountService.accountID(of: account) else {
                throw CloudLibraryFailure.signInRequired
            }
            let catalog = CatalogBridge()
            if let running = catalog.fetchState(account: bytes), running.isRunning {
                observe(running)
            }
            let games: [CloudGame]
            do {
                games = try await catalog.myGames(account: bytes, startOver: force, observe: observe)
            } catch {
                guard error.reason != .cancelled else {
                    throw CancellationError()
                }
                await logger.log(.diagnostic(
                    .cloudLibrary, .error,
                    "Catalog request for locale \(locale) was not answered: \(error.reason), HTTP \(error.httpStatus)"
                ))
                throw error.libraryFailure
            }
            try Task.checkCancellation()
            let snapshot = CloudLibrarySnapshot(settledLocale: locale, games: games)
            let milliseconds = LogFormat.milliseconds(start.duration(to: clock.now))
            await logger.log(.diagnostic(
                .cloudLibrary, .info,
                CloudLibraryLog.loaded(snapshot, who: who, locale: locale, milliseconds: milliseconds)
            ))
            for line in CloudLibraryLog.dropped(snapshot) {
                @Dependency(\.logger) var logger
                await logger.log(.diagnostic(.cloudLibrary, .info, line))
            }
            return snapshot
        } catch is CancellationError {
            let milliseconds = LogFormat.milliseconds(start.duration(to: clock.now))
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .cloudLibrary, .info, CloudLibraryLog.cancelled(who, locale, milliseconds)
            ))
            throw CancellationError()
        } catch {
            let milliseconds = LogFormat.milliseconds(start.duration(to: clock.now))
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .cloudLibrary, .error, CloudLibraryLog.failed(who, locale, milliseconds, error)
            ))
            throw error
        }
    }

    /// Asks the store again whether the account can play one title, typically after it was added to the library in
    /// the store, and logs the outcome.
    ///
    /// - Parameters:
    ///   - account: The account to check for.
    ///   - game: The title to refresh.
    /// - Returns: The refresh outcome, or a failure when the account has no saved sign-in.
    func refreshTitle(account: UUID, game: CloudGame) async -> CloudTitleRefreshOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        let outcome: CloudTitleRefreshOutcome
        @Dependency(\.accountService) var accountService
        if let bytes = try? await accountService.accountID(of: account) {
            outcome = await CatalogBridge().refreshTitle(account: bytes, game: game)
        } else {
            outcome = .failed(.noSignIn)
        }
        let milliseconds = LogFormat.milliseconds(start.duration(to: clock.now))
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(
            .cloudLibrary,
            outcome.logLabel == "failed"
                ? .warning
                : .info,
            CloudLibraryLog.titleRefreshed(game, outcome: outcome, milliseconds: milliseconds)
        ))
        return outcome
    }
}

extension CloudLibraryService {
    /// Fetches the account's recently played cloud games.
    ///
    /// - Parameter account: The account whose history is fetched.
    /// - Returns: The recently played games, most recent first.
    /// - Throws: `CloudLibraryFailure.signInRequired` when the account has no saved sign-in,
    ///   `CancellationError` when the request was cancelled, or the library failure matching the core's
    ///   answer.
    func recentlyPlayed(account: UUID) async throws -> [CloudRecentlyPlayed] {
        @Dependency(\.accountService) var accountService
        guard let bytes = try await accountService.accountID(of: account) else {
            throw CloudLibraryFailure.signInRequired
        }
        let played: [CloudRecentlyPlayed]
        do throws(CatalogUnanswered) {
            played = try await CatalogBridge().recentlyPlayed(account: bytes)
        } catch {
            guard error.reason != .cancelled else {
                throw CancellationError()
            }
            throw error.libraryFailure
        }
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(
            .cloudLibrary, .info, "Recently played: \(played.count) cloud game(s)"
        ))
        return played
    }
}
