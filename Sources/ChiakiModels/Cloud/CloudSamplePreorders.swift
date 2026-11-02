import Foundation

/// Debug-only sample pre-orders mixed into the cloud library so release countdowns can be previewed without
/// real pre-orders.
public enum CloudSamplePreorders {
    /// The text every sample's product identifier contains, which marks a game as a sample.
    public static let identifierMarker = "SAMPLEPREORDER"

    /// Whether the developer preview setting for sample pre-orders is on; always `false` in release builds.
    public static var enabled: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: DeveloperPreviewSetting.samplePreorders)
        #else
            false
        #endif
    }

    /// Whether a game is one of the sample pre-orders, which cannot be played.
    ///
    /// - Parameter game: The game to test.
    /// - Returns: `true` when the game's identifier carries the sample marker.
    public static func isSample(_ game: CloudGame) -> Bool {
        game.id.contains(identifierMarker)
    }

    /// Puts the sample pre-orders at the front of a library snapshot, skipping any already present.
    ///
    /// - Parameters:
    ///   - snapshot: The library to add the samples to.
    ///   - now: The current time, which the scheduled samples count down from.
    /// - Returns: The library with the samples added.
    public static func adding(to snapshot: CloudLibrarySnapshot, now: Date) -> CloudLibrarySnapshot {
        let samples = [
            sample("UP9000-PPSA99001_00-SAMPLEPREORDER01", "Sample Pre-order Unlocking Soon",
                   .scheduled(now.addingTimeInterval(75))),
            sample("UP9000-PPSA99002_00-SAMPLEPREORDER02", "Sample Pre-order in Three Days",
                   .scheduled(now.addingTimeInterval(3 * 86400 + 4 * 3600 + 5 * 60))),
            sample("UP9000-PPSA99003_00-SAMPLEPREORDER03", "Sample Pre-order Without a Date", .unannounced)
        ]
        let existing = Set(snapshot.games.map(\.id))
        return CloudLibrarySnapshot(
            settledLocale: snapshot.settledLocale,
            games: samples.filter { !existing.contains($0.id) } + snapshot.games
        )
    }

    private static func sample(_ id: String, _ name: String, _ release: CloudReleaseDate) -> CloudGame {
        CloudGame(productId: id, name: name, isOwned: true, standing: .inLibrary, release: release)
    }
}
