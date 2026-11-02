#if CHIAKI_KAKUSAN
    import enum ChiakiBridge.chiaki_bridge
    import enum ChiakiBridge.libchiaking
    import ChiakiCoreBridge
    import ChiakiModels
    import ChiakiPersistence
    import Foundation
    import Testing

    extension CoreSessionSuites {
        @Suite struct DeviceStoreAdapterTests {
            @Test func theCoreSavesThisDevicesIdentityAndKeepsItAcrossARestart() throws {
                let harness = try CoreSessionHarness()
                defer {
                    harness.remove()
                }
                let first = try harness.open()
                let created = try first.kakusanDevices.thisDevice()
                first.close()
                let saved = try harness.repositories.devices.identity()
                #expect(saved.map { Data($0.key.bytes) } == created.publicKey.bytes)

                let second = try harness.open()
                defer {
                    second.close()
                }
                let reopened = try second.kakusanDevices.thisDevice()
                #expect(reopened.publicKey == created.publicKey)
            }

            @Test func rememberedDevicesReachTheCoreAndForgettingRemovesTheRow() throws {
                let harness = try CoreSessionHarness()
                defer {
                    harness.remove()
                }
                let key = try #require(DeviceIdentityKey(bytes: [UInt8](repeating: 0x21, count: 32)))
                let fingerprint = try #require(DeviceKeyFingerprint(bytes: [UInt8](
                    repeating: 0x22,
                    count: 32
                )))
                try harness.repositories.devices.save(RememberedDevice(
                    key: key,
                    fingerprint: fingerprint,
                    nickname: "Alex",
                    firstVerified: Date(timeIntervalSince1970: 1000),
                    lastSeen: Date(timeIntervalSince1970: 2000)
                ))
                let session = try harness.open()
                defer {
                    session.close()
                }
                let peers = try session.kakusanDevices.peers()
                #expect(peers.map(\.nickname) == ["Alex"])
                #expect(peers.map(\.publicKey.bytes) == [Data(key.bytes)])
                let publicKey = try #require(KakusanPublicKey(Data(key.bytes)))
                #expect(session.kakusanDevices.forget(publicKey))
                #expect(try harness.repositories.devices.rememberedDevices().isEmpty)
            }
        }
    }
#endif
