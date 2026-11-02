import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiDiagnostics
import ChiakiModels
import Dependencies
import Foundation
import PlatformUI

extension SettingsClient: DependencyKey {
    /// The app's store, backed by the app database's settings and controls repositories, with the build's
    /// Takion versions from the core, outputs from the player, microphones from Core Audio and the request log
    /// from the core's HTTP log bridge.
    ///
    /// Most values are read and written under their `ChiakiModels/SettingKey`. Three values have side effects:
    /// logging settings reconfigure the log sink, Takion version settings log what was saved, and the controls
    /// configuration lives in its own table. Release builds offer no Takion controls, so they load the
    /// automatic defaults and ignore any choice a debug build saved. Discovery settings are checked by the core
    /// before they are written.
    public static let liveValue = Self(
        read: { type throws(PersistedSettingFailure) in
            try await read(type)
        },
        write: { value throws(PersistedSettingFailure) in
            try await write(value)
        },
        buildTakionVersion: { target in
            PlayBridge.builtProtocolVersion(target)
        },
        soundDevices: {
            SoundDevices(outputs: AudioOutputs.names(), inputs: MicrophoneInputDevices.names())
        },
        requestLogRevision: {
            HTTPCallsBridge().revision()
        },
        requestLog: {
            try await HTTPCallsBridge().log()
        },
        requestDetail: { exchange in
            await HTTPCallsBridge().detail(of: exchange)
        },
        clearRequestLog: {
            HTTPCallsBridge().clear()
        },
        resetRequestTotals: {
            HTTPCallsBridge().resetTotals()
        },
        coreBuild: {
            CoreSession.build
        }
    )

    private static func read<Value: PersistedSettingValue>(
        _: Value.Type
    ) async throws(PersistedSettingFailure) -> any PersistedSettingValue {
        @Dependency(\.logSettings) var logging
        do {
            if Value.self == LogSettings.self {
                return try await logging.load()
            }
            #if !DEBUG
                if Value.self == DeveloperSettings.self {
                    return DeveloperSettings()
                }
            #endif
            @Dependency(\.accountService) var accountService
            let repositories = try await accountService.storage()
            if Value.self == ControlsConfiguration.self {
                return try repositories.controls.configuration(ControlsConfiguration.self)?.validated()
                    ?? ControlsConfiguration()
            }
            return try repositories.settings.value(Value.settingKey)
        } catch {
            throw .unavailable
        }
    }

    private static func write<Value: PersistedSettingValue>(_ value: Value) async throws(
        PersistedSettingFailure
    ) {
        @Dependency(\.logSettings) var logging
        if let value = value as? DiscoverySettings {
            do {
                _ = try DiscoveryBridge().validated(value)
            } catch {
                throw .invalid
            }
        }
        do {
            if let value = value as? LogSettings {
                return try await logging.save(value)
            }
            @Dependency(\.accountService) var accountService
            let repositories = try await accountService.storage()
            if let value = value as? ControlsConfiguration {
                return try repositories.controls.save(value.validated())
            }
            try repositories.settings.save(value, for: Value.settingKey)
        } catch {
            throw .unavailable
        }
        if let value = value as? DeveloperSettings {
            await logTakionChoices(value)
        }
    }

    private static func logTakionChoices(_ value: DeveloperSettings) async {
        let summary = TakionTarget.allCases.map { target in
            let negotiation = value[negotiation: target]
                ? ", negotiation on"
                : ""
            let build = PlayBridge.builtProtocolVersion(target)
            return "\(target.title): \(DeveloperSettings.versionTitle(for: value[target], build: build))"
                + negotiation
        }.joined(separator: "; ")
        @Dependency(\.logger) var logger
        await logger.log(.diagnostic(.app, .info, "Takion version settings saved: " + summary))
    }
}
