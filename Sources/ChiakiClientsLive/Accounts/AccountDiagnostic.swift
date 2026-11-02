import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation

/// The `--diagnose-account` run: renews the one saved PlayStation account and fetches its cloud catalog.
public enum AccountDiagnostic {
    /// Runs the diagnostic against the installed account service, in the injected locale.
    ///
    /// - Returns: The line printed for the run.
    public static func run() async -> String {
        @Dependency(\.accountService) var accountService
        @Dependency(\.locale) var locale
        var completed: [String] = []
        do {
            let repository = try await accountService.storage()
            let accounts = try repository.accounts.list().filter {
                $0.method == .npsso
            }
            guard accounts.count == 1, let account = accounts.first else {
                return "Account diagnostic requires exactly one saved PlayStation account."
            }
            let user = try await UsersBridge().refresh(account.accountID)
            completed.append("Sign-in renewal, profile and membership for \(user.onlineID)")
            if let url = user.avatarURL {
                _ = try await AccountDetailsRefresh.avatar(at: url)
                completed.append("Bounded avatar download")
            }
            let cloud = try await accountService.cloud()
            let snapshot = try await cloud.refresh(.init(
                accountID: account.id,
                locale: locale.identifier.replacingOccurrences(of: "_", with: "-")
            ))
            completed.append("Cloud catalog with \(snapshot.catalog.gameCount) games")
            return "PASS: " + completed.joined(separator: "; ")
        } catch let error as CoreUnanswered {
            return "Completed: " + completed.joined(separator: "; ") + ". Sign-in failed: \(error.reason)."
        } catch let error as CloudStatusFailure {
            return "Completed: " + completed.joined(separator: "; ") + ". Cloud failed: \(error.rawValue)."
        } catch {
            return "Completed: " + completed.joined(separator: "; ") + ". Account diagnostic failed."
        }
    }
}
