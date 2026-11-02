import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct MissingTimeTests {
    @Test func trophiesAndMessagesReadZeroAndNegativeTimesAsNone() {
        for read in [PSNTrophiesBridge.date(of:), PSNMessagesBridge.date(of:)] {
            #expect(read(0) == nil)
            #expect(read(-1) == nil)
            #expect(read(1) == Date(timeIntervalSince1970: 0.001))
            #expect(read(1_760_000_000_250) == Date(timeIntervalSince1970: 1_760_000_000.25))
        }
    }

    @Test func anInvitationSentAtOrBeforeTheEpochHasNoSentTime() {
        var facts = chiaki_bridge.GameInvitationFacts()
        facts.sent_ms = 0
        #expect(GameInvitationsBridge.invitation(of: facts).sent == nil)
        facts.sent_ms = -1
        #expect(GameInvitationsBridge.invitation(of: facts).sent == nil)
        facts.sent_ms = 1_760_000_000_250
        #expect(GameInvitationsBridge.invitation(of: facts)
            .sent == Date(timeIntervalSince1970: 1_760_000_000.25))
    }

    @Test func catalogTimesHaveNoMissingMarker() {
        #expect(CatalogBridge.date(of: 0) == Date(timeIntervalSince1970: 0))
        #expect(CatalogBridge.date(of: -1) == Date(timeIntervalSince1970: -0.001))
        #expect(CatalogBridge.date(of: 1_760_000_000_250) == Date(timeIntervalSince1970: 1_760_000_000.25))
    }

    @Test func aQRCodeExpiryIsMissingOnlyWhenNegative() {
        func expiry(_ milliseconds: Int64) -> Date?? {
            "https://example.invalid/a".withCString { url in
                "012345".withCString { code in
                    guard case let .awaitingApproval(shown) = UsersBridge.progress(
                        attempt: 1,
                        step: UInt8(libchiaking.users.QrSignInStep.awaiting_approval.rawValue),
                        url: url,
                        code: code,
                        expiresAtMilliseconds: milliseconds
                    ) else {
                        return nil
                    }
                    return .some(shown.expiresAt)
                }
            }
        }
        #expect(expiry(-1) == .some(nil))
        #expect(expiry(0) == .some(Date(timeIntervalSince1970: 0)))
        #expect(expiry(1500) == .some(Date(timeIntervalSince1970: 1.5)))
    }
}
