import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiClientsLive

private struct Refused: Error {}

private final class Ledger: Sendable {
    let writes = LockIsolated<[String]>([])
    let core = LockIsolated<[String]>([])

    func transaction(
        writeFails: Bool = false,
        coreAccepts: Bool = true
    ) -> ConsoleEditTransaction {
        ConsoleEditTransaction(
            read: { _ in
                .init(name: "Old", address: "192.0.2.1", connectAtLaunch: false)
            },
            write: { [writes] _, name, address, launch, forget in
                guard !writeFails else {
                    throw Refused()
                }
                writes.withValue {
                    $0.append("\(name) \(address) \(launch) \(forget)")
                }
            },
            applyToCore: { [core] _, name, address in
                core.withValue {
                    $0.append("\(name) \(address)")
                }
                return coreAccepts
            }
        )
    }
}

private let draft = ConsoleDraft(
    id: UUID(), name: " New ", address: "192.0.2.9", generation: "PS5", remoteAvailable: false,
    hardwareID: "aabbccddeeff", connectAtLaunch: true, loginPIN: .forgotten
)

@Test func anEditReachesTheDatabaseThenTheCoreAndForgetsThePINLast() async {
    let ledger = Ledger()
    let failure = await ledger.transaction().commit(draft)
    #expect(failure == nil)
    #expect(ledger.writes.value == ["New 192.0.2.9 true false", "New 192.0.2.9 true true"])
    #expect(ledger.core.value == ["New 192.0.2.9"])
}

@Test func aCoreRefusalPutsTheDatabaseBackSoTheyNeverDisagree() async {
    let ledger = Ledger()
    let failure = await ledger.transaction(coreAccepts: false).commit(draft)
    #expect(failure == .saveFailed)
    #expect(ledger.writes.value == ["New 192.0.2.9 true false", "Old 192.0.2.1 false false"])
}

@Test func aDatabaseFailureNeverRenamesInTheCore() async {
    let ledger = Ledger()
    let failure = await ledger.transaction(writeFails: true).commit(draft)
    #expect(failure == .saveFailed)
    #expect(ledger.core.value.isEmpty)
}

@Test func anInvalidDraftTouchesNothing() async {
    let ledger = Ledger()
    var invalid = draft
    invalid.name = "  "
    let failure = await ledger.transaction().commit(invalid)
    #expect(failure == .saveFailed)
    #expect(ledger.writes.value.isEmpty && ledger.core.value.isEmpty)
}
