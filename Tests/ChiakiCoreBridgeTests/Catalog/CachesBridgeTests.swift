import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import CxxStdlib
import Foundation
import Testing

@Suite struct CachesBridgeTests {
    @Test func anEntryKeepsWhatIdentifiesIt() {
        var facts = chiaki_bridge.CacheEntryFacts()
        facts.cache = .game_details
        var account = chiaki_bridge.Bytes()
        for byte: UInt8 in 1...8 {
            account.push_back(byte)
        }
        facts.account_id = .init(account)
        facts.locale = .init(std.string("en-gb"))
        facts.concept_id = .init(std.string("10000237"))
        facts.bytes = 2048
        facts.stored_at_ms = 1_700_000_000_000
        facts.expires_at_ms = .init(1_700_000_060_000)
        #expect(CachesBridge.entry(of: facts) == CoreCacheEntry(
            cache: .game_details,
            account: Data([1, 2, 3, 4, 5, 6, 7, 8]),
            locale: "en-gb",
            conceptID: "10000237",
            bytes: 2048,
            storedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_060)
        ))
    }

    @Test func aClosedCoreIsReportedAsClosed() {
        let outcome = chiaki_bridge.ClearOutcome.refused(chiaki_bridge.CatalogRefusal.core_closed)
        #expect(throws: CatalogUnanswered(reason: .coreClosed)) {
            try CachesBridge.result(of: outcome).get()
        }
        let storage = chiaki_bridge.SummariesOutcome.unanswered(chiaki_bridge.CatalogUnanswered(
            reason: .storage,
            http_status: 0,
            needs_sign_in: false
        ))
        #expect(throws: CatalogUnanswered(reason: .storage)) {
            try CachesBridge.result(of: storage).get()
        }
    }
}
