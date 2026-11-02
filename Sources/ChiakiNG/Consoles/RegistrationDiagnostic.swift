import ChiakiClients
import ChiakiClientsLive
import ChiakiDiagnostics
import ChiakiFeatures
import ChiakiModels
import Dependencies
import Foundation

/// The command-line check that pairs the only PSN console of the only signed-in account.
public enum RegistrationDiagnostic {
    /// Pairs the console over the internet and describes the outcome.
    ///
    /// - Returns: One line for the terminal.
    public static func run() async -> String {
        do {
            @Dependency(\.accountService) var accountService
            let repository = try await accountService.storage()
            let accounts = try repository.accounts.list().filter {
                $0.method == .npsso
            }
            guard accounts.count == 1, let account = accounts.first else {
                return "Select an account in the app; diagnostic selection is ambiguous."
            }
            let accountID = account.accountID
            @Dependency(\.logger) var logger
            let devices = try await PSNConsoleClient.logged(logger).list(accountID.data, true)
            guard devices.count == 1, let console = devices.first,
                  let uid = ConsoleDeviceUID(bytes: console.deviceID)
            else {
                return "Select a console in the app; diagnostic selection is ambiguous."
            }
            let target = PairingTarget.overInternet(AccountConsoleTarget(
                deviceUID: uid,
                name: console.name,
                kind: .ps5
            ))
            @Dependency(\.consoles) var consoles
            switch await consoles.pair(accountID, target, nil, { _ in
            }) {
            case .success:
                return "Registration succeeded and credentials were saved."
            case .failure(let failure):
                return PairingFailureMessage.text(for: failure)
            }
        } catch let error as RegistrationFailure {
            return RegistrationFailureMessage.text(for: error)
        } catch {
            return "Registration diagnostic failed before native registration."
        }
    }
}
