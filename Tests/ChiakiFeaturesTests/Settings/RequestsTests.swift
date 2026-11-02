@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private let gameList = CoreHTTPExchange(
    id: 3, area: .catalog, credentials: [.accountToken], credentialLabel: "commerce bearer", method: "GET",
    startedAt: Date(timeIntervalSince1970: 3661), duration: .milliseconds(120),
    base: "https://m.np.playstation.com",
    url: CoreHTTPMarkedText(
        "https://m.np.playstation.com/api/gamelist?code=SECRETCODE",
        spans: [CoreHTTPSecretSpan(offset: 47, length: 10, kind: .parameter)]
    ),
    status: 200, bytesReceived: 2048
)
private let cloudStart = CoreHTTPExchange(
    id: 2, area: .play, credentials: [.gkSession], method: "POST", base: "https://cc.prod.gaikai.com",
    url: CoreHTTPMarkedText("https://cc.prod.gaikai.com/v1/sessions/start"), status: 500, failed: true
)
private let config = CoreHTTPExchange(
    id: 1, area: .play, base: "https://config.cc.prod.gaikai.com",
    url: CoreHTTPMarkedText("https://config.cc.prod.gaikai.com/config"), status: nil,
    transportError: .timedOut,
    failed: true
)
private let log = CoreHTTPLog(
    revision: 5,
    totals: CoreHTTPTotals(
        all: CoreHTTPTally(requests: 250, httpErrors: 4, transportErrors: 1),
        bases: [
            "https://m.np.playstation.com": CoreHTTPTally(requests: 200),
            "https://cc.prod.gaikai.com": CoreHTTPTally(requests: 40),
            "https://config.cc.prod.gaikai.com": CoreHTTPTally(requests: 10)
        ]
    ),
    exchanges: [gameList, cloudStart, config]
)
private let detail = CoreHTTPExchangeDetail(
    requestHeaders: [
        CoreHTTPHeader(name: "Authorization", value: CoreHTTPMarkedText(
            "Bearer TOKEN123", spans: [CoreHTTPSecretSpan(offset: 7, length: 8, kind: .credential)]
        )),
        CoreHTTPHeader(name: "Accept", value: CoreHTTPMarkedText("application/json"))
    ],
    requestBody: CoreHTTPBody(
        size: 0,
        kept: 0,
        truncated: false,
        binary: false,
        text: CoreHTTPMarkedText("")
    ),
    responseHeaders: [CoreHTTPHeader(name: "Content-Type", value: CoreHTTPMarkedText("application/json"))],
    responseBody: CoreHTTPBody(
        size: 40, kept: 40, truncated: false, binary: false,
        text: CoreHTTPMarkedText(
            "{\n  \"access_token\": \"JSONSECRET\"\n}",
            spans: [CoreHTTPSecretSpan(offset: 21, length: 10, kind: .field)]
        )
    )
)

private final class Copied: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [String] = []
    private var revisions: [UInt64] = [5]
    private var asked = 0

    func add(_ text: String) {
        lock.withLock {
            held.append(text)
        }
    }

    var all: [String] {
        lock.withLock {
            held
        }
    }

    func revision() -> UInt64 {
        lock.withLock {
            asked += 1
            return revisions.count > 1
                ? revisions.removeFirst()
                : revisions[0]
        }
    }

    func next(_ revision: UInt64) {
        lock.withLock {
            revisions = [revision]
        }
    }

    var polls: Int {
        lock.withLock {
            asked
        }
    }
}

private func client(_ copied: Copied, log served: CoreHTTPLog = log) -> SettingsClient {
    let store = SettingsClient.inMemory()
    return SettingsClient(
        read: store.read, write: store.write, requestLogRevision: { copied.revision() },
        requestLog: { served },
        requestDetail: { _ in detail }
    )
}

@Test func requestsFilterByCredentialAreaBaseFailuresAndSearch() {
    var filter = RequestsReducer.Filter()
    #expect(filter.isEmpty)
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [3, 2, 1])
    filter.credentials = [.anonymous]
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [1])
    filter.credentials = [.anonymous, .carried(.gkSession)]
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [2, 1])
    filter.areas = [.play]
    filter.bases = ["https://cc.prod.gaikai.com"]
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [2])
    filter = RequestsReducer.Filter()
    filter.bases = ["https://cc.prod.gaikai.com", "https://m.np.playstation.com"]
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [3, 2])
    filter.failuresOnly = true
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [2])
    filter = RequestsReducer.Filter()
    filter.search = "GAMELIST"
    #expect(log.exchanges.filter(filter.admits).map(\.id) == [3])
    filter.search = "SECRETCODE"
    #expect(log.exchanges.filter(filter.admits).isEmpty)
    #expect(!filter.isEmpty)
}

@Test func requestBaseChoicesCountTheLifetimeAndTheLog() {
    let choices = RequestBaseChoice.choices(
        totals: log.totals, exchanges: log.exchanges, chosen: ["https://cc.prod.gaikai.com"]
    )
    #expect(choices.map(\.base) == [
        "https://m.np.playstation.com", "https://cc.prod.gaikai.com", "https://config.cc.prod.gaikai.com"
    ])
    #expect(choices.map(\.lifetime) == [200, 40, 10])
    #expect(choices.map(\.kept) == [1, 1, 1])
    #expect(choices.map(\.chosen) == [false, true, false])
    #expect(choices[0].host == "m.np.playstation.com")
}

@Test func requestRowsShowTheirBasePathStatusAndTags() {
    let row = RequestRowPresentation(gameList, timeZone: TimeZone(identifier: "UTC")!)
    #expect(row.time == "01:01:01")
    #expect(row.base == "https://m.np.playstation.com")
    #expect(row.path == "/api/gamelist?code=[parameter, 10 bytes]")
    #expect(row.status == "200" && !row.failed)
    #expect(row.duration == "120 ms" && row.size == "2.0 KB")
    #expect(row.credentials == ["Account token"] && row.area == "Catalog")
    let failed = RequestRowPresentation(config)
    #expect(failed.status == "Timed out" && failed.failed)
    #expect(failed.credentials == ["Anonymous"])
}

@MainActor @Test func requestsMaskSecretsUntilOneIsRevealedAndCopyWhatIsShown() async {
    let copied = Copied()
    var state = RequestsReducer.State()
    state.log = log
    state.phase = .ready
    let store = TestStore(initialState: state) {
        RequestsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = client(copied)
        $0.platform.copy = { copied.add($0) }
    }
    await store.send(.open(3)) {
        $0.detail = .loading(3, UUID(0))
    }
    await store.receive(.detailLoaded(UUID(0), detail)) {
        $0.detail = .shown(3, detail)
    }
    await store.send(.copyCurl)
    await store.send(.copyResponse)
    let header = RequestsReducer.Secret(.requestHeader(0), 0)
    await store.send(.toggleSecret(header)) {
        $0.revealed = [header]
    }
    await store.send(.copyCurl)
    let body = RequestsReducer.Secret(.responseBody, 0)
    await store.send(.toggleSecret(body)) {
        $0.revealed = [header, body]
    }
    await store.send(.copyResponse)
    await store.send(.toggleSecret(header)) {
        $0.revealed = [body]
    }
    await store.finish()
    let copies = copied.all
    #expect(copies.count == 4)
    #expect(copies[0] == """
    curl -X GET 'https://m.np.playstation.com/api/gamelist?code=[parameter, 10 bytes]' \\
      -H 'Authorization: Bearer [credential, 8 bytes]' \\
      -H 'Accept: application/json'
    """)
    #expect(!copies[1].contains("JSONSECRET") && copies[1].hasPrefix("HTTP 200"))
    #expect(copies[2].contains("Bearer TOKEN123") && !copies[2].contains("SECRETCODE"))
    #expect(copies[3].contains("\"access_token\": \"JSONSECRET\""))
    await store.send(.open(2)) {
        $0.revealed = []
        $0.detail = .loading(2, UUID(1))
    }
    await store.receive(.detailLoaded(UUID(1), detail)) {
        $0.detail = .shown(2, detail)
    }
    await store.send(.open(2)) {
        $0.detail = .closed
    }
}

@MainActor @Test func requestsRefreshOnlyWhileTheTabIsVisible() async {
    let copied = Copied()
    let clock = TestClock()
    let store = TestStore(initialState: RequestsReducer.State()) {
        RequestsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.settings = client(copied)
        $0.platform.copy = { copied.add($0) }
    }
    await store.send(.appear) {
        $0.watch = .watching
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.loaded(UUID(0), log)) {
        $0.log = log
        $0.phase = .ready
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.revisionSeen(5))
    copied.next(6)
    await clock.advance(by: .seconds(1))
    await store.receive(.revisionSeen(6)) {
        $0.phase = .loading(UUID(1))
    }
    await store.receive(.loaded(UUID(1), log)) {
        $0.phase = .ready
    }
    await store.send(.disappear) {
        $0.watch = .hidden
    }
    let asked = copied.polls
    await clock.advance(by: .seconds(5))
    #expect(copied.polls == asked)
    await store.send(.revisionSeen(9))
    await store.send(.appear) {
        $0.watch = .watching
        $0.phase = .loading(UUID(2))
    }
    await store.receive(.loaded(UUID(2), log)) {
        $0.phase = .ready
    }
    await store.send(.disappear) {
        $0.watch = .hidden
    }
}

@MainActor @Test func requestsFiltersAndClearsChangeOnlyWhatTheyName() async {
    let copied = Copied()
    var state = RequestsReducer.State()
    state.log = log
    state.phase = .ready
    state.detail = .shown(3, detail)
    let store = TestStore(initialState: state) {
        RequestsReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = client(copied, log: CoreHTTPLog(revision: 6, totals: log.totals))
        $0.platform.copy = { copied.add($0) }
    }
    await store.send(.toggleBase("https://cc.prod.gaikai.com")) {
        $0.filter.bases = ["https://cc.prod.gaikai.com"]
    }
    await store.send(.toggleArea(.play)) {
        $0.filter.areas = [.play]
    }
    await store.send(.toggleCredential(.anonymous)) {
        $0.filter.credentials = [.anonymous]
    }
    await store.send(.setFailuresOnly(true)) {
        $0.filter.failuresOnly = true
    }
    await store.send(.setSearch("start")) {
        $0.filter.search = "start"
    }
    #expect(store.state.shown.isEmpty)
    await store.send(.toggleCredential(.anonymous)) {
        $0.filter.credentials = []
    }
    #expect(store.state.shown.map(\.id) == [2])
    await store.send(.clearFilters) {
        $0.filter = RequestsReducer.Filter()
    }
    await store.send(.clearLog) {
        $0.detail = .closed
    }
    await store.receive(.refresh) {
        $0.phase = .loading(UUID(0))
    }
    await store.receive(.loaded(UUID(0), CoreHTTPLog(revision: 6, totals: log.totals))) {
        $0.log = CoreHTTPLog(revision: 6, totals: log.totals)
        $0.phase = .ready
    }
}

@Test func theRequestsAndNetworkTabsAreNamed() {
    #expect(SettingsRoute.requests.title == "Requests")
    #expect(SettingsRoute.network.title == "Network")
}
