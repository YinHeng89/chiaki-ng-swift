import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import ComposableArchitecture
import Foundation

/// Refreshes the saved PlayStation accounts from PSN: each account's online id, membership and avatar, cached in the
/// account resources.
///
/// A failed refresh marks the account as needing sign-in or as unavailable; cancelling the run stops it at
/// the next account.
enum AccountDetailsRefresh {
    /// Refreshes every PlayStation account in turn, caching each one's details and avatar.
    ///
    /// - Parameter repositories: The open repositories.
    /// - Returns: The issue each failed refresh met, by account.
    /// - Throws: `CancellationError` when the run was cancelled.
    static func run(
        _ repositories: AppRepositories
    ) async throws -> [UUID: AccountRefreshResult.Issue] {
        var issues: [UUID: AccountRefreshResult.Issue] = [:]
        let clock = ContinuousClock()
        for profile in try repositories.accounts.list() where profile.method == .npsso {
            try Task.checkCancellation()
            let start = clock.now
            let name = "\"\(profile.onlineID ?? profile.name)\" (id \(LogFormat.idPrefix(profile.id)))"
            do {
                let user = try await UsersBridge().refresh(profile.accountID)
                let avatar = try await saveDetails(of: user, for: profile, in: repositories.resources)
                @Dependency(\.logger) var logger
                await logger.log(.diagnostic(
                    .accounts, .info,
                    "Refreshed \(name) in \(LogFormat.milliseconds(start.duration(to: clock.now))) ms: online ID "
                        + "\"\(user.onlineID)\", PS Plus "
                        + (user.plusMember.map(LogFormat.yesNo) ?? "unknown") + ", avatar \(avatar)"
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CoreUnanswered where error.reason == .cancelled {
                throw CancellationError()
            } catch {
                let issue: AccountRefreshResult.Issue = (error as? CoreUnanswered)?.needsSignIn == true
                    ? .signInRequired
                    : .unavailable
                issues[profile.id] = issue
                @Dependency(\.logger) var logger
                await logger.log(.diagnostic(
                    .accounts, .warning,
                    "Refreshing \(name) failed after \(LogFormat.milliseconds(start.duration(to: clock.now))) ms: "
                        + "\(LogFormat.error(error)); the account is marked "
                        + (issue == .signInRequired
                            ? "as needing sign-in"
                            : "unavailable")
                ))
            }
        }
        return issues
    }
    private static func saveDetails(
        of user: SignedInUser, for profile: AccountProfile, in resources: AccountResourceRepository
    ) async throws -> String {
        let now = Date()
        let details = ProfileDetails(
            onlineID: user.onlineID,
            avatarURL: user.avatarURL,
            isPlus: user.plusMember
        )
        try resources.cache(
            .profile, for: profile.id, payload: JSONEncoder().encode(details), now: now, ttl: 900
        )
        guard let url = user.avatarURL else {
            return "none on the profile"
        }
        let cached = try resources.cached(.avatar, for: profile.id)
        if let cached, cached.expiresAt > now, cached.sourceURL == url.absoluteString {
            return "from cache"
        }
        let image = try await avatar(at: url)
        try Task.checkCancellation()
        try resources.cache(
            .avatar, for: profile.id, payload: image, sourceURL: url.absoluteString, now: now, ttl: 86400
        )
        return "downloaded (\(LogFormat.size(image.count)))"
    }
    /// Downloads an account's avatar image and logs how the request went.
    ///
    /// - Parameter url: The avatar address; only plain HTTPS without credentials is accepted.
    /// - Returns: The image bytes.
    /// - Throws: `URLError(.unsupportedURL)` for any other address, `URLError(.badServerResponse)` when the
    ///   answer is not an image of at most two megabytes, the transport's `URLError`, or `CancellationError`.
    static func avatar(at url: URL) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil else {
            throw URLError(.unsupportedURL)
        }
        try Task.checkCancellation()
        @Dependency(\.network) var network
        @Dependency(\.logger) var logger
        let clock = ContinuousClock()
        let start = clock.now
        let host = url.host ?? "unknown host"
        let response: HTTPResponse
        do {
            response = try await network.send(URLRequest(url: url, timeoutInterval: 20), avatarLimit)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let elapsed = LogFormat.milliseconds(start.duration(to: clock.now))
            await logger.log(.diagnostic(
                .accounts, .warning,
                "PSN avatar image: GET \(host) failed after \(elapsed) ms with "
                    + "\(LogFormat.urlError((error as? URLError)?.errorCode)); no response received"
            ))
            throw error
        }
        try Task.checkCancellation()
        let elapsed = LogFormat.milliseconds(start.duration(to: clock.now))
        await logger.log(.diagnostic(
            .accounts,
            response.status == 200
                ? .debug
                : .warning,
            "PSN avatar image: GET \(host) answered HTTP \(response.status) in \(elapsed) ms "
                + "(\(LogFormat.size(response.body.count)))"
        ))
        guard response.status == 200,
              response.header("Content-Type")?.lowercased().hasPrefix("image/") == true
        else {
            throw URLError(.badServerResponse)
        }
        return response.body
    }

    private static let avatarLimit = 2_000_000

    private struct ProfileDetails: Encodable {
        let onlineID: String
        let avatarURL: URL?
        let isPlus: Bool?
    }
}
