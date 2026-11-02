import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Signs users in and out of the open core and reads what it knows about them.
///
/// Sign-in and refresh talk to PSN and block a core thread, so they run on a dispatch queue while the calling
/// task waits; cancelling the task cancels the core request. Account ids cross as `ChiakiModels/AccountID`,
/// so the core is never handed bytes of the wrong length.
public struct UsersBridge: Sendable {
    private final class QRReceiver: @unchecked Sendable {
        let progress: @Sendable (QRSignInProgress) -> Void

        init(progress: @escaping @Sendable (QRSignInProgress) -> Void) {
            self.progress = progress
        }
    }

    private final class SignIn: @unchecked Sendable {
        let npsso: SecretBytes
        private let expiry: chiaki_bridge.Milliseconds
        private let deviceID: String
        private let correlation: String
        private let account: AccountID?

        init(
            npsso: consuming SecretBytes,
            validUntil: Date?,
            deviceID: String,
            correlationID: UUID,
            again account: AccountID?
        ) {
            self.npsso = npsso
            expiry = UsersBridge.milliseconds(of: validUntil).map { chiaki_bridge.Milliseconds($0) }
                ?? chiaki_bridge.Milliseconds()
            self.deviceID = deviceID
            correlation = correlationID.uuidString.lowercased()
            self.account = account
        }

        func start(_ request: chiaki_bridge.Request, npsso: UnsafePointer<CChar>) -> chiaki_bridge
            .SignInOutcome {
            guard let account else {
                return chiaki_bridge.UsersBridge.sign_in(
                    request, npsso, expiry, std.string(deviceID), std.string(correlation)
                )
            }
            return chiaki_bridge.UsersBridge.sign_in_again(
                request, UsersBridge.vector(account), npsso, expiry, std.string(deviceID),
                std.string(correlation)
            )
        }
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// Loads every saved user into the core.
    ///
    /// - Returns: How many saved users were admitted and rejected, or `nil` when the core is closed or the
    ///   store could not be read.
    public func welcomeBack() -> (admitted: Int, rejected: Int)? {
        guard let welcomed = chiaki_bridge.UsersBridge.welcome_back().value else {
            return nil
        }
        return (Int(welcomed.admitted), Int(welcomed.rejected))
    }

    /// Every user the core holds.
    ///
    /// - Returns: The users, empty when the core is closed.
    public func everyone() -> [SignedInUser] {
        chiaki_bridge.UsersBridge.everyone().compactMap(Self.user(of:))
    }

    /// One user the core holds.
    ///
    /// - Parameter account: The user's account.
    /// - Returns: The user, or `nil` when the core does not hold it.
    public func find(_ account: AccountID) -> SignedInUser? {
        chiaki_bridge.UsersBridge.find(Self.vector(account)).value.flatMap(Self.user(of:))
    }

    /// The time on the PlayStation Network servers, from the last reply the core saw.
    ///
    /// - Returns: The time, or `nil` until a reply has been seen.
    public func serverTime() -> Date? {
        chiaki_bridge.UsersBridge.server_time().value.map(Timestamp.date(milliseconds:))
    }

    /// Signs a user in with an NPSSO, or signs a held user in again.
    ///
    /// - Parameters:
    ///   - npsso: The NPSSO. It is consumed and wiped when the attempt ends.
    ///   - validUntil: When the NPSSO expires, when known.
    ///   - deviceID: The installation's device id.
    ///   - correlationID: The id tying this sign-in's requests together.
    ///   - account: The held user to sign in again, or `nil` for a new sign-in.
    /// - Returns: The signed-in user.
    /// - Throws: The `ChiakiModels/CoreSignInFailure` that ended the attempt.
    public func signIn(
        npsso: consuming SecretBytes,
        validUntil: Date?,
        deviceID: String,
        correlationID: UUID,
        again account: AccountID?
    ) async throws(CoreSignInFailure) -> SignedInUser {
        let attempt = SignIn(
            npsso: npsso,
            validUntil: validUntil,
            deviceID: deviceID,
            correlationID: correlationID,
            again: account
        )
        let result = await CoreCancellation.run { request in
            attempt.npsso.withUnsafeCString { npsso in
                Self.result(of: attempt.start(request, npsso: npsso))
            }
        }
        return try result.get()
    }

    /// Signs a user in without a password, by a QR code another device scans and approves.
    ///
    /// The core issues replacement codes as they expire and reports every step through `progress`, on the core
    /// thread. The NPSSO the approval yields stays inside the core.
    ///
    /// - Parameters:
    ///   - deviceID: The installation's device id.
    ///   - correlationID: The id tying this sign-in's requests together.
    ///   - progress: Told each step before the sign-in ends; it must return quickly.
    /// - Returns: The signed-in user.
    /// - Throws: The `ChiakiModels/CoreSignInFailure` that ended the attempt; a cancelled task throws
    ///   `ChiakiModels/CoreSignInFailure/cancelled`.
    public func signInWithQR(
        deviceID: String,
        correlationID: UUID,
        progress: @escaping @Sendable (QRSignInProgress) -> Void
    ) async throws(CoreSignInFailure) -> SignedInUser {
        let receiver = QRReceiver(progress: progress)
        let correlation = correlationID.uuidString.lowercased()
        let sink: chiaki_bridge.QrSignInSink = { attempt, step, url, code, expiresAt, context in
            guard let context else {
                return
            }
            let receiver = Unmanaged<QRReceiver>.fromOpaque(context).takeUnretainedValue()
            guard let reported = UsersBridge.progress(
                attempt: attempt, step: step, url: url, code: code, expiresAtMilliseconds: expiresAt
            ) else {
                return
            }
            receiver.progress(reported)
        }
        let result = await CoreCancellation.run { request in
            withExtendedLifetime(receiver) {
                Self.result(of: chiaki_bridge.UsersBridge.sign_in_with_qr(
                    request, std.string(deviceID), std.string(correlation), sink,
                    Unmanaged.passUnretained(receiver).toOpaque()
                ))
            }
        }
        return try result.get()
    }

    /// The model progress of one QR sign-in step the core reported.
    ///
    /// - Parameters:
    ///   - attempt: The code the step belongs to.
    ///   - step: The core's step, as its raw value.
    ///   - url: The address to show as the QR code.
    ///   - code: The six digits shown beside the code.
    ///   - expiresAtMilliseconds: When the code expires, in Unix milliseconds, or a negative value when unknown.
    /// - Returns: The progress, or `nil` for a final step, which the sign-in's result reports, or a code
    ///   without an address.
    static func progress(
        attempt: UInt32,
        step: UInt8,
        url: UnsafePointer<CChar>?,
        code: UnsafePointer<CChar>?,
        expiresAtMilliseconds: Int64
    ) -> QRSignInProgress? {
        typealias Step = libchiaking.users.QrSignInStep
        switch step {
        case UInt8(Step.preparing.rawValue):
            return .preparing
        case UInt8(Step.signing_in.rawValue):
            return .signingIn
        case UInt8(Step.awaiting_approval.rawValue):
            guard let url, let code, url.pointee != 0 else {
                return nil
            }
            let expiry = expiresAtMilliseconds < 0
                ? nil
                : Timestamp.date(milliseconds: expiresAtMilliseconds)
            return .awaitingApproval(QRSignInCode(
                attempt: Int(attempt), approvalURL: String(cString: url), userCode: String(cString: code),
                expiresAt: expiry
            ))
        default:
            return nil
        }
    }

    /// Adds a user by account id, without a PSN sign-in.
    ///
    /// - Parameters:
    ///   - account: The user's account.
    ///   - name: The name to show for the user.
    /// - Returns: The added user, or `nil` when the core is closed or refused the name.
    public func addHomeUser(_ account: AccountID, name: String) -> SignedInUser? {
        let outcome = chiaki_bridge.UsersBridge.add_home_user(Self.vector(account), std.string(name))
        switch outcome.kind() {
        case .added:
            return Self.user(of: outcome.user())
        case .refused, .invalid:
            return nil
        }
    }

    /// Signs a user out and forgets their saved sign-in.
    ///
    /// - Parameter account: The user's account.
    /// - Returns: `true` when the user was signed out.
    @discardableResult
    public func signOut(_ account: AccountID) -> Bool {
        chiaki_bridge.UsersBridge.sign_out(Self.vector(account)).value == nil
    }

    /// Renews a user's sign-in and fetches their profile and membership.
    ///
    /// - Parameter account: The user's account.
    /// - Returns: The user as the core now knows them.
    /// - Throws: ``CoreUnanswered`` when PSN did not answer; a cancelled task throws its
    ///   ``CoreUnanswered/Reason/cancelled`` reason.
    public func refresh(_ account: AccountID) async throws(CoreUnanswered) -> SignedInUser {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.UsersBridge.refresh(request, Self.vector(account)))
        }
        return try result.get()
    }

    /// The Unix time in milliseconds the core is told an NPSSO expires at.
    ///
    /// - Parameter date: When the NPSSO expires, when known.
    /// - Returns: The time rounded to the nearest millisecond, or `nil` when the expiry is not known.
    static func milliseconds(of date: Date?) -> Int64? {
        date.map(Timestamp.milliseconds(of:))
    }

    /// The model user of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The user, or `nil` when the account id is not eight bytes.
    static func user(of facts: chiaki_bridge.UserFacts) -> SignedInUser? {
        guard let account = AccountID(bytes: Array(facts.account_id)) else {
            return nil
        }
        let region: AccountRegion? = if let country = facts.country.value,
                                        let language = facts.language.value {
            AccountRegion(country: String(country), language: String(language))
        } else {
            nil
        }
        return SignedInUser(
            accountID: account,
            onlineID: String(facts.online_id),
            hasPSNAccount: facts.has_psn_account,
            state: state(of: facts.sign_in_state),
            tier: facts.tier.value.map(tier(of:)),
            plusMember: facts.plus_member.value,
            avatarURL: facts.avatar_url.value.flatMap { URL(string: String($0)) },
            region: region
        )
    }

    /// The model result of a sign-in outcome.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The signed-in user or the failure.
    static func result(of outcome: chiaki_bridge.SignInOutcome) -> Result<SignedInUser, CoreSignInFailure> {
        switch outcome.kind() {
        case .signed_in:
            guard let user = user(of: outcome.user()) else {
                return .failure(.malformed)
            }
            return .success(user)
        case .different_account:
            let other = outcome.other_account()
            return .failure(.differentAccount(
                AccountID(bytes: Array(other.account_id)),
                onlineID: String(other.online_id)
            ))
        case .refused:
            return .failure(failure(ofRefusal: outcome.refusal()))
        case .failed:
            let failed = outcome.failure()
            return .failure(failure(of: failed.kind, httpStatus: failed.http_status.value.map(Int.init)))
        }
    }

    /// The model result of a refresh outcome.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The refreshed user or why PSN did not answer.
    static func result(of outcome: chiaki_bridge.RefreshOutcome) -> Result<SignedInUser, CoreUnanswered> {
        switch outcome.kind() {
        case .refreshed:
            guard let user = user(of: outcome.user()) else {
                return .failure(CoreUnanswered(reason: .unavailable))
            }
            return .success(user)
        case .unanswered:
            let why = outcome.why_unanswered()
            return .failure(CoreUnanswered(
                reason: CoreUnanswered.reason(of: why.reason),
                httpStatus: Int(why.http_status)
            ))
        case .refused:
            return .failure(CoreUnanswered(reason: unanswered(of: outcome.refusal())))
        }
    }

    /// The model failure of a refusal the bridge made before the core ran.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The failure.
    static func failure(ofRefusal refusal: chiaki_bridge.UsersRefusal) -> CoreSignInFailure {
        switch refusal {
        case .core_closed:
            .coreClosed
        case .unknown_user:
            .unknownUser
        case .invalid_device:
            .invalidDevice
        case .not_saved:
            .unavailable(httpStatus: nil)
        }
    }

    /// The model failure of a core sign-in failure.
    ///
    /// - Parameters:
    ///   - kind: The core's kind of failure.
    ///   - httpStatus: The status of the reply behind it, when there was one.
    /// - Returns: The failure.
    static func failure(of kind: libchiaking.users.SignInErrorKind,
                        httpStatus: Int?) -> CoreSignInFailure {
        switch kind {
        case .invalid_request:
            .invalidRequest
        case .cancelled:
            .cancelled
        case .transport:
            .transport
        case .rejected:
            .rejected
        case .rate_limited:
            .rateLimited
        case .unavailable:
            .unavailable(httpStatus: httpStatus)
        case .malformed:
            .malformed
        case .declined:
            .declined
        case .verification_required:
            .verificationRequired
        case .expired:
            .expired
        case .layout_changed:
            .layoutChanged
        }
    }

    /// The unanswered reason of a refusal the bridge made before the core ran.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The reason.
    static func unanswered(of refusal: chiaki_bridge.UsersRefusal) -> CoreUnanswered.Reason {
        switch refusal {
        case .core_closed:
            .coreClosed
        case .unknown_user:
            .unknownUser
        case .invalid_device, .not_saved:
            .unavailable
        }
    }

    /// The model sign-in state of a core state.
    ///
    /// - Parameter state: The core's state.
    /// - Returns: The model state.
    static func state(of state: libchiaking.users.SignInState) -> SignInState {
        switch state {
        case .signed_in:
            .signedIn
        case .store_access_lapsed:
            .storeAccessLapsed
        case .expired:
            .signInExpired
        case .signed_out:
            .signedOut
        }
    }

    /// The model tier of a core tier.
    ///
    /// - Parameter tier: The core's tier.
    /// - Returns: The model tier.
    static func tier(of tier: libchiaking.users.Tier) -> PlusTier {
        switch tier {
        case .none:
            .none
        case .essential:
            .essential
        case .extra:
            .extra
        case .premium:
            .premium
        }
    }

    /// Copies an account id into the bridge's byte vector.
    ///
    /// - Parameter account: The account.
    /// - Returns: Its eight bytes.
    static func vector(_ account: AccountID) -> chiaki_bridge.Bytes {
        chiaki_bridge.Bytes(account.bytes)
    }
}
