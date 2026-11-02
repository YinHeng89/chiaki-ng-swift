import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import Testing

private func ended(
    _ configure: (inout chiaki_bridge.StreamEndFacts) -> Void
) -> StreamOutcome {
    var end = chiaki_bridge.StreamEndFacts()
    configure(&end)
    return StreamOutcomeReader.outcome(of: chiaki_bridge.StreamOutcome.ended(end))
}

private func startRefused(
    _ configure: (inout chiaki_bridge.StartRefusalFacts) -> Void
) -> StreamOutcome {
    var refusal = chiaki_bridge.StartRefusalFacts()
    configure(&refusal)
    return StreamOutcomeReader.outcome(of: chiaki_bridge.StreamOutcome.start_refused(refusal))
}

@Test func coreEndingsBecomeTypedOutcomes() {
    #expect(ended {
        $0.ending = .finished
    } == .finished)
    #expect(ended {
        $0.ending = .left
    } == .left)
    #expect(StreamOutcomeReader.outcome(of: chiaki_bridge.StreamOutcome.unrecorded()) == .unrecorded)
    #expect(ended {
        $0.ending = .session_failed
        $0.cause.value = .control_timeout
    } == .sessionFailed(.controlTimeout))
    #expect(ended {
        $0.ending = .start_failed
    } == .startFailed(nil))
    #expect(ended {
        $0.ending = .console_quit
        $0.quit.value = .console_in_use
    } == .consoleQuit(.consoleInUse))
    #expect(ended {
        $0.ending = .media_failed
        $0.media_failure.value = .audio_output
    } == .mediaFailed(.audioOutput))
}

@Test func aReachedTimeLimitCrossesAsItsOwnQuit() {
    #expect(ended {
        $0.ending = .console_quit
        $0.quit.value = .time_limit_reached
    } == .consoleQuit(.timeLimitReached))
    #expect(StreamOutcomeReader.quitReason(of: .time_limit_reached) != .consoleDisconnected)
    #expect(StreamOutcome.consoleQuit(.timeLimitReached).name == "console_quit.time_limit_reached")
}

@Test func anEndedTrialCrossesAsItsOwnQuit() {
    #expect(ended {
        $0.ending = .console_quit
        $0.quit.value = .trial_ended
    } == .consoleQuit(.trialEnded))
    #expect(StreamOutcome.consoleQuit(.trialEnded).name == "console_quit.trial_ended")
    #expect(StreamOutcome.QuitReason.trialEnded.endsPlayTime)
    #expect(StreamOutcome.QuitReason.timeLimitReached.endsPlayTime)
    #expect(!StreamOutcome.QuitReason.consoleDisconnected.endsPlayTime)
}

@Test func refusalsWinOverTheEnding() {
    #expect(startRefused {
        $0.kind = .needs_psn_sign_in
    } == .startRefused(.needsPSNSignIn))
    #expect(StreamOutcomeReader
        .outcome(of: chiaki_bridge.StreamOutcome.refused(.no_decoder)) == .startRefused(.noDecoder))
    #expect(StreamOutcomeReader
        .outcome(of: chiaki_bridge.StreamOutcome.refused(.core_closed)) == .startRefused(.coreClosed))
}

@Test func cloudLaunchRefusalsTravelWithTheReport() {
    var start = chiaki_bridge.StartRefusalFacts()
    start.kind = .launch_refused
    var refused = chiaki_bridge.LaunchRefusalFacts()
    refused.kind = .datacenter_unavailable
    refused.datacenter = "eu-west"
    start.launch_refused.value = refused
    let report = StreamOutcomeReader.report(of: chiaki_bridge.StreamOutcome.start_refused(start))
    #expect(report.outcome == .startRefused(.launchRefused))
    #expect(report.launchRefused == .datacenterUnavailable("eu-west"))
    #expect(StreamOutcomeReader.report(of: chiaki_bridge.StreamOutcome.unrecorded()).launchRefused == nil)
}

@Test func aConsoleUnreachableOverTheNetworkIsANetworkFailure() {
    #expect(startRefused {
        $0.kind = .console_unreachable
        $0.unreachable.value = .network
    } == .startRefused(.networkUnreachable))
    #expect(startRefused {
        $0.kind = .console_unreachable
        $0.unreachable.value = .timed_out
    } == .startRefused(.consoleUnreachable))
    #expect(startRefused {
        $0.kind = .console_unreachable
    } == .startRefused(.consoleUnreachable))
    #expect(StreamOutcome.startRefused(.networkUnreachable).name == "start_refused.network_unreachable")
}

@Test func namesAreStableForLogsAndSupport() {
    #expect(StreamOutcome.sessionFailed(.controlTimeout).name == "session_failed.control_timeout")
    #expect(StreamOutcome.shutdownFailed(nil).name == "shutdown_failed")
    #expect(StreamOutcome.startRefused(.needsPSNSignIn).name == "start_refused.needs_psn_sign_in")
    #expect(!StreamOutcome.left.failed && !StreamOutcome.finished.failed && StreamOutcome.unrecorded.failed)
}

@Test func onlyFailuresWithACauseReportOne() {
    #expect(StreamOutcome.startFailed(.pairingRejected).cause == .pairingRejected)
    #expect(StreamOutcome.sessionFailed(nil).cause == nil)
    #expect(StreamOutcome.consoleQuit(.consoleInUse).cause == nil)
    #expect(StreamOutcomeReader.cause(of: .pairing_rejected) == .pairingRejected)
}

@Test func aSessionThreadTheHostCouldNotStartIsAHostRefusal() {
    #expect(startRefused {
        $0.kind = .host_refused
    } == .startRefused(.hostRefused))
}
