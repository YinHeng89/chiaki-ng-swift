import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation
import PlatformUI

/// Reads and writes the account's stored console, cloud and sound settings for the stream menu's tuning.
enum StreamTuning {
    /// Reads the saved picture and sound settings for a stream context into a tuning configuration.
    ///
    /// - Parameter context: The kind of stream.
    /// - Returns: The configuration.
    /// - Throws: The error the settings storage throws.
    static func load(_ context: StreamTuningContext) async throws -> StreamTuningConfiguration {
        @Dependency(\.accountService) var accountService
        let sound = (try? await accountService.storage().settings.value(SettingKeys.sound)) ??
            SoundSettings()
        switch context {
        case let .console(route, ps5):
            let value = try await accountService.storage().settings.value(SettingKeys.picture)
            let profile = value.profile(for: route, ps5: ps5)
            return StreamTuningConfiguration(
                presentationFrameRate: value.presentationFrameRate,
                upscaledOutput: profile.upscaledOutput,
                upscaler: value.upscaler,
                nativeHeight: profile.height,
                sourceFPS: profile.fps,
                frameGenerationAvailable: [720, 1080].contains(profile.height),
                hdrRequested: value.launchCodec(
                    forPS5: ps5,
                    route: route,
                    displaySupportsHDR: await DisplayDynamicRange.supportsHDR
                ) == .hevcHDR,
                videoFit: value.videoFit,
                adjustments: value.adjustments,
                reduceBanding: value.reduceBanding,
                volume: sound.volume,
                spatialAudio: sound.spatialAudio,
                audio3DAvailable: Self.audio3DAvailable(context),
                launch: .console(value, route: route, ps5: ps5),
                launchOptions: .console(ps5: ps5)
            )
        case .cloud(let service):
            let value = try await accountService.storage().settings.value(SettingKeys.cloudPicture)
            let height = value.height(for: service)
            return StreamTuningConfiguration(
                presentationFrameRate: value.presentationFrameRate,
                upscaledOutput: value.output(for: service),
                upscaler: value.upscaler,
                nativeHeight: height,
                frameGenerationAvailable: [720, 1080].contains(height),
                videoFit: value.videoFit,
                adjustments: value.adjustments,
                reduceBanding: value.reduceBanding,
                volume: sound.volume,
                chatVolume: service == "pscloud"
                    ? nil
                    : sound.chatVolume,
                spatialAudio: sound.spatialAudio,
                audio3DAvailable: Self.audio3DAvailable(context),
                launch: .cloud(value, service: service),
                launchOptions: .cloud(service)
            )
        case .guest:
            return StreamTuningConfiguration(
                volume: sound.volume,
                spatialAudio: sound.spatialAudio,
                audio3DAvailable: Self.audio3DAvailable(context)
            )
        }
    }

    /// Writes a tuning configuration back to the sound settings and the context's picture settings.
    ///
    /// - Parameters:
    ///   - context: The kind of stream.
    ///   - configuration: The tuning to save.
    /// - Throws: The error the settings storage throws.
    static func save(
        _ context: StreamTuningContext,
        _ configuration: StreamTuningConfiguration
    ) async throws {
        @Dependency(\.accountService) var accountService
        if let saved = try? await accountService.storage().settings.value(SettingKeys.sound),
           let sound = Self.sound(saved, tunedBy: configuration) {
            try await accountService.storage().settings.save(sound, for: SettingKeys.sound)
        }
        switch context {
        case let .console(route, ps5):
            var value = try await accountService.storage().settings.value(SettingKeys.picture)
            value = configuration.launch.applied(to: value, route: route, ps5: ps5)
            value.presentationFrameRate = configuration.presentationFrameRate
            value[route].upscaledOutput = configuration.upscaledOutput
            value.upscaler = configuration.upscaler
            value.videoFit = configuration.videoFit
            value.adjustments = configuration.adjustments
            value.reduceBanding = configuration.reduceBanding
            try await accountService.storage().settings.save(
                value.normalized(),
                for: SettingKeys.picture
            )
        case .cloud(let service):
            var value = try await accountService.storage().settings.value(SettingKeys.cloudPicture)
            value = configuration.launch.applied(to: value, service: service)
            value.presentationFrameRate = configuration.presentationFrameRate
            if service == "pscloud" {
                value.upscaledOutput = configuration.upscaledOutput
            } else {
                value.psNowUpscaledOutput = configuration.upscaledOutput
            }
            value.upscaler = configuration.upscaler
            value.videoFit = configuration.videoFit
            value.adjustments = configuration.adjustments
            value.reduceBanding = configuration.reduceBanding
            try await accountService.storage().settings.save(
                value.normalized(),
                for: SettingKeys.cloudPicture
            )
        case .guest:
            break
        }
    }

    /// Whether the core plays the console's 3D audio for a stream.
    ///
    /// - Parameter context: The kind of stream.
    /// - Returns: `false` for a guest and for targets the core gives no 3D audio.
    static func audio3DAvailable(_ context: StreamTuningContext) -> Bool {
        context.soundTarget.map(PlayBridge.supportsAudio3D) ?? false
    }

    /// Applies a tuning configuration's volume, party chat volume and spatial audio to saved sound settings.
    /// - Parameters:
    ///   - saved: The sound settings currently stored.
    ///   - configuration: The tuning whose sound values to apply.
    /// - Returns: The normalized settings to store, or `nil` when nothing would change.
    static func sound(_ saved: SoundSettings, tunedBy configuration: StreamTuningConfiguration)

        -> SoundSettings? {
        var sound = saved
        sound.volume = configuration.volume
        if let chatVolume = configuration.chatVolume {
            sound.chatVolume = chatVolume
        }
        sound.spatialAudio = configuration.spatialAudio
        let normalized = sound.normalized()
        guard normalized != saved else {
            return nil
        }
        return normalized
    }
}
