import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct ConsoleLaunchRepositoryTests {
    let account = AccountID(value: 5)

    func pairedConsole(_ fixture: TestDatabase, hex: String, profile: ProfileID) throws -> UUID {
        let consoles = ConsoleRepository(database: fixture.database)
        let hardware = try #require(HardwareID(hex: hex))
        try consoles.save(StoredConsole(
            hardwareID: hardware,
            firmware: .ps5,
            name: "PS5",
            nameSource: .pairing,
            address: "192.0.2.9"
        ))
        try consoles.save(#require(fixture.pairing(account: account, console: hardware, keys: (1, 2))))
        let fetched: String? = try fixture.scalar(
            "SELECT id FROM consoles WHERE hardware_id = ?",
            [hardware.hex]
        )
        let id = try #require(fetched)
        return try #require(UUID(uuidString: id))
    }

    static func pin(_ text: String) -> SecretBytes {
        var bytes = Array(text.utf8)
        return SecretBytes(wiping: &bytes)
    }

    @Test func connectAtLaunchIsExclusive() throws {
        let fixture = try TestDatabase()
        let profile = try fixture.addProfile(account)
        let first = try pairedConsole(fixture, hex: "a1a1a1a1a1a1", profile: profile)
        let second = try pairedConsole(fixture, hex: "b2b2b2b2b2b2", profile: profile)
        let launch = ConsoleLaunchRepository(database: fixture.database)
        try launch.update(
            first,
            name: "One",
            address: "192.0.2.1",
            connectAtLaunch: true,
            forgetLoginPIN: false
        )
        try launch.update(
            second,
            name: "Two",
            address: "192.0.2.2",
            connectAtLaunch: true,
            forgetLoginPIN: false
        )
        #expect(try launch.launchConsole() == second)
        #expect(try launch.options(of: first).connectAtLaunch == false)
        #expect(throws: PersistenceError.invalidInput) {
            try launch.update(
                first,
                name: " ",
                address: "192.0.2.1",
                connectAtLaunch: false,
                forgetLoginPIN: false
            )
        }
    }

    @Test func theLoginPINIsSealedBoundToItsAccountAndForgotten() throws {
        let fixture = try TestDatabase()
        let profile = try fixture.addProfile(account)
        let console = try pairedConsole(fixture, hex: "c3c3c3c3c3c3", profile: profile)
        let launch = ConsoleLaunchRepository(database: fixture.database)
        #expect(throws: PersistenceError.invalidInput) {
            try launch.saveLoginPIN(Self.pin("12a4"), console: console, profile: profile.uuid)
        }
        #expect(throws: PersistenceError.invalidInput) {
            try launch.saveLoginPIN(Self.pin("1234"), console: console, profile: UUID())
        }
        try launch.saveLoginPIN(Self.pin("4711"), console: console, profile: profile.uuid)
        #expect(try launch.options(of: console).loginPINSaved)
        let opened = try launch.loginPIN(console: console, profile: profile.uuid)
        switch consume opened {
        case .some(let pin):
            #expect(pin.withUnsafeBytes { String(bytes: $0, encoding: .utf8) ?? "" } == "4711")
        case .none:
            Issue.record("The PIN did not load")
        }
        let stranger = try launch.loginPIN(console: console, profile: UUID())
        switch consume stranger {
        case .some:
            Issue.record("Another account read the PIN")
        case .none:
            break
        }
        try launch.clearLoginPIN(console: console, profile: profile.uuid)
        #expect(try !launch.options(of: console).loginPINSaved)
    }
}
