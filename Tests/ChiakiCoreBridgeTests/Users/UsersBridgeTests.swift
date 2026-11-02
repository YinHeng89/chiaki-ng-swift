import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import CxxStdlib
import Foundation
import Testing

@Suite struct UsersBridgeTests {
    typealias Kind = libchiaking.users.SignInErrorKind

    struct RefusalCase {
        let refusal: chiaki_bridge.UsersRefusal
        let signIn: CoreSignInFailure
        let refresh: CoreUnanswered.Reason

        init(
            _ refusal: chiaki_bridge.UsersRefusal,
            _ signIn: CoreSignInFailure,
            _ refresh: CoreUnanswered.Reason
        ) {
            self.refusal = refusal
            self.signIn = signIn
            self.refresh = refresh
        }
    }

    @Test func everyCoreSignInFailureKeepsItsMeaning() {
        let expected: [(Kind, CoreSignInFailure)] = [
            (.invalid_request, .invalidRequest), (.cancelled, .cancelled), (.transport, .transport),
            (.rejected, .rejected), (.rate_limited, .rateLimited), (
                .unavailable,
                .unavailable(httpStatus: 503)
            ),
            (.malformed, .malformed), (.declined, .declined), (.verification_required, .verificationRequired),
            (.expired, .expired), (.layout_changed, .layoutChanged)
        ]
        for (kind, model) in expected {
            #expect(UsersBridge.failure(of: kind, httpStatus: 503) == model)
        }
    }

    @Test func everyQRSignInStepBecomesProgressAndFinalStepsAreLeftToTheResult() {
        typealias Step = libchiaking.users.QrSignInStep
        func progress(_ step: Step, url: String = "", code: String = "",
                      expires: Int64 = -1) -> QRSignInProgress? {
            url.withCString { url in
                code.withCString { code in
                    UsersBridge.progress(
                        attempt: 2, step: UInt8(step.rawValue), url: url, code: code,
                        expiresAtMilliseconds: expires
                    )
                }
            }
        }
        #expect(progress(.preparing) == .preparing)
        #expect(progress(.signing_in) == .signingIn)
        #expect(progress(.awaiting_approval, url: "https://example.invalid/a", code: "012345", expires: 1500)
            == .awaitingApproval(QRSignInCode(
                attempt: 2, approvalURL: "https://example.invalid/a", userCode: "012345",
                expiresAt: Date(timeIntervalSince1970: 1.5)
            )))
        #expect(progress(.awaiting_approval, url: "https://example.invalid/a", code: "012345")
            == .awaitingApproval(QRSignInCode(
                attempt: 2, approvalURL: "https://example.invalid/a", userCode: "012345", expiresAt: nil
            )))
        #expect(progress(.awaiting_approval) == nil)
        #expect(progress(.signed_in) == nil)
        #expect(progress(.failed) == nil)
    }

    @Test func refusalsBeforeTheCoreRunsSayWhy() {
        let expected = [
            RefusalCase(.core_closed, .coreClosed, .coreClosed),
            RefusalCase(.unknown_user, .unknownUser, .unknownUser),
            RefusalCase(.invalid_device, .invalidDevice, .unavailable),
            RefusalCase(.not_saved, .unavailable(httpStatus: nil), .unavailable)
        ]
        for entry in expected {
            let signIn = chiaki_bridge.SignInOutcome.refused(entry.refusal)
            #expect(UsersBridge.result(of: signIn) == .failure(entry.signIn))
            let refresh = chiaki_bridge.RefreshOutcome.refused(entry.refusal)
            #expect(UsersBridge.result(of: refresh) == .failure(CoreUnanswered(reason: entry.refresh)))
        }
    }

    @Test func aDifferentAccountNamesWhoTheNPSSOBelongsTo() {
        var other = chiaki_bridge.OtherAccount()
        other.account_id = chiaki_bridge.Bytes(AccountID(value: 77).bytes)
        other.online_id = std.string("someone")
        let outcome = chiaki_bridge.SignInOutcome.different_account(other)
        #expect(UsersBridge.result(of: outcome) == .failure(.differentAccount(
            AccountID(value: 77),
            onlineID: "someone"
        )))
    }

    @Test func aStatusIsKeptOnlyWhenTheCoreReportsOne() {
        var failure = chiaki_bridge.SignInFailureFacts()
        failure.kind = Kind.unavailable
        #expect(UsersBridge
            .result(of: chiaki_bridge.SignInOutcome.failed(failure)) ==
            .failure(.unavailable(httpStatus: nil)))
        failure.http_status = .init(502)
        #expect(UsersBridge
            .result(of: chiaki_bridge.SignInOutcome.failed(failure)) ==
            .failure(.unavailable(httpStatus: 502)))
    }

    @Test func everyCoreStateAndTierHasAModelValue() {
        let states: [(libchiaking.users.SignInState, SignInState)] = [
            (.signed_in, .signedIn), (.store_access_lapsed, .storeAccessLapsed), (.expired, .signInExpired),
            (.signed_out, .signedOut)
        ]
        for (core, model) in states {
            #expect(UsersBridge.state(of: core) == model)
        }
        let tiers: [(libchiaking.users.Tier, PlusTier)] = [
            (.none, .none), (.essential, .essential), (.extra, .extra), (.premium, .premium)
        ]
        for (core, model) in tiers {
            #expect(UsersBridge.tier(of: core) == model)
        }
    }

    @Test func userFactsBecomeTheModelUser() throws {
        var facts = chiaki_bridge.UserFacts()
        facts.account_id = chiaki_bridge.Bytes(AccountID(value: 5).bytes)
        facts.online_id = std.string("player")
        facts.has_psn_account = true
        facts.sign_in_state = .signed_in
        facts.tier = .init(libchiaking.users.Tier.extra)
        facts.plus_member = .init(true)
        facts.avatar_url = .init(std.string("https://example.invalid/a.png"))
        facts.country = .init(std.string("GB"))
        facts.language = .init(std.string("en"))
        let user = try #require(UsersBridge.user(of: facts))
        #expect(user == SignedInUser(
            accountID: AccountID(value: 5), onlineID: "player", hasPSNAccount: true, state: .signedIn,
            tier: .extra, plusMember: true, avatarURL: URL(string: "https://example.invalid/a.png"),
            region: AccountRegion(country: "GB", language: "en")
        ))
        facts.account_id = chiaki_bridge.Bytes([1, 2, 3])
        #expect(UsersBridge.user(of: facts) == nil)
    }

    @Test func aRefreshThatWentUnansweredKeepsItsReasonAndStatus() {
        var why = libchiaking.users.Unanswered()
        why.reason = .sign_in_expired
        why.http_status = 401
        let outcome = chiaki_bridge.RefreshOutcome.unanswered(why)
        let failure = CoreUnanswered(reason: .signInExpired, httpStatus: 401)
        #expect(UsersBridge.result(of: outcome) == .failure(failure))
        #expect(failure.needsSignIn)
    }

    @Test func everyCoreUnansweredReasonHasAModelReason() {
        typealias Reason = libchiaking.users.Unanswered.Reason
        let expected: [(Reason, CoreUnanswered.Reason)] = [
            (.signed_out, .signedOut), (.sign_in_expired, .signInExpired),
            (.store_access_lapsed, .storeAccessLapsed), (
                .remote_play_access_missing,
                .remotePlayAccessMissing
            ),
            (.cancelled, .cancelled), (.rate_limited, .rateLimited), (.unavailable, .unavailable),
            (.rejected, .rejected), (.malformed, .malformed), (.old_service_refused, .oldServiceRefused)
        ]
        for (core, model) in expected {
            #expect(CoreUnanswered.reason(of: core) == model)
        }
    }

    @Test func theCoreIsToldAnExpiryOnlyWhenTheSignInCarriesOne() {
        #expect(UsersBridge.milliseconds(of: Date(timeIntervalSince1970: 5_106_401)) == 5_106_401_000)
        #expect(UsersBridge
            .milliseconds(of: Date(timeIntervalSince1970: 1_765_000_000.4567)) == 1_765_000_000_457)
        #expect(UsersBridge.milliseconds(of: nil) == nil)
    }
}
