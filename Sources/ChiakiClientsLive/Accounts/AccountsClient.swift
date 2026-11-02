import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import ComposableArchitecture
import Foundation

extension AccountsClient {
    /// The client over ``AccountService``, logging every account operation and how long it took, with the
    /// credentials read through the core. The web sign-in capture is left to the app, which shows the page.
    ///
    /// - Parameter service: The service that owns the open database and core.
    /// - Returns: The live client.
    public static func live(_ service: AccountService) -> AccountsClient {
        AccountsClient(
            load: {
                await timed("Loading saved accounts", failure: AccountsFailure.loadFailed) {
                    try await service.load()
                } describe: { accounts in
                    "loaded \(accounts.count) saved " + (accounts.count == 1
                        ? "account"
                        : "accounts") + (accounts.isEmpty
                        ? ""
                        : ": " + accounts.map(describe).joined(separator: ", "))
                }
            },
            addAccountID: { profile, name, account in
                await timed(
                    "Adding account \(LogFormat.idPrefix(profile)) by account ID",
                    failure: AccountsFailure.saveFailed
                ) {
                    try await service.addAccountID(profile: profile, name: name, account: account)
                } describe: { saved in
                    "saved \(describe(saved))"
                }
            },
            signIn: { profile, capture in
                await signIn(profile, capture: capture, through: service)
            },
            signInWithQR: { profile, progress in
                await signInWithQR(profile, progress: progress, through: service)
            },
            delete: { profile in
                let result = await timed(
                    "Deleting account \(LogFormat.idPrefix(profile))",
                    failure: AccountsFailure.deleteFailed
                ) {
                    try await service.delete(profile)
                    return profile
                } describe: { _ in
                    "deleted account \(LogFormat.idPrefix(profile)) with its tokens, registrations and cached profile"
                }
                if case .failure(let failure) = result {
                    return failure
                }
                return nil
            },
            refresh: {
                do {
                    return try await .success(service.refresh())
                } catch {
                    return .failure(.refreshFailed)
                }
            },
            selectedAccount: {
                try? await service.storage().settings.value(SettingKeys.activeAccount)
            },
            selectAccount: { profile in
                await remember(profile, through: service)
            },
            tokenAccounts: {
                try await AccountTokens.accounts(through: service)
            },
            authenticateOwner: { reason in
                await AccountTokens.authenticate(reason)
            },
            revealToken: { account, kind in
                AccountTokens.reveal(account, kind: kind)
            }
        )
    }

    private static func signIn(
        _ profile: UUID,
        capture: consuming SignInCapture,
        through service: AccountService
    ) async -> Result<AccountProfile, SignInFailure> {
        let clock = ContinuousClock()
        let start = clock.now
        let result: Result<AccountProfile, SignInFailure>
        do throws(SignInFailure) {
            result = try await .success(service.signIn(profile: profile, capture: capture))
        } catch {
            result = .failure(error)
        }
        await report(result, of: profile, method: "the sign-in page", after: start.duration(to: clock.now))
        return result
    }

    private static func signInWithQR(
        _ profile: UUID,
        progress: @escaping @Sendable (QRSignInProgress) -> Void,
        through service: AccountService
    ) async -> Result<AccountProfile, SignInFailure> {
        let clock = ContinuousClock()
        let start = clock.now
        let result: Result<AccountProfile, SignInFailure>
        do throws(SignInFailure) {
            result = try await .success(service.signInWithQR(profile: profile, progress: progress))
        } catch {
            result = .failure(error)
        }
        await report(result, of: profile, method: "a QR code", after: start.duration(to: clock.now))
        return result
    }

    private static func report(
        _ result: Result<AccountProfile, SignInFailure>,
        of profile: UUID,
        method: String,
        after duration: Duration
    ) async {
        let elapsed = LogFormat.milliseconds(duration)
        @Dependency(\.logger) var logger
        switch result {
        case .success(let saved):
            await logger.log(.diagnostic(
                .accounts,
                .info,
                "saved \(describe(saved)) in \(elapsed) ms"
            ))
        case .failure(let failure):
            await logger.log(.diagnostic(
                .accounts, .error,
                "Signing in account \(LogFormat.idPrefix(profile)) with \(method) failed after \(elapsed) ms: "
                    + "\(failure)"
            ))
        }
    }

    private static func remember(_ profile: UUID, through service: AccountService) async -> Bool {
        do {
            try await service.storage().settings.save(profile, for: SettingKeys.activeAccount)
            return true
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .accounts, .warning,
                "Couldn’t remember the active account \(LogFormat.idPrefix(profile))"
            ))
            return false
        }
    }

    private static func describe(_ profile: AccountProfile) -> String {
        let name = profile.onlineID ?? profile.name
        let plus = profile.isPlus.map {
            $0
                ? ", PS Plus"
                : ", no PS Plus"
        } ?? ""
        let account = LogFormat.hexPrefix(profile.accountID.data, bytes: 2)
        return "\"\(name)\" (id \(LogFormat.idPrefix(profile.id)), PSN account \(account), "
            + "\(profile.method.rawValue)\(plus))"
    }

    private static func timed<T: Sendable>(
        _ action: String,
        failure: AccountsFailure,
        operation: @Sendable () async throws -> T,
        describe: @Sendable (T) -> String
    ) async -> Result<T, AccountsFailure> {
        let clock = ContinuousClock()
        let start = clock.now
        @Dependency(\.logger) var logger
        do {
            let result = try await operation()
            let elapsed = LogFormat.milliseconds(start.duration(to: clock.now))
            await logger.log(.diagnostic(.accounts, .info, "\(describe(result)) in \(elapsed) ms"))
            return .success(result)
        } catch {
            let elapsed = LogFormat.milliseconds(start.duration(to: clock.now))
            await logger.log(.diagnostic(
                .accounts, .error,
                "\(action) failed after \(elapsed) ms: \(reason(error))"
            ))
            return .failure(failure)
        }
    }

    private static func reason(_ error: Error) -> String {
        switch error {
        case let failure as PersistenceError:
            "storage failed with \(failure) (database or Keychain)"
        default:
            LogFormat.error(error)
        }
    }
}
