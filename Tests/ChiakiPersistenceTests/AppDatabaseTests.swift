import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import Testing

@Suite struct AppDatabaseTests {
    @Test func aScratchLocationOpensMigratedWithOwnerOnlyPermissions() throws {
        let data = UserData.scratch()
        defer {
            try? FileManager.default.removeItem(at: data.support.deletingLastPathComponent())
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(!data.database.resolvingSymlinksInPath().path.hasPrefix("\(home)/Library"))
        let database = try AppDatabase.open(data)
        let version: Int? = try database.read { database in
            try Int.fetchOne(database, sql: "PRAGMA user_version")
        }
        #expect(version == 19)
        let attributes = try FileManager.default.attributesOfItem(atPath: data.database.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func reopeningAScratchLocationReadsWhatTheFirstOpenSealed() throws {
        let data = UserData.scratch()
        defer {
            try? FileManager.default.removeItem(at: data.support.deletingLastPathComponent())
        }
        var plaintext = Array("synthetic".utf8)
        let envelope = try AppDatabase.open(data).cipher.seal(
            SecretBytes(wiping: &plaintext),
            context: "test",
            allowKeyCreation: true
        )
        let opened = try AppDatabase.open(data).cipher.open(envelope, context: "test").withUnsafeBytes {
            Data($0)
        }
        #expect(opened == Data("synthetic".utf8))
    }

    @Test func aWriteThatThrowsRollsBack() throws {
        let fixture = try TestDatabase()
        #expect(throws: PersistenceError.database(code: 19)) {
            try fixture.database.write { database in
                try database.execute(sql: "INSERT INTO settings(key, value_json) VALUES ('kept', '1')")
                try database.execute(sql: "INSERT INTO settings(key, value_json) VALUES ('kept', '2')")
            }
        }
        let count: Int? = try fixture.scalar("SELECT count(*) FROM settings")
        #expect(count == 0)
    }
}
