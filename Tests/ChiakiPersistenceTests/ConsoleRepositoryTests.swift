import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct ConsoleRepositoryTests {
    let account = AccountID(value: 0x0102_0304_0506_0708)

    func hardware(_ hex: String) throws -> HardwareID {
        try #require(HardwareID(hex: hex))
    }

    @Test func aPS4BelowEightAndADiscoveredNameSurviveARestart() throws {
        let file = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        let keys = KeychainKeyStore(source: .memory())
        let console = try StoredConsole(
            hardwareID: hardware("a1b2c3d4e5f6"), firmware: .ps4_8, name: "PS4-117",
            nameSource: .discovered, address: "192.0.2.4"
        )
        try ConsoleRepository(database: TestDatabase(path: file.path, keys: keys).database).save(console)
        let reopened = try ConsoleRepository(database: TestDatabase(path: file.path, keys: keys).database)
        #expect(try reopened.savedConsoles().consoles == [console])
    }

    @Test func savingAgainReplacesTheFactsButKeepsAKnownAddress() throws {
        let repository = try ConsoleRepository(database: TestDatabase().database)
        let id = try hardware("a1b2c3d4e5f6")
        try repository.save(StoredConsole(
            hardwareID: id, firmware: .ps4_9, name: "PS4", nameSource: .generation, address: "192.0.2.4"
        ))
        try repository.save(StoredConsole(
            hardwareID: id, firmware: .ps4_10, name: "Den", nameSource: .renamed, address: nil
        ))
        #expect(try repository.savedConsoles().consoles == [
            StoredConsole(
                hardwareID: id,
                firmware: .ps4_10,
                name: "Den",
                nameSource: .renamed,
                address: "192.0.2.4"
            )
        ])
    }

    @Test func aRowWrittenWithoutFirmwareReadsAsItsGenerationsNewestFamily() throws {
        let fixture = try TestDatabase()
        try fixture.database.write { database in
            try database.execute(
                sql: "INSERT INTO consoles(id, hardware_id, name, generation) "
                    + "VALUES ('c', 'a1b2c3d4e5f6', 'Den', 'ps4')"
            )
        }
        let loaded = try ConsoleRepository(database: fixture.database).savedConsoles().consoles
        #expect(loaded.map(\.firmware) == [.ps4_10])
        #expect(loaded.map(\.nameSource) == [.renamed])
    }

    @Test func aPairingRoundTripsItsKeysWithoutWritingThemInTheClear() throws {
        let file = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        let fixture = try TestDatabase(path: file.path)
        try fixture.addProfile(account)
        let repository = ConsoleRepository(database: fixture.database)
        let console = try hardware("0a0b0c0d0e0f")
        let device = try #require(ConsoleDeviceUID(bytes: [UInt8](repeating: 9, count: 32)))
        try repository.save(StoredConsole(
            hardwareID: console, firmware: .ps5, name: "Living room", nameSource: .pairing, address: nil
        ))
        let pairing = try #require(fixture.pairing(
            account: account,
            console: console,
            keys: (0x31, 0x5A),
            device: device
        ))
        try repository.save(pairing)

        let loaded = try repository.savedConsoles().pairings
        #expect(loaded.count == 1)
        let first = try #require(loaded.first)
        #expect(first.account == account)
        #expect(first.console == console)
        #expect(first.deviceUID == device)
        #expect(first.credentials.keyType == 2)
        let sameKeys = first.credentials.isEqual(to: pairing.credentials)
        #expect(sameKeys)
        let disk = try Data(contentsOf: file)
        #expect(disk.range(of: Data(repeating: 0x31, count: 16)) == nil)
        #expect(disk.range(of: Data(repeating: 0x5A, count: 16)) == nil)
    }

    @Test func savingAPairingAgainReplacesItsKeys() throws {
        let fixture = try TestDatabase()
        try fixture.addProfile(account)
        let repository = ConsoleRepository(database: fixture.database)
        let console = try hardware("0a0b0c0d0e0f")
        try repository.save(StoredConsole(
            hardwareID: console,
            firmware: .ps5,
            name: "PS5",
            nameSource: .pairing,
            address: nil
        ))
        try repository.save(#require(fixture.pairing(account: account, console: console, keys: (1, 2))))
        let replacement = try #require(fixture.pairing(
            account: account,
            console: console,
            keys: (3, 4),
            keyType: 1
        ))
        try repository.save(replacement)
        let loaded = try repository.savedConsoles().pairings
        #expect(loaded.count == 1)
        let replaced = loaded.first?.credentials.isEqual(to: replacement.credentials)
        #expect(replaced == true)
    }

    @Test func aPairingNeedsAKnownAccountAndConsole() throws {
        let fixture = try TestDatabase()
        let repository = ConsoleRepository(database: fixture.database)
        let console = try hardware("0a0b0c0d0e0f")
        #expect(throws: ConsoleStoreFailure.unknownAccount) {
            try repository.save(#require(fixture.pairing(account: account, console: console, keys: (1, 2))))
        }
        try fixture.addProfile(account)
        #expect(throws: ConsoleStoreFailure.unknownConsole) {
            try repository.save(#require(fixture.pairing(account: account, console: console, keys: (1, 2))))
        }
    }

    @Test func removingAPairingKeepsTheConsoleAndRemovingTheConsoleTakesItsPairings() throws {
        let fixture = try TestDatabase()
        try fixture.addProfile(account)
        let other = AccountID(value: 99)
        try fixture.addProfile(other, name: "Other")
        let repository = ConsoleRepository(database: fixture.database)
        let console = try hardware("0a0b0c0d0e0f")
        try repository.save(StoredConsole(
            hardwareID: console,
            firmware: .ps5,
            name: "PS5",
            nameSource: .pairing,
            address: nil
        ))
        try repository.save(#require(fixture.pairing(account: account, console: console, keys: (1, 2))))
        try repository.save(#require(fixture.pairing(account: other, console: console, keys: (3, 4))))
        try repository.removePairing(account: account, console: console)
        var saved = try repository.savedConsoles()
        #expect(saved.consoles.count == 1)
        #expect(saved.pairings.map(\.account) == [other])
        try repository.removeConsole(console)
        saved = try repository.savedConsoles()
        #expect(saved.consoles.isEmpty)
        #expect(saved.pairings.isEmpty)
    }

    @Test func noNewKeyIsCreatedWhileAnotherCredentialIsStored() throws {
        let reports = ReportedFailures()
        let fixture = try TestDatabase()
        try fixture.addProfile(account)
        try fixture.database.write { database in
            try database.execute(
                sql: """
                INSERT INTO profile_tokens(profile_id, credential_kind, encrypted_refresh, key_version)
                SELECT id, 'remote_play', X'0101', 1 FROM profiles
                """
            )
        }
        let repository = ConsoleRepository(database: fixture.database, report: reports.record)
        let console = try hardware("0a0b0c0d0e0f")
        try repository.save(StoredConsole(
            hardwareID: console,
            firmware: .ps5,
            name: "PS5",
            nameSource: .pairing,
            address: nil
        ))
        #expect(throws: ConsoleStoreFailure.unavailable) {
            try repository.save(#require(fixture.pairing(account: account, console: console, keys: (1, 2))))
        }
        #expect(reports.all == [.missingKey])
    }
}
