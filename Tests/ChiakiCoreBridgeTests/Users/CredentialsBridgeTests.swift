import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct CredentialsBridgeTests {
    @Test func everyCredentialKindCrossesBothWays() {
        for kind in CredentialKind.allCases {
            #expect(CredentialsBridge.kind(of: CredentialsBridge.kind(of: kind)) == kind)
        }
    }

    @Test func aHeldCredentialBecomesTheModelFacts() {
        var facts = chiaki_bridge.HeldCredentialFacts()
        facts.kind = .app_token
        facts.held = true
        facts.kept = .with_the_user
        facts.state = .expired
        facts.obtained_at_ms = .init(1_700_000_000_000)
        facts.expires_at_ms = .init(1_700_000_900_000)
        facts.scopes = std.string("psn:mobile.v2.core")
        facts.last_reply_status = .init(401)
        facts.used_for.push_back(.profile)
        facts.used_for.push_back(.membership)
        #expect(CredentialsBridge.credential(of: facts) == HeldCredential(
            kind: .appToken, held: true, kept: .withTheUser, state: .expired,
            obtainedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_900), scopes: "psn:mobile.v2.core",
            lastReplyStatus: 401, usedFor: [.profile, .membership]
        ))
    }

    @Test func aCredentialThatWasNeverObtainedCrossesWithNothingInvented() {
        var facts = chiaki_bridge.HeldCredentialFacts()
        facts.kind = .library_token
        facts.kept = .in_memory
        facts.state = .never_obtained
        let credential = CredentialsBridge.credential(of: facts)
        #expect(credential == HeldCredential(kind: .libraryToken, held: false))
        #expect(credential.obtainedAt == nil && credential.expiresAt == nil && credential
            .lastReplyStatus == nil)
    }

    @Test func everyRefusalToRevealSaysWhy() {
        let expected: [(chiaki_bridge.RevealRefusal, NotRevealed.Reason)] = [
            (.core_closed, .coreClosed), (.unknown_user, .unknownUser), (.not_held, .notHeld),
            (.signed_out, .signedOut)
        ]
        for (refusal, reason) in expected {
            #expect(CredentialsBridge.reason(of: refusal) == reason)
        }
    }

    @Test func everyCoreUseStateAndKeepingHasAModelValue() {
        #expect(CredentialState.allCases.count == 5)
        #expect(CredentialsBridge.state(of: .unverified) == .unverified)
        #expect(CredentialsBridge.kept(of: .in_memory) == .inMemory)
        #expect(CredentialsBridge.use(of: .old_service_checkout) == .oldServiceCheckout)
        #expect(CredentialUse.allCases.count == 15)
    }
}
