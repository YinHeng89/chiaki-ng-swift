import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct AccountRepositoryTests {
    let account = AccountID(value: 77)

    @Test func theListCarriesTheCachedAvatarAndMembership() throws {
        let fixture = try TestDatabase()
        let id = try fixture.addProfile(account, name: "Player")
        let resources = AccountResourceRepository(database: fixture.database)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        try resources.cache(.avatar, for: id.uuid, payload: Data([1, 2]), now: now, ttl: 60)
        try resources.cache(
            .profile,
            for: id.uuid,
            payload: Data(#"{"onlineID":"p","isPlus":true}"#.utf8),
            now: now,
            ttl: 900
        )
        let profile = try #require(AccountRepository(database: fixture.database).list().first)
        #expect(profile.id == id.uuid)
        #expect(profile.accountID == account)
        #expect(profile.avatarData == Data([1, 2]))
        #expect(profile.isPlus == true)
        #expect(profile.membershipCheckedAt == now)
        #expect(profile.membershipExpiresAt == now.addingTimeInterval(900))
    }

    @Test func deletingAnAccountCascadesToEverythingItHolds() throws {
        let fixture = try TestDatabase()
        let id = try fixture.addProfile(account)
        try AccountResourceRepository(database: fixture.database)
            .cache(.avatar, for: id.uuid, payload: Data([1]), now: Date(), ttl: 60)
        try fixture.database.write { database in
            try database.execute(
                sql: "INSERT INTO account_context(profile_id, age) VALUES (?, 3)",
                arguments: [id.uuidString]
            )
        }
        try AccountRepository(database: fixture.database).delete(id.uuid)
        for table in ["profiles", "account_resource_cache", "account_context"] {
            let count: Int? = try fixture.scalar("SELECT count(*) FROM \(table)")
            #expect(count == 0, "\(table)")
        }
    }

    @Test func anUnlinkedDuplicateHandsItsTokensToTheOldestProfile() throws {
        let fixture = try TestDatabase()
        let oldest = try fixture.addProfile(account, name: "Oldest")
        let duplicate = try fixture.addProfile(account, name: "Duplicate")
        var token = Array("refresh".utf8)
        let sealed = try fixture.database.cipher.seal(
            SecretBytes(wiping: &token),
            context: TokenRow.context(
                profileID: duplicate.uuidString,
                kind: TokenRow.remotePlayKind,
                part: .refresh
            ),
            allowKeyCreation: true
        )
        try fixture.database.write { database in
            try database.execute(
                sql: "UPDATE profiles SET created_at = created_at + 1000 WHERE id = ?",
                arguments: [duplicate.uuidString]
            )
            try database.execute(
                sql: """
                INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_refresh, key_version, updated_at)
                VALUES (?, 'remote_play', ?, 1, 5)
                """,
                arguments: [duplicate.uuidString, sealed]
            )
        }
        try AccountRepository(database: fixture.database).consolidateUnlinkedDuplicates()
        #expect(try AccountRepository(database: fixture.database).list().map(\.id) == [oldest.uuid])
        let moved: Data? = try fixture.scalar(
            "SELECT encrypted_refresh FROM profile_tokens WHERE profile_id = ?", [oldest.uuidString]
        )
        let opened = try fixture.database.cipher.open(
            #require(moved),
            context: TokenRow.context(
                profileID: oldest.uuidString,
                kind: TokenRow.remotePlayKind,
                part: .refresh
            )
        )
        #expect(opened.withUnsafeBytes { String(bytes: $0, encoding: .utf8) ?? "" } == "refresh")
    }

    @Test func aResourceIsCachedOnlyWithinItsLimits() throws {
        let fixture = try TestDatabase()
        let id = try fixture.addProfile(account)
        let resources = AccountResourceRepository(database: fixture.database)
        #expect(throws: PersistenceError.invalidInput) {
            try resources.cache(.avatar, for: id.uuid, payload: Data(), now: Date(), ttl: 60)
        }
        #expect(throws: PersistenceError.invalidInput) {
            try resources.cache(.avatar, for: id.uuid, payload: Data([1]), now: Date(), ttl: 0)
        }
        #expect(try resources.cached(.avatar, for: id.uuid) == nil)
    }

    @Test func theCloudDeviceIdIsCreatedOnceAndAMalformedOneIsNeverRotated() throws {
        let fixture = try TestDatabase()
        let installation = CloudInstallationRepository(database: fixture.database)
        let first = try installation.deviceID()
        #expect(first.count == 48)
        #expect(first.hasPrefix(CloudInstallationRepository.prefix))
        #expect(try installation.deviceID() == first)
        try fixture.database.write { database in
            try database.execute(
                sql: "UPDATE settings SET value_json = '\"broken\"' WHERE key = ?",
                arguments: [CloudInstallationRepository.key]
            )
        }
        #expect(throws: PersistenceError.corruptData) {
            try installation.deviceID()
        }
    }
}
