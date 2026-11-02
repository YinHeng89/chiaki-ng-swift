import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
import ChiakiPersistence
import Foundation
import Testing

extension CoreSessionSuites {
    @Suite struct ConsoleStoreAdapterTests {
        struct UnreadableStore: ConsoleStoring {
            func savedConsoles() throws(ConsoleStoreFailure) -> SavedConsoles {
                throw .unavailable
            }

            func save(_ console: StoredConsole) throws(ConsoleStoreFailure) {
                throw .unavailable
            }

            func save(_ pairing: StoredPairing) throws(ConsoleStoreFailure) {
                throw .unavailable
            }

            func removePairing(account: AccountID, console: HardwareID) throws(ConsoleStoreFailure) {
                throw .unavailable
            }

            func removeConsole(_ console: HardwareID) throws(ConsoleStoreFailure) {
                throw .unavailable
            }
        }

        let account = AccountID(value: 0x0102_0304_0506_0708)

        func hardware() throws -> HardwareID {
            try #require(HardwareID(hex: "a1b2c3d4e5f6"))
        }

        func seeded(_ harness: CoreSessionHarness) throws -> StoredConsole {
            let console = try StoredConsole(
                hardwareID: hardware(), firmware: .ps4_8, name: "PS4-117", nameSource: .discovered,
                address: "192.0.2.4"
            )
            try harness.addProfile(account)
            try harness.repository.save(console)
            try harness.repository.save(#require(harness.pairing(
                account: account,
                console: console.hardwareID,
                keys: (0x31, 0x5A)
            )))
            return console
        }

        @Test func savedFactsReachTheCoreWithTheirFirmwareAndNameSource() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let console = try seeded(harness)
            let session = try harness.open()
            defer {
                session.close()
            }
            #expect(session.rememberSavedConsoles() == RememberedConsoles(remembered: 1, rejected: 0))
            #expect(session.console(console.hardwareID) == console)
            #expect(session.isPaired(console.hardwareID))
        }

        @Test func aRenameInTheCoreIsSavedAndAPS4BelowEightSurvivesARestart() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let console = try seeded(harness)
            let first = try harness.open()
            _ = first.rememberSavedConsoles()
            let renamed = first.consoles.rename(console.hardwareID, to: "Den")
            first.close()
            #expect(renamed)
            let expected = StoredConsole(
                hardwareID: console.hardwareID, firmware: .ps4_8, name: "Den", nameSource: .renamed,
                address: "192.0.2.4"
            )
            #expect(try harness.repository.savedConsoles().consoles == [expected])

            let second = try harness.open()
            defer {
                second.close()
            }
            _ = second.rememberSavedConsoles()
            #expect(second.console(console.hardwareID) == expected)
        }

        @Test func unpairingAndForgettingInTheCoreRemoveTheRows() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let console = try seeded(harness)
            let session = try harness.open()
            defer {
                session.close()
            }
            _ = session.rememberSavedConsoles()
            try session.consoles.unpair(account, from: console.hardwareID)
            #expect(try harness.repository.savedConsoles().pairings.isEmpty)
            #expect(try harness.repository.savedConsoles().consoles.count == 1)
            #expect(session.consoles.forget(console.hardwareID))
            #expect(throws: UnpairRefusal.unknownConsole) {
                try session.consoles.unpair(account, from: console.hardwareID)
            }
            #expect(try harness.repository.savedConsoles().consoles.isEmpty)
        }

        @Test func aStoreThatCannotBeReadLeavesTheCoreWithoutConsoles() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let session = try harness.open(consoles: UnreadableStore())
            defer {
                session.close()
            }
            #expect(session.rememberSavedConsoles() == nil)
        }

        @Test func onlyOneSessionOpensAtATime() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let session = try harness.open()
            defer {
                session.close()
            }
            #expect(CoreSession.isOpen)
            #expect(throws: CoreOpenFailure.alreadyOpen) {
                try harness.open()
            }
        }
    }
}
