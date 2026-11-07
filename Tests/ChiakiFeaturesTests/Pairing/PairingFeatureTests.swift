import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct PairingFeatureTests {
    let account = AccountID(value: 0x0102_0304_0506_0708)
    let home = PairingTarget.atHome(address: "192.0.2.4", kind: .ps5)
    let reportedAt = Date(timeIntervalSince1970: 1_000)

    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    func console() throws -> PairedConsole {
        try PairedConsole(
            hardwareID: #require(HardwareID(hex: "a1b2c3d4e5f6")), name: "PS5-117", nameSource: .pairing,
            firmware: .ps5, address: "192.0.2.4"
        )
    }

    func internet() throws -> PairingTarget {
        let uid = try #require(ConsoleDeviceUID(bytes: [UInt8](
            repeating: 7,
            count: ConsoleDeviceUID.byteCount
        )))
        return .overInternet(AccountConsoleTarget(deviceUID: uid, name: "Den", kind: .ps5))
    }

    func store(
        _ target: PairingTarget,
        pair: @escaping @Sendable (
            AccountID, PairingTarget, String?, @escaping @Sendable (PairingProgress) -> Void
        ) async -> Result<PairedConsole, PairingFailure>
    ) -> TestStoreOf<PairingFeature> {
        TestStore(initialState: PairingFeature.State(account: account, target: target)) {
            PairingFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = reportedAt
            $0.continuousClock = ImmediateClock()
            $0.consoles.pair = pair
        }
    }

    @Test func aHomeConsoleIsPairedWithTheTypedPINAndReportedUpward() async throws {
        let paired = try console()
        let reaching = PairingProgress(step: .reachingConsole)
        let account = account
        let home = home
        let store = store(home) { requestedAccount, target, pin, progress in
            #expect(requestedAccount == account && target == home && pin == "12345678")
            progress(reaching)
            return .success(paired)
        }
        await store.send(.view(.submitPIN))
        await store.send(.binding(.set(\.pin, "1234"))) {
            $0.pin = "1234"
        }
        await store.send(.view(.submitPIN))
        await store.send(.binding(.set(\.pin, "12345678"))) {
            $0.pin = "12345678"
        }
        await store.send(.view(.submitPIN)) {
            $0.pin = ""
            $0.flow = .pairing(PairingAttempt(id: operation(0), target: home))
        }
        await store.receive(.delegate(.attemptStarted(home)))
        await store.receive(.attemptProgress(operation(0), reaching)) {
            $0.flow = .pairing(PairingAttempt(id: operation(0), target: home, progress: reaching))
            $0.reportedAt = reportedAt
        }
        await store.receive(.attemptFinished(operation(0), .success(paired), elapsed: .zero)) {
            $0.flow = .paired(paired)
            $0.reportedAt = nil
        }
        await store.receive(.delegate(.attemptEnded(home, .success(paired), elapsed: .zero)))
        await store.receive(.delegate(.paired(paired)))
    }

    @Test func aFailedHomeAttemptReturnsToPINEntryWithItsFailureAndCanBeRetried() async throws {
        let paired = try console()
        let attempts = LockIsolated(0)
        let home = home
        let store = store(home) { _, _, _, _ in
            attempts.withValue {
                $0 += 1
            }
            return attempts.value == 1
                ? .failure(.rejected)
                : .success(paired)
        }
        await store.send(.binding(.set(\.pin, "12345678"))) {
            $0.pin = "12345678"
        }
        await store.send(.view(.submitPIN)) {
            $0.pin = ""
            $0.flow = .pairing(PairingAttempt(id: operation(0), target: home))
        }
        await store.receive(.delegate(.attemptStarted(home)))
        await store.receive(.attemptFinished(operation(0), .failure(.rejected), elapsed: .zero)) {
            $0.flow = .enteringPIN(home, failure: .rejected)
        }
        await store.receive(.delegate(.attemptEnded(home, .failure(.rejected), elapsed: .zero)))
        await store.send(.binding(.set(\.pin, "87654321"))) {
            $0.pin = "87654321"
        }
        await store.send(.view(.submitPIN)) {
            $0.pin = ""
            $0.flow = .pairing(PairingAttempt(id: operation(1), target: home))
        }
        await store.receive(.delegate(.attemptStarted(home)))
        await store.receive(.attemptFinished(operation(1), .success(paired), elapsed: .zero)) {
            $0.flow = .paired(paired)
        }
        await store.receive(.delegate(.attemptEnded(home, .success(paired), elapsed: .zero)))
        await store.receive(.delegate(.paired(paired)))
    }

    @Test func cancellingARunningAttemptStopsItAndIgnoresItsLateResults() async throws {
        let paired = try console()
        let waiting = TestClock()
        let home = home
        let store = store(home) { _, _, _, _ in
            try? await waiting.sleep(for: .seconds(30))
            return .failure(.cancelled)
        }
        await store.send(.binding(.set(\.pin, "12345678"))) {
            $0.pin = "12345678"
        }
        await store.send(.view(.submitPIN)) {
            $0.pin = ""
            $0.flow = .pairing(PairingAttempt(id: operation(0), target: home))
        }
        await store.receive(.delegate(.attemptStarted(home)))
        await store.send(.view(.cancel)) {
            $0.flow = .enteringPIN(home, failure: nil)
        }
        await store.send(.attemptProgress(operation(0), PairingProgress(step: .waitingForAnswer)))
        await store.send(.attemptFinished(operation(0), .success(paired), elapsed: .seconds(3)))
        await store.send(.view(.cancel)) {
            $0.flow = .left(home, failure: nil)
        }
        await store.receive(.delegate(.left(home, nil)))
    }

    @Test func anInternetConsoleStartsWhenToldAndLeavesWithItsFailure() async throws {
        let target = try internet()
        let failure = PairingFailure.overInternet(.connecting, code: 403)
        let store = store(target) { _, _, pin, _ in
            #expect(pin == nil)
            return .failure(failure)
        }
        await store.send(.view(.submitPIN))
        await store.send(.start) {
            $0.flow = .pairing(PairingAttempt(id: operation(0), target: target))
        }
        await store.receive(.delegate(.attemptStarted(target)))
        await store.receive(.attemptFinished(operation(0), .failure(failure), elapsed: .zero)) {
            $0.flow = .left(target, failure: failure)
        }
        await store.receive(.delegate(.attemptEnded(target, .failure(failure), elapsed: .zero)))
        await store.receive(.delegate(.left(target, failure)))
        await store.send(.start)
    }

    @Test func everyFailureHasWordsForTheUser() {
        let failures: [PairingFailure] = [
            .invalidInput, .rejected, .unreachable, .unavailable, .notSaved, .sessionPlaying, .cancelled,
            .overInternet(.wakingConsole, code: nil), .overInternet(.connecting, code: 403)
        ]
        let texts = failures.map { String(localized: PairingFailureMessage.text(for: $0)) }
        #expect(Set(texts).count == failures.count)
        #expect(texts[0] == "Enter a valid console address and eight-digit PIN.")
        #expect(
            texts[8] == "PlayStation registration failed during console connection (code 403). "
                + "Retry or use a local PIN."
        )
    }
}
