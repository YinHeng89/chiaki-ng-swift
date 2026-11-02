import ChiakiModels
import Foundation
import Testing

@Suite struct PairingFlowTests {
    let home = PairingTarget.atHome(address: "192.0.2.4", kind: .ps4)

    func internet() throws -> PairingTarget {
        let device = try #require(ConsoleDeviceUID(bytes: [UInt8](repeating: 0xAB, count: 32)))
        return .overInternet(AccountConsoleTarget(deviceUID: device, name: "Living room", kind: .ps5))
    }

    func console() throws -> PairedConsole {
        try PairedConsole(
            hardwareID: #require(HardwareID(hex: "a1b2c3d4e5f6")),
            name: "Living room",
            nameSource: .pairing,
            firmware: .ps4_8,
            address: "192.0.2.4"
        )
    }

    @Test func aHomeTargetWaitsForItsPINAndAnInternetTargetWaitsToStart() throws {
        let remote = try internet()
        #expect(PairingFlow(target: home) == .enteringPIN(home, failure: nil))
        #expect(PairingFlow(target: remote) == .ready(remote))
    }

    @Test func onlyTheRunningAttemptCanReportOrFinish() throws {
        var flow = PairingFlow(target: home)
        let stale = OperationID(), running = OperationID(), paired = try console()
        flow.start(stale)
        flow.cancel()
        let started = flow.start(running)
        let staleReport = flow.report(PairingProgress(step: .sendingRequest), for: stale)
        let staleFinish = flow.finish(stale, with: .success(paired))
        #expect(started && !staleReport && !staleFinish)
        #expect(flow.attempt?.id == running)
        let reported = flow.report(PairingProgress(step: .waitingForAnswer), for: running)
        #expect(reported)
        #expect(flow.attempt?.progress?.step == .waitingForAnswer)
        let finished = flow.finish(running, with: .success(paired))
        let finishedAgain = flow.finish(running, with: .success(paired))
        #expect(finished && !finishedAgain)
        #expect(flow == .paired(paired))
    }

    @Test func aFailedHomeAttemptReturnsToPINEntryWithItsFailure() {
        var flow = PairingFlow(target: home)
        let id = OperationID()
        flow.start(id)
        let finished = flow.finish(id, with: .failure(.rejected))
        #expect(finished)
        #expect(flow == .enteringPIN(home, failure: .rejected))
        let retried = flow.start(OperationID())
        #expect(retried)
    }

    @Test func aFailedInternetAttemptLeavesWithItsFailure() throws {
        let remote = try internet()
        var flow = PairingFlow(target: remote)
        let id = OperationID()
        flow.start(id)
        let failure = PairingFailure.overInternet(.connecting, code: 403)
        let finished = flow.finish(id, with: .failure(failure))
        #expect(finished)
        #expect(flow == .left(remote, failure: failure))
        let restarted = flow.start(OperationID())
        #expect(!restarted)
    }

    @Test func aCancelledResultNeverMovesTheWorkflow() {
        var flow = PairingFlow(target: home)
        let id = OperationID()
        flow.start(id)
        let finished = flow.finish(id, with: .failure(.cancelled))
        #expect(!finished)
        #expect(flow.attempt?.id == id)
    }

    @Test func cancellingStepsBackOneState() throws {
        var flow = PairingFlow(target: home)
        flow.start(OperationID())
        flow.cancel()
        #expect(flow == .enteringPIN(home, failure: nil))
        flow.cancel()
        #expect(flow == .left(home, failure: nil))
        let cancelledAgain = flow.cancel()
        #expect(!cancelledAgain)

        let remote = try internet()
        var remoteFlow = PairingFlow(target: remote)
        remoteFlow.start(OperationID())
        remoteFlow.cancel()
        #expect(remoteFlow == .left(remote, failure: nil))
    }

    @Test func noSecondAttemptStartsWhileOneRuns() {
        var flow = PairingFlow(target: home)
        let first = flow.start(OperationID())
        let second = flow.start(OperationID())
        #expect(first && !second)
    }
}
