import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation

/// Asks the core for a game's details and loads its layered art, logging how long each part took.
struct ConsoleArtOpening: Sendable {
    /// Downloads and decodes the art layers.
    var catalog: CatalogClient

    /// Fetches the layered art of a game concept.
    ///
    /// - Parameters:
    ///   - account: The account whose PSN identity asks for the details.
    ///   - concept: The game's concept id.
    /// - Returns: The decoded layers, or `nil` when the account is missing, the details are not answered, the
    ///   game has no layered art or a layer fails, in which case the card shows its plain tile.
    func layers(account: UUID, concept: String) async -> GameArtLayers? {
        let clock = ContinuousClock()
        let start = clock.now
        @Dependency(\.accountService) var accountService
        guard let bytes = try? await accountService.accountID(of: account) else {
            return nil
        }
        let answer = await TitleChecksBridge().details(account: bytes, conceptID: concept)
        let asked = "details \(LogFormat.milliseconds(start.duration(to: clock.now))) ms"
        switch answer {
        case .failure(let failure):
            await log("Console art \(concept): \(asked), not answered (\(failure.reason)), showing the tile")
            return nil
        case .success(let details):
            guard let art = details.layeredArt else {
                await log("Console art \(concept): \(asked), no layered art, showing the tile")
                return nil
            }
            let layers = await catalog.artLayers(.layered(art))
            let outcome = layers == nil
                ? "a layer failed, showing the tile"
                : "layered card ready"
            await log(
                "Console art \(concept): \(asked), \(outcome) after "
                    + "\(LogFormat.milliseconds(start.duration(to: clock.now))) ms"
            )
            return layers
        }
    }

    private func log(_ message: String) async {
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(.recentlyPlayed, .info, message))
    }
}
