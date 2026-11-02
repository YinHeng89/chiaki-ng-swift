import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct SignInFeatureTests {
    let profile = AccountProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Player", method: .npsso, accountID: AccountID(value: 7)
    )

    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    static var browser: SignInFeature.State {
        var state = SignInFeature.State()
        state.method = .browser
        return state
    }

    func code(_ attempt: Int) -> QRSignInCode {
        QRSignInCode(
            attempt: attempt, approvalURL: "https://example.invalid/approve/\(attempt)",
            userCode: "01234\(attempt)", expiresAt: nil
        )
    }

    func store(
        _ state: SignInFeature.State = Self.browser,
        capture: @escaping @Sendable (
            @escaping @Sendable (SignInStage) -> Void
        ) async throws(SignInFailure) -> SignInCapture,
        signIn: @escaping @Sendable (UUID, consuming SignInCapture) async -> Result<
            AccountProfile,
            SignInFailure
        >
    ) -> TestStoreOf<SignInFeature> {
        TestStore(initialState: state) {
            SignInFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.accounts.captureSignIn = capture
            $0.accounts.signIn = signIn
        }
    }

    func qrStore(
        _ state: SignInFeature.State = SignInFeature.State(),
        signInWithQR: @escaping @Sendable (UUID, @escaping @Sendable (QRSignInProgress) -> Void) async
            -> Result<
                AccountProfile,
                SignInFailure
            >
    ) -> TestStoreOf<SignInFeature> {
        TestStore(initialState: state) {
            SignInFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.accounts.signInWithQR = signInWithQR
        }
    }

    nonisolated static func captured(_ token: String = "synthetic-npsso") throws(SignInFailure)
        -> SignInCapture {
        guard let npsso = NPSSO(token) else {
            throw .unreadableResponse
        }
        return SignInCapture(npsso: npsso, expiresAt: nil, expirySource: .cookie)
    }

    @Test func aCapturedNPSSOIsSignedInWithoutLeavingTheEffect() async {
        let profile = profile
        let store = store { _ throws(SignInFailure) in
            try Self.captured()
        } signIn: { requested, capture in
            #expect(requested == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
            #expect(capture.expirySource == .unknown)
            let expected = NPSSO("synthetic-npsso")!
            let equal = capture.npsso.isEqual(to: expected)
            #expect(equal)
            return .success(profile)
        }
        await store.send(.view(.start)) {
            $0.phase = .opening(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.receive(.captured(operation(0))) {
            $0.phase = .signingIn(operation(0))
        }
        await store.receive(.finished(operation(0), .success(profile))) {
            $0.phase = .idle
        }
        await store.receive(.delegate(.signedIn(profile)))
    }

    @Test func reconnectingSignsInTheSameAccountAgain() async {
        let profile = profile
        let reconnecting = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
        let store = store(SignInFeature.State(reconnecting: reconnecting)) { _ throws(SignInFailure) in
            try Self.captured()
        } signIn: { requested, _ in
            #expect(requested == reconnecting)
            return .success(profile)
        }
        await store.send(.view(.start)) {
            $0.phase = .opening(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.receive(.captured(operation(0))) {
            $0.phase = .signingIn(operation(0))
        }
        await store.receive(.finished(operation(0), .success(profile))) {
            $0.phase = .idle
        }
        await store.receive(.delegate(.signedIn(profile)))
    }

    @Test func aRefusedCaptureShowsItsFailureAndNeverSignsIn() async {
        let store = store { _ throws(SignInFailure) in
            throw .navigationFailed
        } signIn: { _, _ in
            Issue.record("A failed capture must not sign in")
            return .failure(.storage)
        }
        await store.send(.view(.start)) {
            $0.phase = .opening(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.receive(.finished(operation(0), .failure(.navigationFailed))) {
            $0.phase = .failed(.navigationFailed)
        }
    }

    @Test func goingBackCancelsTheAttemptAndIgnoresItsLateResult() async {
        let profile = profile
        let clock = TestClock()
        let store = store { _ throws(SignInFailure) in
            try? await clock.sleep(for: .seconds(60))
            throw .cancelled
        } signIn: { _, _ in
            .success(profile)
        }
        await store.send(.view(.start)) {
            $0.phase = .opening(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.send(.view(.back)) {
            $0.phase = .idle
        }
        await store.receive(.delegate(.left))
        await store.send(.finished(operation(0), .success(profile)))
        await store.send(.stageReported(operation(0), .completing))
    }

    @Test func closingThePageStaysOnTheScreen() async {
        let clock = TestClock()
        let store = store { _ throws(SignInFailure) in
            try? await clock.sleep(for: .seconds(60))
            throw .cancelled
        } signIn: { _, _ in
            .failure(.storage)
        }
        await store.send(.view(.start)) {
            $0.phase = .opening(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.send(.view(.closePage)) {
            $0.phase = .idle
        }
        await store.send(.view(.closePage))
    }

    @Test func theAcknowledgementTicksAndClearsAndSurvivesSwitchingMethods() async {
        let store = qrStore { _, _ in
            .failure(.cancelled)
        }
        store.exhaustivity = .off
        await store.send(.view(.acknowledge)) {
            $0.acknowledged = true
        }
        await store.send(.view(.choose(.browser))) {
            $0.method = .browser
        }
        #expect(store.state.acknowledged)
        await store.send(.view(.acknowledge)) {
            $0.acknowledged = false
        }
    }

    @Test func aSecuredPageShowsItsCertificateUntilThePageCloses() async {
        let clock = TestClock()
        let page = SignInPage(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let certificate = SignInCertificate(
            host: "io.playstation.com", subject: "io.playstation.com", organization: "Example Org",
            location: "San Mateo, California, US", issuer: "Example CA", fingerprint: "AB CD"
        )
        let store = store { stages throws(SignInFailure) in
            stages(.browsing(page))
            stages(.secured(page, certificate))
            try? await clock.sleep(for: .seconds(60))
            throw .cancelled
        } signIn: { _, _ in
            .failure(.storage)
        }
        await store.send(.view(.start)) {
            $0.phase = .opening(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.receive(.stageReported(operation(0), .browsing(page))) {
            $0.phase = .browsing(operation(0), page)
        }
        await store.receive(.stageReported(operation(0), .secured(page, certificate))) {
            $0.certificate = certificate
        }
        #expect(certificate.verifiedParty == "Example Org, San Mateo, California, US")
        await store.send(.view(.closePage)) {
            $0.phase = .idle
            $0.certificate = nil
        }
    }

    @Test func aNewAccountShowsEachCodeAndSignsInOnceOneIsApproved() async {
        let profile = profile
        let first = code(1)
        let second = code(2)
        let store = qrStore { requested, progress in
            #expect(requested == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
            progress(.preparing)
            progress(.awaitingApproval(first))
            progress(.preparing)
            progress(.awaitingApproval(second))
            progress(.signingIn)
            return .success(profile)
        }
        #expect(store.state.method == .qrCode)
        #expect(store.state.offersQRCode)
        await store.send(.view(.appeared)) {
            $0.phase = .preparingCode(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.receive(.codeReported(operation(0), .preparing))
        await store.receive(.codeReported(operation(0), .awaitingApproval(first))) {
            $0.phase = .showingCode(operation(0), first)
        }
        await store.receive(.codeReported(operation(0), .preparing)) {
            $0.phase = .preparingCode(operation(0))
        }
        await store.receive(.codeReported(operation(0), .awaitingApproval(second))) {
            $0.phase = .showingCode(operation(0), second)
        }
        await store.receive(.codeReported(operation(0), .signingIn)) {
            $0.phase = .signingIn(operation(0))
        }
        await store.receive(.finished(operation(0), .success(profile))) {
            $0.phase = .idle
        }
        await store.receive(.delegate(.signedIn(profile)))
    }

    @Test func choosingTheSignInPageAbandonsTheCodeAndIgnoresItsLateSteps() async {
        let profile = profile
        let clock = TestClock()
        let store = qrStore { _, _ in
            try? await clock.sleep(for: .seconds(60))
            return .failure(.cancelled)
        }
        await store.send(.view(.appeared)) {
            $0.phase = .preparingCode(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.send(.view(.choose(.browser))) {
            $0.method = .browser
            $0.phase = .idle
        }
        await store.send(.codeReported(operation(0), .awaitingApproval(code(1))))
        await store.send(.finished(operation(0), .success(profile)))
        await store.send(.view(.appeared))
    }

    @Test func choosingAQRCodeFromTheSignInPageShowsACodeAtOnce() async {
        let clock = TestClock()
        let store = qrStore(Self.browser) { _, _ in
            try? await clock.sleep(for: .seconds(60))
            return .failure(.cancelled)
        }
        await store.send(.view(.choose(.qrCode))) {
            $0.method = .qrCode
            $0.phase = .preparingCode(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.send(.view(.back)) {
            $0.phase = .idle
        }
        await store.receive(.delegate(.left))
    }

    @Test func aFailedQRSignInShowsWhyAndOffersANewCode() async {
        let store = qrStore { _, _ in
            .failure(.navigationFailed)
        }
        await store.send(.view(.appeared)) {
            $0.phase = .preparingCode(operation(0))
        }
        await store.receive(.delegate(.started))
        await store.receive(.finished(operation(0), .failure(.navigationFailed))) {
            $0.phase = .failed(.navigationFailed)
        }
        await store.send(.view(.appeared))
        await store.send(.view(.start)) {
            $0.phase = .preparingCode(operation(2))
        }
        await store.receive(.delegate(.started))
        await store.receive(.finished(operation(2), .failure(.navigationFailed))) {
            $0.phase = .failed(.navigationFailed)
        }
    }

    @Test func reconnectingKeepsTheSignInPageAndNeverOffersACode() async {
        let reconnecting = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
        let store = qrStore(SignInFeature.State(reconnecting: reconnecting)) { _, _ in
            Issue.record("Reconnecting must not sign in with a QR code")
            return .failure(.storage)
        }
        #expect(store.state.method == .browser)
        #expect(!store.state.offersQRCode)
        await store.send(.view(.appeared))
        await store.send(.view(.choose(.qrCode)))
    }

    @Test func onlyTheSignInPageAndSavingTakeTheScreenOver() {
        let id = operation(0)
        let phases: [(SignInFeature.State.Phase, Bool)] = [
            (.idle, false), (.preparingCode(id), false), (.showingCode(id, code(1)), false),
            (.failed(.rejected), false), (.opening(id), true), (.signingIn(id), true)
        ]
        for (phase, busy) in phases {
            var state = SignInFeature.State()
            state.phase = phase
            #expect(state.isBusy == busy)
        }
    }

    @Test func everySignInFailureHasItsOwnWords() {
        let failures: [SignInFailure] = [
            .cancelled, .browserUnavailable, .codesExpired, .rejected, .rateLimited, .serviceUnavailable,
            .unreachable, .differentAccount, .storage
        ]
        let texts = failures.map(AccountsFailureMessage.text(for:))
        #expect(Set(texts).count == failures.count)
    }
}
