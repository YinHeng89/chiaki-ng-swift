import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct KakusanDeviceRepositoryTests {
    static func key(_ byte: UInt8) throws -> DeviceIdentityKey {
        try #require(DeviceIdentityKey(bytes: [UInt8](repeating: byte, count: 32)))
    }

    static func fingerprint(_ byte: UInt8) throws -> DeviceKeyFingerprint {
        try #require(DeviceKeyFingerprint(bytes: [UInt8](repeating: byte, count: 32)))
    }

    static func identity(
        seed byte: UInt8,
        key: DeviceIdentityKey,
        fingerprint: DeviceKeyFingerprint
    ) throws -> StoredDeviceIdentity {
        var seed = [UInt8](repeating: byte, count: 32)
        let secret = SecretBytes(wiping: &seed)
        guard let identity = StoredDeviceIdentity(seed: secret, key: key, fingerprint: fingerprint) else {
            throw DeviceStoreFailure.unavailable
        }
        return identity
    }

    @Test func theIdentitySeedIsSealedAtRestAndComesBack() throws {
        let file = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        let keys = KeychainKeyStore(source: .memory())
        let repository = try KakusanDeviceRepository(database: AppDatabase(path: file.path, keys: keys))
        #expect(try repository.identity() == nil)
        let identity = try Self.identity(seed: 0x5C, key: Self.key(7), fingerprint: Self.fingerprint(8))
        try repository.save(identity)
        let reopened = try KakusanDeviceRepository(database: AppDatabase(path: file.path, keys: keys))
        let reloaded = try reopened.identity()
        let loaded = try #require(reloaded)
        #expect(loaded.key == (try Self.key(7)))
        let sameSeed = loaded.seed.isEqual(to: identity.seed)
        #expect(sameSeed)
        #expect(try Data(contentsOf: file).range(of: Data(repeating: 0x5C, count: 32)) == nil)
        let withoutKey = try KakusanDeviceRepository(
            database: AppDatabase(path: file.path, keys: KeychainKeyStore(source: .memory()))
        )
        #expect(throws: DeviceStoreFailure.unavailable) {
            try withoutKey.identity()
        }
    }

    @Test func devicesAreSavedUpdatedAndForgottenByKey() throws {
        let fixture = try TestDatabase()
        let repository = KakusanDeviceRepository(database: fixture.database)
        let first = try RememberedDevice(
            key: Self.key(1), fingerprint: Self.fingerprint(2), nickname: "Alex",
            firstVerified: Date(timeIntervalSince1970: 1000), lastSeen: Date(timeIntervalSince1970: 2000)
        )
        try repository.save(first)
        try repository.save(RememberedDevice(
            key: Self.key(1), fingerprint: Self.fingerprint(2), nickname: "Lex",
            firstVerified: Date(timeIntervalSince1970: 9000), lastSeen: Date(timeIntervalSince1970: 3000)
        ))
        let loaded = try repository.rememberedDevices()
        #expect(loaded.count == 1)
        #expect(loaded.first?.nickname == "Lex")
        #expect(loaded.first?.firstVerified == Date(timeIntervalSince1970: 1000))
        #expect(loaded.first?.lastSeen == Date(timeIntervalSince1970: 3000))
        try repository.forget(Self.key(1))
        #expect(try repository.rememberedDevices().isEmpty)
    }

    @Test func onlyPlaceholderKeysAndFingerprintsAreRestored() throws {
        let fixture = try TestDatabase()
        let repository = KakusanDeviceRepository(database: fixture.database)
        let placeholder = try Self.key(0)
        try repository.save(Self.identity(seed: 1, key: placeholder, fingerprint: .underived))
        try repository.save(RememberedDevice(
            key: Self.key(3), fingerprint: .underived, nickname: "Placeholder",
            firstVerified: Date(timeIntervalSince1970: 1), lastSeen: Date(timeIntervalSince1970: 2)
        ))
        try repository.save(RememberedDevice(
            key: Self.key(4), fingerprint: Self.fingerprint(4), nickname: "Real",
            firstVerified: Date(timeIntervalSince1970: 1), lastSeen: Date(timeIntervalSince1970: 2)
        ))
        #expect(try repository.hasUnderivedColumns())
        try repository.restoreDerivedColumns(
            identityKey: Self.key(9),
            fingerprints: [Self.key(3): Self.fingerprint(5), Self.key(4): Self.fingerprint(6)]
        )
        #expect(try repository.identity()?.key == (try Self.key(9)))
        let devices = try repository.rememberedDevices()
        #expect(devices.map(\.fingerprint) == [try Self.fingerprint(5), try Self.fingerprint(4)])
        #expect(try !repository.hasUnderivedColumns())
    }
}
