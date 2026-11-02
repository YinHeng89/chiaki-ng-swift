import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import ChiakiPersistence
import Dependencies
import Foundation

extension KakusanClient: DependencyKey {
    #if CHIAKI_KAKUSAN
        /// Kakusan through the core: session operations through ``KakusanDesks``, devices through the core's
        /// device store, the guest's stream through the app's `ChiakiClients/StreamSessionClient` and the
        /// preferences in the app's settings store.
        public static let liveValue = KakusanClient(
            useStunServers: { servers in
                KakusanDevicesBridge().useStunServers(servers)
            },
            arm: { configuration, events in
                await KakusanDesks().arm(configuration, events)
            },
            disarm: {
                await KakusanDesks().disarm()
            },
            invite: {
                await KakusanDesks().invite()
            },
            importReply: { block in
                await KakusanDesks().importReply(block)
            },
            send: { command in
                await KakusanDesks().send(command)
            },
            preview: { block in
                KakusanDevicesBridge().preview(block)
            },
            enterCode: { code in
                await KakusanDesks().enterCode(code)
            },
            identity: {
                try KakusanDevicesBridge().thisDevice()
            },
            peers: {
                try KakusanDevicesBridge().peers().sorted {
                    ($0.lastSeenAt, $1.nickname) > ($1.lastSeenAt, $0.nickname)
                }
            },
            recognize: { key, nickname in
                KakusanDevicesBridge().recognize(key, expecting: nickname)
            },
            remember: { peer, nickname, replacing in
                try await KakusanDesks().remember(peer, nickname, replacing: replacing)
            },
            rename: { key, nickname in
                try KakusanDevicesBridge().rename(key, to: nickname)
            },
            forget: { key in
                guard KakusanDevicesBridge().forget(key) else {
                    throw KakusanError.internal
                }
            },
            nickname: { typed in
                KakusanDevicesBridge().normalisedNickname(typed)
            },
            playGuest: { session, configuration, handler in
                @Dependency(\.streamSession) var streamSession
                do {
                    for try await event in streamSession.start(
                        StreamSessionID(uuid: session),
                        .guest(configuration)
                    ) {
                        switch event {
                        case .presented(let surface):
                            await handler(.presented(surface))
                        case .guest(let event):
                            await handler(event)
                        default:
                            break
                        }
                    }
                } catch let failure as StreamFailure {
                    if case .kakusan(let error) = failure {
                        throw error
                    }
                    throw KakusanError.internal
                }
            },
            stopGuest: {
                @Dependency(\.streamLeases) var streamLeases
                let leases = streamLeases
                _ = await leases.stop()
            },
            loadSettings: {
                @Dependency(\.accountService) var accountService
                return try await accountService.storage().settings.value(SettingKeys.kakusan)
            },
            saveSettings: { value in
                @Dependency(\.accountService) var accountService
                return try await accountService.storage().settings.save(value, for: SettingKeys.kakusan)
            }
        )
    #else
        /// Kakusan left out of this build: every operation answers as
        /// `ChiakiClients/KakusanClient/unavailable` does.
        public static let liveValue = KakusanClient.unavailable
    #endif
}
