import ComposableArchitecture
import Foundation
import Testing
import ChiakiClients
import ChiakiModels
@testable import ChiakiFeatures
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private let player = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let playerAccount = Data([40, 0, 0, 0, 0, 0, 0, 0])
private let obtained = Date(timeIntervalSince1970: 1_700_000_000)
private let appToken = HeldCredential(
    kind: .appToken, held: true, kept: .withTheUser, state: .usable, obtainedAt: obtained,
    expiresAt: obtained.addingTimeInterval(3600), scopes: "psn:mobile.v2.core", lastReplyStatus: 200,
    usedFor: [.profile, .membership]
)
private let seed = HeldCredential(
    kind: .signInSeed, held: true, kept: .withTheUser, state: .unverified,
    usedFor: [.exchangingTokens]
)
private let libraryToken = HeldCredential(kind: .libraryToken, held: false, usedFor: [.ownedLibrary])
private let accounts = [
    TokenAccount(
        id: player,
        name: "Player",
        accountID: playerAccount,
        credentials: [seed, appToken, libraryToken]
    )
]
private let appTarget = TokensReducer.Target(account: player, kind: .appToken)
private let seedTarget = TokensReducer.Target(account: player, kind: .signInSeed)
private let libraryTarget = TokensReducer.Target(account: player, kind: .libraryToken)

private final class Vault: @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    private var revealed: [CredentialKind] = []
    private var handed: [RevealedSecret] = []

    func ask(_ reason: String) {
        lock.withLock {
            asked.append(reason)
        }
    }

    func reveal(_ kind: CredentialKind) -> RevealedSecret {
        let secret = Array("not-a-real-\(kind)".utf8).withUnsafeBytes { RevealedSecret(copying: $0) }
        lock.withLock {
            revealed.append(kind)
            handed.append(secret)
        }
        return secret
    }

    var reasons: [String] {
        lock.withLock {
            asked
        }
    }

    var reveals: [CredentialKind] {
        lock.withLock {
            revealed
        }
    }

    var secrets: [RevealedSecret] {
        lock.withLock {
            handed
        }
    }
}

private func ready() -> TokensReducer.State {
    var state = TokensReducer.State()
    state.accounts = accounts
    state.phase = .ready
    return state
}

private func useTokens(_ vault: Vault, granting: Bool, in dependencies: inout DependencyValues) {
    dependencies.accounts.tokenAccounts = { accounts }
    dependencies.accounts.authenticateOwner = { reason in
        vault.ask(reason)
        return granting
    }
    dependencies.accounts.revealToken = { _, kind in
        .success(vault.reveal(kind))
    }
}

@MainActor @Test func tokensListEachAccountsCredentialsWithoutRevealingAny() async {
    let vault = Vault()
    let store = TestStore(initialState: TokensReducer.State()) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        useTokens(vault, granting: true, in: &$0)
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.loaded(UUID(0), accounts)) {
        $0.accounts = accounts
        $0.phase = .ready
    }
    #expect(store.state.holds(appTarget) && !store.state.holds(libraryTarget))
    #expect(vault.reasons.isEmpty && vault.reveals.isEmpty)
}

@MainActor @Test func tokensSayWhenSavedAccountsCannotBeRead() async {
    struct Unreadable: Error {}
    let store = TestStore(initialState: TokensReducer.State()) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.accounts.tokenAccounts = {
            throw Unreadable()
        }
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.failed(UUID(0))) {
        $0.phase = .failed(.settingsTokensAccountsUnreadable)
    }
}

@MainActor @Test func aCredentialIsRevealedOnlyAfterAuthenticationAndHiddenAfterThirtySeconds() async {
    let vault = Vault()
    let clock = TestClock()
    let secrets = RevealedSecretStore()
    let store = TestStore(initialState: ready()) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.revealedSecrets = secrets
        $0.continuousClock = clock
        useTokens(vault, granting: true, in: &$0)
    }
    await store.send(.reveal(appTarget)) {
        $0.reveal = .authenticating(appTarget, UUID(0))
    }
    await store.receive(.authenticated(UUID(0))) {
        $0.unlocked = true
    }
    await store.receive(.revealed(UUID(0))) {
        $0.reveal = .shown(appTarget, UUID(0))
        $0.secrets = secrets
    }
    #expect(vault.reasons == ["reveal your PlayStation tokens"])
    #expect(vault.reveals == [.appToken])
    #expect(secrets.holds(OperationID(uuid: UUID(0))))
    #expect(secrets
        .text(for: OperationID(uuid: UUID(0))) == "not-a-real-\(CredentialKind.appToken)")
    await clock.advance(by: .seconds(29))
    #expect(secrets.text(for: OperationID(uuid: UUID(0))) != nil)
    await clock.advance(by: .seconds(1))
    await store.receive(.expired(UUID(0))) {
        $0.reveal = .hidden
        $0.secrets = nil
    }
    #expect(!secrets.holds(OperationID(uuid: UUID(0))))
    #expect(!vault.secrets.map(\.isWiped).contains(false))
}

@MainActor @Test func aDeniedAuthenticationRevealsNothingAndNeverAsksTheCore() async {
    let vault = Vault()
    let secrets = RevealedSecretStore()
    let store = TestStore(initialState: ready()) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.revealedSecrets = secrets
        $0.continuousClock = TestClock()
        useTokens(vault, granting: false, in: &$0)
    }
    await store.send(.reveal(seedTarget)) {
        $0.reveal = .authenticating(seedTarget, UUID(0))
    }
    await store.receive(.denied(UUID(0))) {
        $0.reveal = .hidden
    }
    #expect(vault.reasons == ["reveal your PlayStation tokens"])
    #expect(vault.reveals.isEmpty && vault.secrets.isEmpty)
    #expect(!secrets.holds(OperationID(uuid: UUID(0))))
}

@MainActor private func revealAppToken(
    in store: TestStoreOf<TokensReducer>,
    secrets: RevealedSecretStore,
    operation: Int
) async {
    await store.send(.reveal(appTarget)) {
        $0.reveal = .authenticating(appTarget, UUID(operation))
    }
    await store.receive(.authenticated(UUID(operation))) {
        $0.unlocked = true
    }
    await store.receive(.revealed(UUID(operation))) {
        $0.reveal = .shown(appTarget, UUID(operation))
        $0.secrets = secrets
    }
}

@MainActor @Test func revealingAnotherCredentialHidesTheOneBefore() async {
    let vault = Vault()
    let secrets = RevealedSecretStore()
    let store = TestStore(initialState: ready()) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.revealedSecrets = secrets
        $0.continuousClock = TestClock()
        useTokens(vault, granting: true, in: &$0)
    }
    await revealAppToken(in: store, secrets: secrets, operation: 0)
    await store.send(.reveal(seedTarget)) {
        $0.reveal = .authenticating(seedTarget, UUID(1))
    }
    await store.receive(.revealed(UUID(1))) {
        $0.reveal = .shown(seedTarget, UUID(1))
        $0.secrets = secrets
    }
    #expect(vault.reasons == ["reveal your PlayStation tokens"])
    #expect(vault.reveals == [.appToken, .signInSeed])
    #expect(vault.secrets.map(\.isWiped) == [true, true])
    #expect(!secrets.holds(OperationID(uuid: UUID(0))))
    #expect(secrets
        .text(for: OperationID(uuid: UUID(1))) == "not-a-real-\(CredentialKind.signInSeed)")
    await store.send(.hide) {
        $0.reveal = .hidden
        $0.secrets = nil
    }
    await store.finish()
    #expect(!secrets.holds(OperationID(uuid: UUID(1))))
    #expect(!vault.secrets.map(\.isWiped).contains(false))
    await store.send(.lock) {
        $0.unlocked = false
    }
    await revealAppToken(in: store, secrets: secrets, operation: 2)
    #expect(vault.reasons.count == 2)
    await store.send(.lock) {
        $0.unlocked = false
        $0.reveal = .hidden
        $0.secrets = nil
    }
    await store.finish()
    #expect(!secrets.holds(OperationID(uuid: UUID(2))))
}

@MainActor @Test func aCredentialThatIsNotHeldIsNeverAskedFor() async {
    let vault = Vault()
    let secrets = RevealedSecretStore()
    let store = TestStore(initialState: ready()) {
        TokensReducer()
    } withDependencies: {
        $0.revealedSecrets = secrets
        useTokens(vault, granting: true, in: &$0)
    }
    await store.send(.reveal(libraryTarget))
    await store.send(.reveal(TokensReducer.Target(account: UUID(9), kind: .appToken)))
    #expect(vault.reasons.isEmpty && vault.reveals.isEmpty)
}

@MainActor @Test func aRefusalFromTheCoreIsShownInPlaceOfTheValue() async {
    let secrets = RevealedSecretStore()
    let store = TestStore(initialState: ready()) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.revealedSecrets = secrets
        $0.continuousClock = TestClock()
        $0.accounts.tokenAccounts = { accounts }
        $0.accounts.authenticateOwner = { _ in true }
        $0.accounts.revealToken = { _, _ in .failure(NotRevealed(.signedOut)) }
    }
    await store.send(.reveal(appTarget)) {
        $0.reveal = .authenticating(appTarget, UUID(0))
    }
    await store.receive(.authenticated(UUID(0))) {
        $0.unlocked = true
    }
    await store.receive(.notRevealed(UUID(0), .signedOut)) {
        $0.reveal = .refused(appTarget, .settingsTokensNotRevealedSignedOut)
    }
    #expect(!secrets.holds(OperationID(uuid: UUID(0))))
    await store.send(.hide) {
        $0.reveal = .hidden
    }
}

@MainActor @Test func leavingTheAppHidesAShownCredentialButNotAPendingPrompt() async {
    var shown = ready()
    shown.reveal = .shown(appTarget, UUID(0))
    let store = TestStore(initialState: shown) {
        TokensReducer()
    }
    await store.send(.resignedActive) {
        $0.reveal = .hidden
    }
    await store.send(.resignedActive)
    await store.send(.hide)
    var pending = ready()
    pending.reveal = .authenticating(appTarget, UUID(0))
    let prompting = TestStore(initialState: pending) {
        TokensReducer()
    }
    await prompting.send(.resignedActive)
    await prompting.send(.revealed(UUID(7)))
    await prompting.send(.expired(UUID(0)))
    await prompting.send(.hide) {
        $0.reveal = .hidden
    }
}

@MainActor @Test func aReloadHidesACredentialThatIsNoLongerHeld() async {
    var shown = ready()
    shown.reveal = .shown(appTarget, UUID(5))
    let store = TestStore(initialState: shown) {
        TokensReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.accounts.tokenAccounts = {
            []
        }
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.loaded(UUID(0), [])) {
        $0.accounts = []
        $0.phase = .ready
        $0.reveal = .hidden
    }
}

@MainActor @Test func lockingWipesTheHeldSecret() async {
    let secrets = RevealedSecretStore()
    var bytes: [UInt8] = Array("not-a-real-token".utf8)
    secrets.keep(SecretBytes(wiping: &bytes), for: OperationID(uuid: UUID(0)))
    var shown = ready()
    shown.reveal = .shown(appTarget, UUID(0))
    shown.unlocked = true
    shown.secrets = secrets
    let store = TestStore(initialState: shown) {
        TokensReducer()
    } withDependencies: {
        $0.revealedSecrets = secrets
    }
    await store.send(.lock) {
        $0.unlocked = false
        $0.reveal = .hidden
        $0.secrets = nil
    }
    #expect(!secrets.holds(OperationID(uuid: UUID(0))))
}

@Test func theSecretStoreHoldsOnlyTheLatestRevealAndWipesTheRest() {
    let secrets = RevealedSecretStore()
    var first: [UInt8] = Array("first".utf8)
    secrets.keep(SecretBytes(wiping: &first), for: OperationID(uuid: UUID(1)))
    #expect(secrets.text(for: OperationID(uuid: UUID(1))) == "first")
    #expect(secrets.text(for: OperationID(uuid: UUID(0))) == nil)
    secrets.discard(OperationID(uuid: UUID(0)))
    #expect(secrets.holds(OperationID(uuid: UUID(1))))
    var second: [UInt8] = Array("second".utf8)
    secrets.keep(SecretBytes(wiping: &second), for: OperationID(uuid: UUID(2)))
    #expect(!secrets.holds(OperationID(uuid: UUID(1))))
    #expect(secrets.text(for: OperationID(uuid: UUID(2))) == "second")
    secrets.discard()
    #expect(!secrets.holds(OperationID(uuid: UUID(2))))
}

@Test func everyCredentialStateAndUseHasItsOwnLabel() {
    let kinds = CredentialKind.allCases
    let states = CredentialState.allCases
    let uses = CredentialUse.allCases
    #expect(kinds.map { String(localized: $0.title) } == [
        "NPSSO", "App token", "App refresh token", "Remote Play token", "Remote Play refresh token",
        "Library token", "Old service checkout token"
    ])
    #expect(states.map { String(localized: $0.label) } == [
        "Usable", "Expired", "Refused", "Never obtained", "Unverified"
    ])
    #expect(uses.map { String(localized: $0.label) } == [
        "Exchanging tokens", "Cloud streaming authorisation", "Old service store", "Profile", "Membership",
        "Storefront check", "Console titles", "Starting a title", "Owned copy concepts",
        "Renewing the app token", "Account consoles", "Internet play", "Renewing the Remote Play token",
        "Owned library", "Old service checkout"
    ])
    let messages = Set(NotRevealed.Reason.allCases.map { String(localized: $0.message) })
    #expect(messages.count == NotRevealed.Reason.allCases.count)
    #expect(SettingsRoute.allCases.contains(.tokens))
    #expect(String(localized: SettingsRoute.tokens.title) == "Tokens")
}

@Test func aCredentialRowStatesItsFactsAndNeverAValue() {
    let locale = Locale(identifier: "en_GB")
    let held = HeldCredentialPresentation(appToken, locale: locale, timeZone: .gmt)
    #expect(String(localized: held.title) == "App token")
    #expect(String(localized: held.status) == "Usable")
    #expect(held.held)
    #expect(held.facts.map { String(localized: $0.label) } == [
        "Obtained", "Expires", "Scopes", "Last reply", "Used for"
    ])
    #expect(held.facts.map(\.value) == [
        "14 Nov 2023 at 22:13", "14 Nov 2023 at 23:13", "psn:mobile.v2.core", "HTTP 200",
        "Profile, Membership"
    ])
    let missing = HeldCredentialPresentation(libraryToken, locale: locale, timeZone: .gmt)
    #expect(String(localized: missing.status) == "Never obtained")
    #expect(!missing.held)
    #expect(missing.facts.map(\.value) == ["Unknown", "Unknown", "None", "None", "Owned library"])
    let lapsed = HeldCredentialPresentation(
        HeldCredential(kind: .appToken, held: false, state: .expired), locale: locale, timeZone: .gmt
    )
    #expect(String(localized: lapsed.status) == "Not held, expired")
    #expect(lapsed.facts.last?.value == "Nothing")
}

@Test func aSavedCredentialShowsItsDatesAndReadsExpiredOnceTheCoreSaysSo() {
    let locale = Locale(identifier: "en_GB")
    let seed = HeldCredentialPresentation(
        HeldCredential(
            kind: .signInSeed, held: true, kept: .withTheUser, state: .unverified, obtainedAt: obtained,
            expiresAt: obtained.addingTimeInterval(86400)
        ),
        locale: locale, timeZone: .gmt
    )
    #expect(String(localized: seed.title) == "NPSSO" && String(localized: seed.status) == "Unverified")
    #expect(seed.facts.prefix(2).map(\.value) == ["14 Nov 2023 at 22:13", "15 Nov 2023 at 22:13"])
    for kind in [CredentialKind.signInSeed, .appRefreshToken, .remotePlayRefreshToken] {
        let lapsed = HeldCredentialPresentation(
            HeldCredential(
                kind: kind, held: true, kept: .withTheUser, state: .expired, obtainedAt: obtained,
                expiresAt: obtained.addingTimeInterval(3600)
            ),
            locale: locale, timeZone: .gmt
        )
        #expect(lapsed.held && String(localized: lapsed.status) == "Expired")
        #expect(lapsed.facts.prefix(2).map(\.value) == ["14 Nov 2023 at 22:13", "14 Nov 2023 at 23:13"])
    }
    let undated = HeldCredentialPresentation(
        HeldCredential(kind: .remotePlayRefreshToken, held: true, kept: .withTheUser, state: .usable),
        locale: locale, timeZone: .gmt
    )
    #expect(String(localized: undated.status) == "Usable")
    #expect(undated.facts.prefix(2).map(\.value) == ["Unknown", "Unknown"])
}
