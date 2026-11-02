import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation
import Video

/// Loads the saved settings every stream launcher applies, falling back where a stream can still start.
///
/// A launcher builds one from the `\.settings` it was launched with and threads it through its tasks.
struct StreamSettingsLoader: Sendable {
    /// Where the settings are read from.
    let settings: SettingsClient

    /// The saved sound settings, or the defaults when they cannot be read.
    ///
    /// - Returns: The sound settings.
    func sound() async -> SoundSettings {
        do {
            return try await settings.load(SoundSettings.self)
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .playback, .warning,
                "Saved sound settings could not be loaded (\(LogFormat.error(error))); the system default output "
                    + "is used at full volume"
            ))
            return SoundSettings()
        }
    }

    /// The saved PlayStation accessibility settings, or settings that follow the device when they cannot be
    /// read, so an optional preference never stops a cloud launch.
    ///
    /// - Returns: The PlayStation accessibility settings.
    func playStationAccessibility() async -> PlayStationAccessibilitySettings {
        do {
            return try await settings.load(PlayStationAccessibilitySettings.self)
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .cloud, .warning,
                "PlayStation accessibility preferences could not be read (\(LogFormat.error(error))); using "
                    + "device defaults"
            ))
            return PlayStationAccessibilitySettings()
        }
    }

    /// Whether a console stream whose connection drops connects again, or `true`, the default, when the console
    /// power settings cannot be read.
    ///
    /// - Returns: Whether to reconnect.
    func reconnectsAfterDrop() async -> Bool {
        do {
            return try await settings.load(ConsolePowerSettings.self).reconnectAfterDrop
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .playback, .warning,
                "Saved console power settings could not be loaded (\(LogFormat.error(error))); a dropped stream "
                    + "reconnects"
            ))
            return true
        }
    }

    /// The saved console picture settings.
    ///
    /// - Returns: The picture settings.
    /// - Throws: `ChiakiModels/StreamFailure/settingsUnavailable` when they cannot be read.
    func picture() async throws(StreamFailure) -> PictureSettings {
        do {
            return try await settings.load(PictureSettings.self).validated()
        } catch {
            throw .settingsUnavailable
        }
    }

    /// The saved cloud picture settings.
    ///
    /// - Returns: The cloud picture settings.
    /// - Throws: `ChiakiModels/StreamFailure/settingsUnavailable` when they cannot be read.
    func cloudPicture() async throws(StreamFailure) -> CloudPictureSettings {
        do {
            return try await settings.load(CloudPictureSettings.self).validated()
        } catch {
            throw .settingsUnavailable
        }
    }

    /// The saved controller settings.
    ///
    /// - Returns: The controls.
    /// - Throws: `ChiakiModels/StreamFailure/inputConfiguration` when they cannot be read.
    func controls() async throws(StreamFailure) -> ControlsConfiguration {
        do {
            return try await settings.load(ControlsConfiguration.self)
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .playback, .error,
                "Saved controller settings could not be loaded (\(LogFormat.error(error))); the stream was not "
                    + "started [code 3901]"
            ))
            throw .inputConfiguration
        }
    }

    /// Applies the saved internet connection settings to a player.
    ///
    /// - Parameter player: The native player.
    @MainActor
    func configureInternetConnection(_ player: CNLiveVideoPlayer) async {
        let connection: InternetConnectionSettings
        do {
            connection = try await settings.load(InternetConnectionSettings.self)
        } catch {
            @Dependency(\.logger) var logger
            await logger.log(.diagnostic(
                .playback, .warning,
                "Saved Internet connection settings could not be loaded (\(LogFormat.error(error))); "
                    + "port guessing stays automatic"
            ))
            connection = InternetConnectionSettings()
        }
        player.setPortGuessingForced(
            connection.forcePortGuessing,
            count: UInt32(clamping: connection.portGuessCount)
        )
    }
}
