import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct SettingsRepositoryTests {
    struct Volume: Codable, Equatable, Sendable {
        var level: Int
        var changedAt: Date?
    }

    struct OutOfRange: Error {}

    let key = SettingKey(name: "test.volume", defaultValue: Volume(level: 5)) { value in
        guard (0 ... 10).contains(value.level) else {
            throw OutOfRange()
        }
        return value
    }

    @Test func aMissingSettingReadsAsItsDefaultAndASavedOneSurvives() throws {
        let fixture = try TestDatabase()
        let settings = SettingsRepository(database: fixture.database)
        #expect(try settings.value(key) == Volume(level: 5))
        let changed = Volume(level: 7, changedAt: Date(timeIntervalSince1970: 1_760_000_000.25))
        try settings.save(changed, for: key)
        #expect(try settings.value(key) == changed)
        let json: String? = try fixture.scalar("SELECT value_json FROM settings WHERE key = 'test.volume'")
        #expect(json?.contains("1760000000250") == true)
    }

    @Test func storedDatesKeepFractionalMillisecondsAndSavedOnesRoundToTheNearest() throws {
        let fixture = try TestDatabase()
        let settings = SettingsRepository(database: fixture.database)
        try fixture.database.write { database in
            try database.execute(
                sql: "INSERT INTO settings(key, value_json) VALUES ('test.volume', ?)",
                arguments: ["{\"level\":1,\"changedAt\":1500.5}"]
            )
        }
        let stored = try #require(try settings.value(key).changedAt)
        #expect(abs(stored.timeIntervalSince1970 - 1.5005) < 1e-6)
        try settings.save(Volume(level: 2, changedAt: Date(timeIntervalSince1970: 0.0006)), for: key)
        let json: String? = try fixture.scalar("SELECT value_json FROM settings WHERE key = 'test.volume'")
        #expect(json?.contains("\"changedAt\":1") == true)
        #expect(json?.contains("\"changedAt\":0") == false)
    }

    @Test func anInvalidValueIsRefusedAndACorruptOneIsNotReplacedByTheDefault() throws {
        let fixture = try TestDatabase()
        let settings = SettingsRepository(database: fixture.database)
        #expect(throws: PersistenceError.invalidInput) {
            try settings.save(Volume(level: 11), for: key)
        }
        try fixture.database.write { database in
            try database
                .execute(
                    sql: "INSERT INTO settings(key, value_json) VALUES ('test.volume', '{\"level\":99}')"
                )
        }
        #expect(throws: PersistenceError.corruptData) {
            try settings.value(key)
        }
    }

    @Test func anUpdateReadsChangesAndWritesInOneStep() throws {
        let fixture = try TestDatabase()
        let settings = SettingsRepository(database: fixture.database)
        let updated = try settings.update(key) {
            Volume(level: $0.level + 1)
        }
        #expect(updated == Volume(level: 6))
        #expect(try settings.value(key) == Volume(level: 6))
    }

    @Test func controlsKeepVersionOneDocumentsAndRefuseNewerOnes() throws {
        let fixture = try TestDatabase()
        let controls = ControlsRepository(database: fixture.database)
        #expect(try controls.configuration(Volume.self) == nil)
        try controls.save(Volume(level: 3))
        #expect(try controls.configuration(Volume.self) == Volume(level: 3))
        try fixture.database.write { database in
            try database.execute(sql: "UPDATE input_configuration SET version = 2")
        }
        #expect(throws: PersistenceError.unsupportedVersion(found: 2, supported: 1)) {
            try controls.configuration(Volume.self)
        }
    }
}
