import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation

extension ConsolesClient {
    /// The consoles over ``AccountService``, the core and a change broadcaster: pairs and unpairs through the
    /// process's open core, reads the saved pairings and edits consoles in the database and the core together,
    /// shares one local-network scan, asks PlayStation Network for an account's consoles, reads the saved
    /// launch console and wakes through the core, keeps the PINs in the app's database through wiping secret
    /// storage, and fetches and launches recently played titles through one service.
    ///
    /// A refused wake request throws `ChiakiModels/PlaybackFailure/wakeRefused`.
    ///
    /// - Parameters:
    ///   - service: The service that owns the open database.
    ///   - changes: Fans out reported pairing changes to observers.
    /// - Returns: The live client.
    public static func live(_ service: AccountService, changes: ConsoleCatalogChanges) -> ConsolesClient {
        ConsolesClient(
            pair: { account, target, pin, progress in
                await Self.pairThroughCore(account: account, target: target, pin: pin, progress: progress)
            },
            unpair: { account, console in
                await Self.unpairThroughCore(account: account, console: console)
            },
            pairings: {
                await Self.pairings(in: service)
            },
            pairingChanges: {
                changes.stream()
            },
            notePairingsChanged: {
                changes.post()
            },
            launchOptions: { console in
                do {
                    return try await .success(service.storage().consoleLaunch.options(of: console))
                } catch {
                    return .failure(.loadFailed)
                }
            },
            saveDraft: { draft in
                await Self.save(draft, through: service)
            },
            deleteConsole: { console in
                await Self.delete(console, from: service)
            },
            scanEvents: {
                await SharedConsoleScanner.shared.events()
            },
            accountConsoles: { account, ps5 in
                try await Self.accountConsoles(of: account, ps5: ps5)
            },
            launchConsole: {
                @Dependency(\.accountService) var accountService
                return try await accountService.storage().consoleLaunch.launchConsole()
            },
            wake: { account, target, address in
                try await Self.wake(account: account, target: target, address: address)
            },
            loginPIN: { owner in
                try await Self.loginPIN(of: owner)
            },
            saveLoginPIN: { owner, code in
                var digits = Array(code.digits.utf8)
                @Dependency(\.accountService) var accountService
                try await accountService.storage().consoleLaunch
                    .saveLoginPIN(
                        SecretBytes(wiping: &digits),
                        console: owner.consoleID,
                        profile: owner.accountID
                    )
            },
            clearLoginPIN: { owner in
                @Dependency(\.accountService) var accountService
                try await accountService.storage().consoleLaunch
                    .clearLoginPIN(console: owner.consoleID, profile: owner.accountID)
            },
            recentlyPlayed: { account in
                try await Self.recentlyPlayedService.fetch(account: account)
            },
            launchTitle: { account, hardwareID, title in
                try await Self.recentlyPlayedService.launch(
                    account: account,
                    hardwareID: hardwareID,
                    title: title
                )
            },
            artLayers: { account, concept in
                @Dependency(\.catalog) var catalog
                return await ConsoleArtOpening(catalog: catalog).layers(account: account, concept: concept)
            }
        )
    }

    private static let recentlyPlayedService = RecentlyPlayedService.live()

    private static func pairings(
        in service: AccountService
    ) async -> Result<[RegisteredConsole], ConsoleCatalogFailure> {
        do {
            return try await .success(service.storage().consoles.registeredConsoles())
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .registration, .error,
                "Reading the saved console pairings failed: \(LogFormat.error(error))"
            ))
            return .failure(.unavailable)
        }
    }

    private static func save(
        _ draft: ConsoleDraft,
        through service: AccountService
    ) async -> ConsoleEditFailure? {
        let failure = await ConsoleEditTransaction.live(service).commit(draft)
        if failure != nil {
            @Dependency(\.logger) var logger
            await logger.log(.consoleWarning(
                "Saving console \(LogFormat.idPrefix(draft.id)) failed; the database and the core keep "
                    + "the values from before the edit"
            ))
        }
        return failure
    }

    private static func delete(_ console: UUID, from service: AccountService) async -> ConsoleEditFailure? {
        do {
            let repositories = try await service.storage()
            let hardware = try repositories.consoles.hardwareID(of: console)
            try repositories.consoles.delete(console)
            if let hardware {
                ConsoleBridge().forget(hardware)
            }
            return nil
        } catch {
            return .deleteFailed
        }
    }

    private static func accountConsoles(of account: UUID, ps5: Bool) async throws -> [PSNConsole] {
        @Dependency(\.accountService) var accountService
        guard let profile = try await accountService.storage().accounts.list()
            .first(where: { $0.id == account })
        else {
            throw RegistrationFailure.unavailable
        }
        @Dependency(\.logger) var logger
        return try await PSNConsoleClient.logged(logger).list(profile.accountID.data, ps5)
    }

    private static func wake(
        account: UUID,
        target: RegistrationFlow.ConsoleTarget,
        address: String
    ) async throws {
        @Dependency(\.accountService) var accountService
        let repositories = try await accountService.storage()
        let console = try repositories.consoles.playTarget(
            profile: account, address: target.address, remoteDeviceID: target.remoteDeviceID
        )
        let name = target.name ?? target.address
        do {
            try ConsoleBridge().wake(console.hardwareID, as: console.accountID)
        } catch {
            let refusal = error
            @Dependency(\.logger) var logger
            await logger.log(.consoleWarning(
                "Auto-connect: the wake request to \"\(name)\" at \(address) was refused (\(refusal))"
            ))
            throw PlaybackFailure.wakeRefused
        }
        @Dependency(\.logger) var logger
        await logger.log(.consoleDiagnostic(
            "Auto-connect: sent a wake request to \"\(name)\" at \(address)"
        ))
    }

    private static func loginPIN(of owner: LoginPINOwner) async throws -> StreamAccessCode? {
        @Dependency(\.accountService) var accountService
        let pin = try await accountService.storage().consoleLaunch
            .loginPIN(console: owner.consoleID, profile: owner.accountID)
        switch consume pin {
        case .some(let secret):
            return secret.withUnsafeBytes {
                String(bytes: $0, encoding: .utf8)
            }
            .flatMap(StreamAccessCode.init)
        case .none:
            return nil
        }
    }

    private static func unpairThroughCore(
        account: UUID,
        console: RegistrationFlow.ConsoleTarget
    ) async -> Result<Void, PairingFailure> {
        @Dependency(\.accountService) var accountService
        do {
            let target = try await accountService.storage().consoles.playTarget(
                profile: account,
                address: console.address,
                remoteDeviceID: console.remoteDeviceID
            )
            try ConsoleBridge().unpair(target.accountID, from: target.hardwareID)
            return .success(())
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .registration, .error, "The pairing could not be removed: \(LogFormat.error(error))"
            ))
            return .failure(.unavailable)
        }
    }

    /// Validates a request and pairs it through the open core.
    ///
    /// - Parameters:
    ///   - account: The account the pairing is for.
    ///   - target: The console and how it is reached.
    ///   - pin: The PIN for a home target; `nil` for an internet target.
    ///   - progress: Receives each step the attempt reports.
    /// - Returns: The paired console, or `ChiakiModels/PairingFailure/invalidInput` before anything is sent
    ///   when the request does not validate, or the failure that ended the attempt.
    static func pairThroughCore(
        account: AccountID,
        target: PairingTarget,
        pin: String?,
        progress: @escaping @Sendable (PairingProgress) -> Void
    ) async -> Result<PairedConsole, PairingFailure> {
        let request: PairingRequest
        do {
            request = try PairingRequest(account: account, target: target, pin: validated(pin))
        } catch {
            return .failure(error)
        }
        do {
            return try await .success(PairingBridge().pair(request, progress: progress))
        } catch {
            return .failure(error)
        }
    }

    private static func validated(_ pin: String?) throws(PairingFailure) -> PairingPIN? {
        guard let pin else {
            return nil
        }
        guard let checked = PairingPIN(pin) else {
            throw .invalidInput
        }
        return checked
    }
}
