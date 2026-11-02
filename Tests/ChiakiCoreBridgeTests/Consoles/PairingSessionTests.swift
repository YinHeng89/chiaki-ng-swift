import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
import Testing

extension CoreSessionSuites {
    @Suite struct PairingSessionTests {
        func request() throws -> PairingRequest {
            try PairingRequest(
                account: AccountID(value: 42),
                target: .atHome(address: "192.0.2.9", kind: .ps5),
                pin: PairingPIN("12345678")
            )
        }

        @Test func pairingWithoutAnOpenCoreIsUnavailable() async throws {
            #expect(!CoreSession.isOpen)
            await #expect(throws: PairingFailure.unavailable) {
                try await PairingBridge().pair(request()) { _ in
                }
            }
        }

        @Test func anAccountTheCoreDoesNotKnowIsRefusedBeforeAnythingIsSent() async throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let session = try harness.open()
            defer {
                session.close()
            }
            await #expect(throws: PairingFailure.invalidInput) {
                try await PairingBridge().pair(request()) { _ in
                    Issue.record("Nothing should be attempted for an unknown account")
                }
            }
        }
    }
}
