import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import Foundation
import LocalAuthentication

/// The Tokens settings panel's view of the accounts: the credentials each signed-in account holds, the device
/// owner's consent and the secrets the core reveals.
enum AccountTokens {
    /// Lists the saved accounts the core knows a PlayStation Network sign-in for, with their held credentials.
    ///
    /// - Parameter service: The service that owns the open database.
    /// - Returns: The accounts.
    /// - Throws: The error ``AccountService/storage()`` throws.
    static func accounts(through service: AccountService) async throws -> [TokenAccount] {
        try await service.storage().accounts.list().compactMap { profile in
            guard UsersBridge().find(profile.accountID)?.hasPSNAccount == true,
                  let credentials = CredentialsBridge().held(by: profile.accountID) else {
                return nil
            }
            return TokenAccount(
                id: profile.id, name: profile.onlineID ?? profile.name, accountID: profile.accountID.data,
                credentials: credentials
            )
        }
    }

    /// Asks the device owner to authenticate with the device owner policy, dismissing the prompt when
    /// cancelled.
    ///
    /// - Parameter reason: Why the app asks, shown in the prompt.
    /// - Returns: Whether the owner authenticated.
    static func authenticate(_ reason: String) async -> Bool {
        let prompt = DeviceOwnerPrompt()
        return await withTaskCancellationHandler {
            await prompt.ask(reason)
        } onCancel: {
            prompt.dismiss()
        }
    }

    /// Asks the core for one credential's secret.
    ///
    /// - Parameters:
    ///   - account: The account's identifier bytes.
    ///   - kind: The credential kind.
    /// - Returns: The secret, or why it cannot be revealed.
    static func reveal(_ account: Data, kind: CredentialKind) -> Result<RevealedSecret, NotRevealed> {
        guard let id = AccountID(bytes: account) else {
            return .failure(NotRevealed(.unknownUser))
        }
        do throws(NotRevealed) {
            return try .success(CredentialsBridge().reveal(kind, of: id))
        } catch {
            return .failure(error)
        }
    }
}

/// Asks the device owner to authenticate, and can withdraw the question.
private final class DeviceOwnerPrompt: @unchecked Sendable {
    private let context = LAContext()

    /// Asks the device owner to authenticate.
    ///
    /// - Parameter reason: Why the app asks, shown in the prompt.
    /// - Returns: Whether the owner authenticated.
    func ask(_ reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Withdraws the prompt.
    func dismiss() {
        context.invalidate()
    }
}
