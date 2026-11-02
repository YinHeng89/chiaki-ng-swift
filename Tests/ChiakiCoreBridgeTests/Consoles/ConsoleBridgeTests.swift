import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct ConsoleBridgeTests {
    @Test func onlyADecidedCoreRouteBecomesAStartRoute() {
        #expect(ConsoleBridge.route(of: .home) == .home)
        #expect(ConsoleBridge.route(of: .internet) == .internet)
        #expect(ConsoleBridge.route(of: .automatic) == nil)
    }

    @Test func everyCoreWakeRefusalKeepsItsMeaning() {
        let expected: [(libchiaking.consoles.WakeRefusal, WakeRefusal)] = [
            (.not_paired, .notPaired), (.no_address, .noAddress), (.network, .network), (
                .not_found,
                .notFound
            ),
            (.still_in_rest_mode, .stillInRestMode), (.cancelled, .cancelled), (.forgotten, .forgotten)
        ]
        for (core, model) in expected {
            #expect(ConsoleBridge.refusal(of: chiaki_bridge.WakeOutcome.declined(core)) == model)
        }
        #expect(ConsoleBridge.refusal(of: chiaki_bridge.WakeOutcome.woken()) == nil)
    }

    @Test func aWakeTheBridgeRefusedSaysWhetherTheCoreWasOpen() {
        let closed = chiaki_bridge.WakeOutcome.refused(chiaki_bridge.ConsolesRefusal.core_closed)
        #expect(ConsoleBridge.refusal(of: closed) == .notAvailable)
        let stranger = chiaki_bridge.WakeOutcome.refused(chiaki_bridge.ConsolesRefusal.unknown_user)
        #expect(ConsoleBridge.refusal(of: stranger) == .unknown)
    }

    @Test func discoveredConsolesCarryTheirUppercaseHardwareIDAndRestMode() throws {
        var facts = chiaki_bridge.ConsoleFacts()
        facts.hardware_id = chiaki_bridge.Bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x0F])
        facts.name = std.string("Den")
        facts.address = .init(std.string("192.168.1.9"))
        facts.generation = .ps5
        facts.presence = .rest_mode
        let console = try #require(DiscoveryBridge.console(of: facts))
        #expect(console == DiscoveredConsole(
            id: "AABBCCDDEE0F", name: "Den", address: "192.168.1.9", kind: .ps5, standby: true
        ))
        facts.hardware_id = chiaki_bridge.Bytes([1, 2])
        #expect(DiscoveryBridge.console(of: facts) == nil)
    }

    @Test func invalidRangesAndFailedSearchesBecomeDiscoveryFailures() {
        #expect(DiscoveryBridge.failure(of: chiaki_bridge.SearchOutcome.covered(0)) == nil)
        let crowded = chiaki_bridge.SearchOutcome
            .invalid(libchiaking.consoles.SearchRanges.Invalid.too_many_targets)
        #expect(DiscoveryBridge.failure(of: crowded) == .tooManyTargets)
        let unreadable = chiaki_bridge.SearchOutcome.invalid(libchiaking.consoles.SearchRanges.Invalid.subnet)
        #expect(DiscoveryBridge.failure(of: unreadable) == .invalidSubnets)
        var stopped = chiaki_bridge.SearchFailureFacts()
        stopped.failure = libchiaking.consoles.SearchFailure.permission_denied
        #expect(DiscoveryBridge.failure(of: chiaki_bridge.SearchOutcome.failed(stopped)) == .network)
    }

    @Test func settingsAreNormalisedAndCheckedByTheCore() throws {
        var settings = DiscoverySettings()
        settings.subnets = [" 192.168.1.0/24 ", "192.168.1.0/24"]
        #expect(try DiscoveryBridge().validated(settings).subnets == ["192.168.1.0/24"])
        settings.subnets = ["not a subnet"]
        #expect(throws: DiscoveryFailure.invalidSubnets) {
            try DiscoveryBridge().validated(settings)
        }
    }

    @Test func anInstalledTitleCarriesItsConceptAndWhereItsTimeIsFrom() {
        var facts = chiaki_bridge.InstalledTitleFacts()
        facts.title_id = std.string("PPSA01234_00")
        facts.start_id = std.string("PPSA01234_00")
        facts.name = std.string("Astro")
        facts.platform = .ps5
        facts.last_used_ms = .init(1_760_000_000_000)
        facts.last_use_known = .init(libchiaking.consoles.InstalledTitle.LastUse.Known.on_the_account)
        facts.recently_played = true
        facts.concept_id = std.string("10000001")
        let title = ConsoleTitlesBridge.title(of: facts)
        #expect(title.titleID == "PPSA01234_00" && title.launchID == "PPSA01234_00")
        #expect(title.conceptID == "10000001")
        #expect(title.lastPlayedMs == 1_760_000_000_000)
        #expect(title.lastPlayedKnown == .onTheAccount)
        #expect(!title.playedOnThisConsole)
        facts.last_use_known = .init(libchiaking.consoles.InstalledTitle.LastUse.Known.on_this_console)
        #expect(ConsoleTitlesBridge.title(of: facts).playedOnThisConsole)
        facts.last_used_ms = .init()
        facts.concept_id = std.string()
        let undated = ConsoleTitlesBridge.title(of: facts)
        #expect(undated.lastPlayed == nil && undated.conceptID.isEmpty && !undated.playedOnThisConsole)
    }

    @Test func aTimedOutStartStillReportsHowFarTheConsoleGot() {
        var failure = libchiaking.consoles.StartFailure()
        failure.reason = .timed_out
        failure.reached = .starting
        #expect(ConsoleTitlesBridge
            .result(of: chiaki_bridge.StartOutcome.failed(failure)) == .success(.starting))
        failure.reason = .refused
        #expect(ConsoleTitlesBridge
            .result(of: chiaki_bridge.StartOutcome.failed(failure)) == .failure(.rejected))
        let unknown = chiaki_bridge.StartOutcome.refused(chiaki_bridge.ConsolesRefusal.invalid_title)
        #expect(ConsoleTitlesBridge.result(of: unknown) == .failure(.rejected))
    }
}
