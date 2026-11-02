import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Testing

@Suite struct PairingBridgeTests {
    typealias Reason = libchiaking.consoles.PairingFailure.Reason

    @Test func everyCoreReasonAtHomeKeepsTheFailureTheAppAlwaysShowed() {
        let expected: [(Reason, PairingFailure)] = [
            (.address_not_for_generation, .invalidInput), (.unreachable, .unreachable), (.refused, .rejected),
            (.unreadable_reply, .rejected), (.malformed, .rejected), (.timed_out, .unreachable),
            (.cancelled, .cancelled), (.busy, .rejected), (.not_saved, .notSaved),
            (.remote_play_disabled, .rejected), (.internet_pairing_missing, .unavailable),
            (.unanswered, .rejected), (.not_available, .unavailable), (.needs_online_id, .rejected),
            (.session_playing, .sessionPlaying)
        ]
        for (reason, failure) in expected {
            #expect(PairingBridge
                .failure(of: reason, overInternet: false, stage: .starting, code: nil) == failure)
        }
    }

    @Test func aFailureOverTheInternetCarriesItsStageAndCode() {
        #expect(
            PairingBridge.failure(of: .refused, overInternet: true, stage: .connecting, code: 403)
                == .overInternet(.connecting, code: 403)
        )
        #expect(PairingBridge
            .failure(of: .session_playing, overInternet: true, stage: .pairing, code: nil) == .sessionPlaying)
        #expect(PairingBridge
            .failure(of: .cancelled, overInternet: true, stage: .pairing, code: nil) == .cancelled)
    }

    @Test func refusalsBeforeTheCoreRunsMapToInputOrAvailability() {
        let expected: [(chiaki_bridge.PairingRefusal, PairingFailure)] = [
            (.core_closed, .unavailable), (.unknown_user, .invalidInput), (.invalid_address, .invalidInput),
            (.invalid_pin, .invalidInput), (.unknown_console, .rejected)
        ]
        for (refusal, failure) in expected {
            let outcome = chiaki_bridge.PairingOutcome.refused(refusal)
            #expect(PairingBridge.result(of: outcome, overInternet: false) == .failure(failure))
        }
    }

    @Test func theConsolesReasonCodeWinsOverTheHTTPStatus() {
        var failure = libchiaking.consoles.PairingFailure()
        failure.reason = Reason.refused
        failure.http_status = .init(403)
        failure.internet_stage = .init(libchiaking.consoles.InternetPairingStage.connecting)
        #expect(PairingBridge.result(
            of: chiaki_bridge.PairingOutcome.failed(failure),
            overInternet: true
        ) == .failure(.overInternet(
            .connecting,
            code: 403
        )))
        failure.ps_reason = .init(0x8010_8B12)
        #expect(
            PairingBridge.result(of: chiaki_bridge.PairingOutcome.failed(failure), overInternet: true)
                == .failure(.overInternet(.connecting, code: 0x8010_8B12))
        )
    }

    @Test func everyStepStageAndWaitReasonMapsToItsOwnModelCase() {
        let steps: [libchiaking.consoles.PairingStep] = [
            .starting, .opening_account_session, .waking_console, .reaching_console, .sending_request,
            .waiting_for_answer, .saving
        ]
        #expect(steps.map(PairingBridge.step(of:)) == PairingStep.allCases)
        let stages: [libchiaking.consoles.InternetPairingStage] = [
            .starting, .opening_session, .waking_console, .connecting, .pairing
        ]
        #expect(stages.map(PairingBridge.stage(of:)) == InternetPairingStage.allCases)
        let reasons: [libchiaking.progress.WaitReason] = [
            .previous_session_closing, .server_queue, .data_migration, .datacenter_choice, .title_not_ready,
            .network_unreachable, .console_waking, .console_joining, .console_answering, .connection_retry,
            .recent_cloud_session
        ]
        #expect(reasons.map(PairingBridge.waitReason(of:)) == ProgressWaitReason.allCases)
    }

    @Test func everyFirmwareFamilyAndNameSourceKeepsItsIdentity() {
        let families: [libchiaking.consoles.Firmware.Family] = [.ps4_8, .ps4_9, .ps4_10, .ps5_1]
        #expect(families.map(ConsoleFactsReader.firmware(of:)) == ConsoleFirmware.allCases)
        let sources: [libchiaking.consoles.ConsoleName.Source] = [
            .generation, .account, .pairing, .discovered, .renamed
        ]
        #expect(sources.map(ConsoleFactsReader.nameSource(of:)) == ConsoleNameSource.allCases)
    }
}
