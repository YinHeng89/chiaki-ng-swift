import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import ChiakiPersistence
import ComposableArchitecture
import Foundation

extension ConsoleEditTransaction {
    /// The transaction over ``AccountService`` and the core: reads and writes the console's saved settings in
    /// the database and tells the core its name and address.
    ///
    /// - Parameter service: The service that owns the open database.
    /// - Returns: The live transaction.
    static func live(_ service: AccountService) -> ConsoleEditTransaction {
        ConsoleEditTransaction(
            read: { console in
                let repositories = try await service.storage()
                guard let saved = try repositories.consoles.registeredConsoles()
                    .first(where: { $0.id == console })
                else {
                    throw PersistenceError.invalidInput
                }
                let options = try repositories.consoleLaunch.options(of: console)
                return .init(
                    name: saved.name,
                    address: saved.address,
                    connectAtLaunch: options.connectAtLaunch
                )
            },
            write: { console, name, address, connectAtLaunch, forgetLoginPIN in
                try await service.storage().consoleLaunch.update(
                    console,
                    name: name,
                    address: address,
                    connectAtLaunch: connectAtLaunch,
                    forgetLoginPIN: forgetLoginPIN
                )
            },
            applyToCore: { console, name, address in
                let hardware: HardwareID?
                do {
                    hardware = try await service.storage().consoles.hardwareID(of: console)
                } catch {
                    return false
                }
                guard let hardware else {
                    return true
                }
                return ConsoleBridge().rename(hardware, to: name)
                    && ConsoleBridge().move(hardware, to: address)
            }
        )
    }
}

/// Saves a console edit to the database and the core so that they never disagree.
///
/// The database is written first, without forgetting the login PIN. Only when that succeeds is the core told
/// the new name and address. When the core refuses, the database is put back to the values read before the
/// edit. The login PIN, which cannot be restored, is forgotten last, once both sides agree.
struct ConsoleEditTransaction: Sendable {
    /// A console's settings as saved before an edit.
    struct Saved: Equatable, Sendable {
        /// The saved name.
        let name: String

        /// The saved address.
        let address: String

        /// Whether the console connects at launch.
        let connectAtLaunch: Bool
    }

    /// Reads a console's saved settings.
    let read: @Sendable (_ console: UUID) async throws -> Saved

    /// Writes a console's settings, forgetting its login PIN when asked.
    let write: @Sendable (
        _ console: UUID,
        _ name: String,
        _ address: String,
        _ connectAtLaunch: Bool,
        _ forgetLoginPIN: Bool
    ) async throws -> Void

    /// Tells the core a console's name and address; returns whether the core accepted them.
    let applyToCore: @Sendable (_ console: UUID, _ name: String, _ address: String) async -> Bool

    /// Saves a draft.
    ///
    /// - Parameter draft: The edited console.
    /// - Returns: `nil` when the database and the core both hold the draft, or
    ///   `ChiakiModels/ConsoleEditFailure/saveFailed` when the draft does not validate or either side
    ///   refused; after a refusal both sides hold the values from before the edit.
    func commit(_ draft: ConsoleDraft) async -> ConsoleEditFailure? {
        guard let name = draft.validName, let address = draft.validAddress?.text else {
            return .saveFailed
        }
        let saved: Saved
        do {
            saved = try await read(draft.id)
            try await write(draft.id, name, address, draft.connectAtLaunch, false)
        } catch {
            return .saveFailed
        }
        guard await applyToCore(draft.id, name, address) else {
            try? await write(draft.id, saved.name, saved.address, saved.connectAtLaunch, false)
            return .saveFailed
        }
        guard draft.loginPIN == .forgotten else {
            return nil
        }
        do {
            try await write(draft.id, name, address, draft.connectAtLaunch, true)
        } catch {
            return .saveFailed
        }
        return nil
    }
}
