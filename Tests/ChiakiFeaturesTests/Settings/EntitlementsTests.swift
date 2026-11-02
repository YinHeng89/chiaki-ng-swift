@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let account = EntitlementAccount(
    id: UUID(),
    name: "Player",
    accountID: AccountID(value: 0x0101_0101_0101_0101)
)
private let shown = ExplainedTitle(
    game: CloudGame(productId: "UP9000-PPSA09006_00-FULLGAME00000000", name: "Owned", standing: .inLibrary),
    explanation: CatalogExplanation(listed: true, steps: [
        .init(rule: .listedInCatalog, outcome: .passed),
        .init(rule: .ownership, outcome: .passed, ownershipID: "UP9000-PPSA09006_00-FULLGAME00000000")
    ])
)
private let hidden = ExplainedTitle(
    game: CloudGame(
        productId: "UP9000-CUSA09006_00-OLDGAME000000000", name: "Old edition", visible: false,
        hideReason: "not_ps5_native"
    ),
    explanation: CatalogExplanation(listed: false, steps: [
        .init(rule: .ps5Native, outcome: .failed, hides: true, tier: .premium)
    ])
)

@MainActor @Test func entitlementsLoadTheCoreExplanationForEachTitle() async {
    let store = TestStore(initialState: EntitlementsReducer.State()) {
        EntitlementsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.entitlementAccounts = { [account] }
        $0.catalog.explainedTitles = { _, _ in [shown, hidden] }
    }
    await store.send(.appear) {
        $0.phase = .loadingAccounts(UUID(0))
    }
    await store.receive(.accountsLoaded(UUID(0), [account])) {
        $0.accounts = [account]
        $0.account = account.id
        $0.phase = .ready
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(1))
    }
    await store.receive(.reported(UUID(1), nil))
    await store.receive(.loaded(UUID(1), [shown, hidden])) {
        $0.titles = [shown, hidden]
        $0.phase = .loaded
    }
    #expect(store.state.rows.isEmpty)
    await store.send(.service(.psCloud)) {
        $0.service = .psCloud
        $0.selection = shown.id
    }
    await store.send(.filter(.hidden)) {
        $0.filter = .hidden
    }
    #expect(store.state.rows == [hidden])
    #expect(store.state.selected == nil)
    await store.send(.query("old")) {
        $0.query = "old"
    }
    #expect(store.state.rows == [hidden])
}

@MainActor @Test func aFailedEntitlementsLoadShowsItsReasonAndKeepsTheAccount() async {
    var state = EntitlementsReducer.State()
    state.accounts = [account]
    state.account = account.id
    state.phase = .ready
    let store = TestStore(initialState: state) {
        EntitlementsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.entitlementAccounts = { [account] }
        $0.catalog.explainedTitles = { _, _ in
            throw EntitlementsFailure("not signed in")
        }
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.failed(UUID(0), "not signed in")) {
        $0.phase = .failed("not signed in")
    }
    await store.send(.selectAccount(nil)) {
        $0.account = nil
        $0.phase = .ready
    }
}

@Test func explanationStepsRenderRuleLabelsAndFacts() {
    #expect(CatalogRule.ps5Native.label == "PS5 native")
    #expect(hidden.explanation.steps[0].facts == "PS Plus Premium")
    #expect(shown.explanation.steps[1].facts == "UP9000-PPSA09006_00-FULLGAME00000000")
    #expect(SettingsRoute.allCases.contains(.entitlements))
}

private let streamed = ExplainedTitle(
    game: CloudGame(
        productId: "EP9000-CUSA07123_00-NIOHEU0000000000", name: "Nioh", streamServiceType: "psnow",
        standing: .included
    ),
    explanation: CatalogExplanation(listed: true, steps: [.init(rule: .includedWithPlus, outcome: .passed)])
)
private func leftThePlan(_ product: String, _ name: String) -> ExplainedTitle {
    ExplainedTitle(
        game: CloudGame(
            productId: product, name: name, streamServiceType: "psnow", visible: false,
            hideReason: "not_in_service"
        ),
        explanation: CatalogExplanation(listed: true, steps: [
            .init(rule: .includedWithPlus, outcome: .failed, hides: true)
        ])
    )
}

@MainActor @Test func eachServiceListsItsOwnTitlesAndCountsWhatWasDroppedAndWhy() async {
    let carto = leftThePlan("EP3717-CUSA23986_00-CARTO0000000000E", "Carto")
    let farCry = leftThePlan("EP0001-CUSA05847_00-FARCRY5GAME00000", "Far Cry 5")
    var state = EntitlementsReducer.State()
    state.titles = [shown, hidden, streamed, carto, farCry]
    state.phase = .loaded
    let store = TestStore(initialState: state) {
        EntitlementsReducer()
    }

    #expect(store.state.rows == [streamed, carto, farCry])
    #expect(store.state.summary.present == 1)
    #expect(store.state.summary.dropped == [
        .init(reason: "no PlayStation Plus plan covers the title's streaming copy", count: 2)
    ])
    #expect(carto.droppedBecause == "no PlayStation Plus plan covers the title's streaming copy")
    #expect(streamed.droppedBecause == nil)
    #expect(carto.endResult == "Not offered")
    #expect(streamed.endResult == "Offered: Included with Premium")
    #expect(store.state.summary.held == 0)
    #expect(shown.heldRecords == ["UP9000-PPSA09006_00-FULLGAME00000000"])
    #expect(streamed.heldRecords.isEmpty)
    #expect(EntitlementService.psNow.source.contains("PlayStation Now shelves"))
    #expect(EntitlementService.psCloud.source.contains("Premium streaming category"))
    #expect(EntitlementService.psNow.rules.count == 6)

    await store.send(.service(.psCloud)) {
        $0.service = .psCloud
        $0.selection = shown.id
    }
    #expect(store.state.rows == [shown, hidden])
    #expect(store.state.summary.present == 1)
    #expect(store.state.summary.dropped == [
        .init(reason: "the copy in the library is not a PS5 version", count: 1)
    ])
    await store.send(.service(.psCloud))
    await store.send(.service(.psNow)) {
        $0.service = .psNow
        $0.selection = streamed.id
    }
}

@MainActor @Test func theFetchReportIsKeptWithTheTitlesAndClearedWithTheAccount() async {
    var report = CatalogFetchReport()
    report.psNowTitles = 781
    report.copiesChecked = .init(asked: 531, answered: 531)
    report.withoutACoveredCopy = 9
    report.psCloudTitles = 4287
    report.audience = .init(country: "GB", language: "en", age: 34)
    report.premiumCategory = .init(fetchedAt: Date(timeIntervalSince1970: 1_791_834_463), titles: 340)
    report.library = .fetched(Date(timeIntervalSince1970: 1_791_834_400), records: 50)
    report.tier = .premium
    var state = EntitlementsReducer.State()
    state.accounts = [account]
    state.account = account.id
    state.phase = .ready
    let store = TestStore(initialState: state) {
        EntitlementsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.entitlementAccounts = { [account] }
        $0.catalog.explainedTitles = { _, _ in [streamed] }
        $0.catalog.fetchReport = { [report] _ in report }
    }
    await store.send(.load) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.reported(UUID(0), report)) {
        $0.report = report
    }
    await store.receive(.loaded(UUID(0), [streamed])) {
        $0.titles = [streamed]
        $0.phase = .loaded
        $0.selection = streamed.id
    }
    await store.send(.selectAccount(nil)) {
        $0.account = nil
        $0.titles = nil
        $0.report = nil
        $0.selection = nil
        $0.phase = .ready
    }
}

@Test func theFetchReportStatesEachSourceInWords() {
    var report = CatalogFetchReport()
    report.psNowTitles = 781
    report.copiesChecked = .init(asked: 531, answered: 531)
    report.withoutACoveredCopy = 9
    report.psCloudTitles = 4287
    report.audience = .init(country: "GB", language: "en", age: 34)
    report.premiumCategory = .init(fetchedAt: Date(timeIntervalSince1970: 1_791_834_463), titles: 340)
    report.library = .fetched(Date(timeIntervalSince1970: 1_791_834_400), records: 50)

    let now = report.source(of: .psNow)
    #expect(now[0] ==
        "781 titles on the PlayStation Now shelves, read through the account's PlayStation Now session")
    #expect(now[1].hasPrefix("The list is complete and was fetched "))
    #expect(now[2] == "Streaming copies were asked about for 531 PS4 titles and 531 were answered, "
        + "of which 9 have no copy a plan covers")
    let cloud = report.source(of: .psCloud)
    #expect(cloud[0] == "4287 titles on the PlayStation Store's PS5 lists")
    #expect(cloud[1] == "Asked as country GB, language en and age 34, taken from the account's sign-in")
    #expect(cloud[2].hasPrefix("The Premium streaming category gave 340 included titles, fetched "))
    #expect(report.held[0].hasPrefix("The library holds 50 records, fetched "))
    #expect(report.held[1] == "The membership tier is not known")

    var unknown = CatalogFetchReport()
    unknown.fromAccountService = false
    unknown.complete = false
    #expect(unknown.source(of: .psNow)[0].hasSuffix("because the account's session did not answer"))
    #expect(unknown.source(of: .psNow)[1].hasPrefix("The list is incomplete"))
    #expect(unknown.source(of: .psNow)[2].hasPrefix("Streaming copies were not checked"))
    #expect(unknown.source(of: .psCloud)[1].hasPrefix("The account's country, language or age is not known"))
    #expect(unknown.held[0] == "The library has not been fetched")
    unknown.library = .unavailable
    #expect(unknown.held[0] == "The library could not be fetched, so ownership is unknown")
    unknown.audience = .init(country: "GB", language: "en", age: 34)
    #expect(unknown.source(of: .psCloud)[2].hasPrefix("The Premium streaming category has not answered"))
}

@MainActor @Test func entitlementsAskForTheCatalogInTheInjectedLocale() async {
    let asked = LockIsolated<[String]>([])
    let store = TestStore(initialState: EntitlementsReducer.State()) {
        EntitlementsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.locale = Locale(identifier: "fr_CA")
        $0.catalog.entitlementAccounts = { [account] }
        $0.catalog.explainedTitles = { _, locale in
            asked.withValue {
                $0.append(locale)
            }
            return [shown]
        }
    }
    store.exhaustivity = .off
    await store.send(.appear)
    await store.receive(\.accountsLoaded)
    await store.send(.load)
    await store.receive(\.loaded)
    #expect(asked.value == ["fr-CA"])
}
