import ChiakiClients
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import DesignSystem
import SwiftUI
import Synchronization
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func cloudControlsAreReachableAndLeadBackToTheGames() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"first","name":"First","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"first"},
        {"productId":"second","name":"Second","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"second"}]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        let harness = MenuFocusHarness(width: 1100, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.send([.up, .right, .confirm])
        #expect(store.filter == .owned)
        await harness.send([.left, .confirm])
        #expect(store.filter == .all)
        await harness.send([.right, .confirm])
        #expect(store.filter == .owned)
        store.send(.focusRequested(LibraryContentFocus(.selectedFilter)))
        await harness.settle()
        await harness.send([.left, .confirm])
        #expect(store.filter == .all)
        await harness.send([.right, .confirm])
        #expect(store.filter == .owned)
        await harness.send([.right, .right, .right])
        #expect(harness.window.firstResponder is NSTextView)
        await harness.send([.down, .right, .confirm])
        #expect(store.selectedGame?.id == snapshot.games[1].id)
    }

    @Test func compactCloudControlsAreTwoDropDownsThenSearch() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[{"productId":"first","name":"First","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"first"}]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        let harness = MenuFocusHarness(width: 393, height: 852) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600)
                .environment(\.screenLayout, ScreenLayout(room: .compact, stature: .tall, touch: true)))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.send([.up, .right, .right, .confirm])
        await waitUntil(harness) {
            store.isSearching
        }
        #expect(store.isSearching)
        await harness.send(.back)
        await waitUntil(harness) {
            !store.isSearching
        }
        #expect(!store.isSearching)
        await harness.pause(200)
        await harness.send([.left, .left, .down, .confirm])
        await waitUntil(harness) {
            store.selectedGame?.id == snapshot.games[0].id
        }
        #expect(store.selectedGame?.id == snapshot.games[0].id)
    }

    @Test func cloudDownEntersTheGameColumnBelowBrowse() async throws {
        _ = NSApplication.shared
        let games = (0..<6).map { index in
            """
            {"productId":"game-\(index)","name":"Game \(index)","platform":"ps5",
            "category":"owned","isOwned":true,"plusCatalog":true,
            "streamServiceType":"pscloud","streamIdentifier":"game-\(index)"}
            """
        }.joined(separator: ",")
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[\(games)]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        let host = MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 1500, height: 800),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        for command: MenuCommand in [
            .up, .right, .right, .right, .down, .confirm
        ] {
            testNavigator.perform(command, in: window) { window.sendEvent($0) }
            await settle(host)
        }
        #expect(store.selectedGame?.id == snapshot.games[1].id)
    }

    private func displayed(_ consoles: [RegistrationFlow.ConsoleTarget]) -> [DisplayedConsole] {
        consoles.map {
            DisplayedConsole(target: $0, preview: false)
        }
    }

    private func consoleShelf(
        _ consoles: [RegistrationFlow.ConsoleTarget]
    ) -> (StoreOf<LibraryFeature>, MenuFocusHarness) {
        let store = FeatureFocusStores.libraryStore(consoles: consoles) { state in
            state.discovery = .watching(DiscoverySnapshot())
        }
        let harness = MenuFocusHarness(width: 1000, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store))
        }
        return (store, harness)
    }

    @Test func consoleCardsMoveBetweenTheirControlsAndNeighbours() async {
        let consoles = [FeatureFocusStores.console(1), FeatureFocusStores.console(2)]
        let items = displayed(consoles)
        let (store, harness) = consoleShelf(consoles)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .console(items[0])
        }
        await harness.pause(400)
        #expect(store.heldFocus == .console(items[0]))
        await expectLibrarySteps(cardSteps(items), harness: harness, store: store)
        var navigation = ControllerNavigationState()
        navigation.setRoute(.menu)
        harness.perform(navigation.button(14, down: true, now: 0), in: harness.window)
        await harness.settle()
        #expect(store.heldFocus == .action(items[0], .edit))
        harness.perform(navigation.button(14, down: false, now: 0.1), in: harness.window)
        harness.perform(navigation.button(13, down: true, now: 0.2), in: harness.window)
        await harness.settle()
        #expect(store.heldFocus == .console(items[0]))
        harness.perform(navigation.button(13, down: false, now: 0.3), in: harness.window)
        harness.perform(navigation.axis(0, value: 25000, now: 0), in: harness.window)
        await harness.settle()
        #expect(store.heldFocus == .action(items[0], .edit))
    }

    @Test func aConsoleNotFoundAtHomeSkipsItsGreyedLocalTag() async {
        let items = displayed([FeatureFocusStores.console(1)])
        let (store, harness) = consoleShelf(items.map(\.target))
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .console(items[0])
        }
        await harness.pause(400)
        store.send(.discoverySearched(true))
        await harness.pause(200)
        #expect(store.heldFocus == .console(items[0]))
        await expectLibrarySteps([
            (.up, .action(items[0], .connection(.remote))),
            (.down, .console(items[0])),
            (.up, .action(items[0], .connection(.remote)))
        ], harness: harness, store: store)
        await harness.send(.left)
        #expect(store.heldFocus != .action(items[0], .connection(.local)))
    }

    @Test func aFocusedConnectionTagHandsFocusToPlayWhenTheConsoleIsNotFound() async {
        let items = displayed([FeatureFocusStores.console(1)])
        let (store, harness) = consoleShelf(items.map(\.target))
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .console(items[0])
        }
        await harness.pause(400)
        await expectLibrarySteps(
            [(.up, .action(items[0], .connection(.local)))],
            harness: harness,
            store: store
        )
        store.send(.discoverySearched(true))
        await harness.pause(200)
        #expect(store.heldFocus == .console(items[0]))
        await expectLibrarySteps(
            [(.up, .action(items[0], .connection(.remote)))],
            harness: harness,
            store: store
        )
    }

    private func cardSteps(
        _ items: [DisplayedConsole]
    ) -> [(MenuCommand, ConsoleLibraryFocus?)] {
        [
            (.right, .action(items[0], .edit)),
            (.right, .action(items[0], .delete)),
            (.right, .action(items[0], .delete)),
            (.left, .action(items[0], .edit)),
            (.up, .action(items[0], .connection(.local))),
            (.down, .console(items[0])),
            (.up, .action(items[0], .connection(.local))),
            (.right, .action(items[0], .connection(.remote))),
            (.right, .action(items[0], .connection(.remote))),
            (.left, .action(items[0], .connection(.local))),
            (.down, .console(items[0])),
            (.down, .console(items[1])),
            (.up, .action(items[1], .connection(.local))),
            (.up, .console(items[0])),
            (.up, .action(items[0], .connection(.local))),
            (.up, .addConsole),
            (.up, .addConsole),
            (.down, .console(items[0])),
            (.left, .librarySection(.consoles)),
            (.right, .console(items[0]))
        ]
    }

    private func expectLibrarySteps(
        _ steps: [(MenuCommand, ConsoleLibraryFocus?)],
        harness: MenuFocusHarness,
        store: StoreOf<LibraryFeature>
    ) async {
        for (command, expected) in steps {
            await harness.send(command)
            await waitUntil(harness, attempts: 10) {
                store.heldFocus == expected
            }
            #expect(store.heldFocus == expected, "after \(command): \(String(describing: store.heldFocus))")
        }
    }

    @Test func nativeButtonsSupportFocusTraversalAndActivation() async throws {
        let probe = FocusProbe()
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: FocusFixture(probe: probe))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            testNavigator.stop()
            window.contentView = nil
            window.close()
        }
        await settle(host)
        window.makeFirstResponder(nil)
        testNavigator.move(backward: false, in: window)
        await settle(host)
        #expect(probe.focus == 0)
        #expect(probe.highlighted == [0])
        testNavigator.move(backward: false, in: window)
        await settle(host)
        #expect(probe.focus == 2)
        #expect(probe.highlighted == [2])
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        window.sendEvent(event)
        await settle(host)
        #expect(probe.activations == [2])
        let space = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        window.sendEvent(space)
        await settle(host)
        #expect(probe.activations == [2, 2])
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(probe.activations == [2, 2, 2])
    }
}

extension MenuFocusTests {
    @Test func failedAccountRefreshRetryIsReachableFromTheConsoles() async {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = [.init(profileID: profileID, console: .init(address: "192.168.1.20", kind: .ps5))]
        }
        let counter = LockIsolated(0)
        var state = LibraryFeature.State(section: .consoles)
        state.activity = LibraryActivity(refresh: .failed)
        let store = Store(initialState: state) {
            LibraryFeature()
            Reduce { _, action in
                if case .requested(.refreshAccounts) = action {
                    counter.withValue {
                        $0 += 1
                    }
                }
                return .none
            }
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send([.up, .confirm])
        await harness.pause(100)
        #expect(counter.value == 1)
    }
}

extension MenuFocusTests {
    @Test func confirmWhileCloudDetailsLoadKeepsThemOpenAndBackReturnsToTheCard() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"first","name":"First","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"first"},
        {"productId":"second","name":"Second","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"second"},
        {"productId":"third","name":"Third","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"third"}]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.catalog.gameDetails = { _, _ in
                try? await Task.sleep(for: .seconds(30))
                return .failure(CatalogFailure(reason: .coreClosed))
            }
        }
        let harness = MenuFocusHarness(width: 1100, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        await harness.send(.right)
        let card = harness.focusedFrame.integral
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.selectedGame?.id == snapshot.games[1].id)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.selectedGame?.id == snapshot.games[1].id)
        await harness.send([.right, .confirm])
        await harness.pause(200)
        #expect(store.selectedGame?.id == snapshot.games[1].id)
        await harness.send(.back)
        await harness.pause(400)
        #expect(store.selectedGame == nil)
        #expect(harness.focusedFrame.integral == card)
    }

    @Test func playTakesFocusWhenTheStoreCheckFinishesAndConfirmWaitsForIt() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"checked","name":"Checked","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"checked",
        "needsStorefrontCheck":true}]}
        """.utf8))
        let game = snapshot.games[0].id
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.catalog.clearForLaunch = CatalogClient.clearing
            $0.catalog.storefrontCheck = CatalogClient.unanswered
        }
        let harness = MenuFocusHarness(width: 1100, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        await harness.send(.confirm)
        await harness.pause(400)
        #expect(store.selectedGame?.id == game)
        store.send(.cardChecked(state.accountID!, game, .checking))
        await harness.pause(100)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.selectedGame?.id == game)
        store.send(.cardChecked(state.accountID!, game, .streams))
        await harness.pause(300)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.launchChecks?.phase == .launched)
        #expect(store.selectedGame?.id == game)
    }

    @Test func playIsFocusedOnceShortlyLoadingCloudDetailsArrive() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"quick","name":"Quick","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"quick"}]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        state.cardChecks[snapshot.games[0].id] = .streams
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.catalog.gameDetails = { _, _ in
                try? await Task.sleep(for: .milliseconds(150))
                return .failure(CatalogFailure(reason: .coreClosed))
            }
            $0.catalog.clearForLaunch = CatalogClient.clearing
            $0.catalog.storefrontCheck = CatalogClient.unanswered
        }
        let harness = MenuFocusHarness(width: 1100, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        await harness.send(.confirm)
        await harness.pause(800)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.launchChecks?.phase == .launched)
    }

    @Test func cloudDetailRefreshSitsBetweenAddToLibraryAndClose() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"addable","name":"A Game With A Rather Long Title That Wraps","platform":"ps5",
        "category":"catalog","isOwned":false,"plusCatalog":true,"streamServiceType":"pscloud",
        "streamIdentifier":"addable","conceptUrl":"https://store.playstation.com/en-gb/concept/1"}]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        state.selection = snapshot.games[0].id
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
            $0.openURL = OpenURLEffect { _ in
                true
            }
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 700))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let add = harness.focusedFrame.integral
        #expect(add.width > 120)
        await harness.send(.down)
        let refresh = harness.focusedFrame.integral
        #expect(abs(refresh.width - add.width) <= 2, "\(add) \(refresh)")
        #expect(refresh.maxY < add.minY)
        await harness.send(.down)
        let close = harness.focusedFrame.integral
        #expect(close.width > 20 && abs(close.width - close.height) <= 2, "\(close)")
        await harness.send(.down)
        #expect(harness.focusedFrame.integral == add)
        store.send(.addToLibraryTapped(snapshot.games[0].id))
        await harness.pause(300)
        #expect(harness.focusedFrame.integral == add)
        await harness.send(.down)
        #expect(harness.focusedFrame.integral == refresh)
    }
}

extension MenuFocusTests {
    @Test func emptyShelfFocusesAddConsoleWhenTheLibraryOpens() async {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = []
        }
        let requests = LockIsolated(0)
        let store = Store(initialState: LibraryFeature.State(section: .consoles)) {
            LibraryFeature()
            Reduce { _, action in
                if case .requested(.addConsole) = action {
                    requests.withValue {
                        $0 += 1
                    }
                }
                return .none
            }
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send([.confirm])
        await harness.pause(100)
        #expect(requests.value == 1)
    }

    @Test func emptyShelfFocusesAddConsoleAfterSigningIn() async {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = []
        }
        $selected.withLock {
            $0 = nil
        }
        $catalog.withLock {
            $0 = []
        }
        let requests = LockIsolated(0)
        let store = Store(initialState: LibraryFeature.State(section: .consoles)) {
            LibraryFeature()
            Reduce { _, action in
                if case .requested(.addConsole) = action {
                    requests.withValue {
                        $0 += 1
                    }
                }
                return .none
            }
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        await harness.pause(500)
        await harness.send([.confirm])
        await harness.pause(100)
        #expect(requests.value == 1)
    }
}

extension MenuFocusTests {
    @Test func appLogoNeverTakesFocus() async {
        let harness = MenuFocusHarness(width: 400, height: 300) { _ in
            MenuFocusHostingView(rootView: ChiakiLogo(size: 48))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.window.makeFirstResponder(nil)
        testNavigator.move(backward: false, in: harness.window)
        await harness.settle()
        testNavigator.move(backward: false, in: harness.window)
        await harness.settle()
        let focused = harness.focusedView
        #expect(focused == nil || focused === harness.host || focused === harness.window.contentView)
    }
}

@MainActor
private final class CodeProbe {
    var completions = 0
}

private struct KonamiFixture: View {
    let probe: CodeProbe
    @State private var code = MenuCommandCode.konami
    @State private var hostWindow: PlatformWindow?

    var body: some View {
        VStack {
            FocusButton("First") {
            }
            FocusButton("Second") {
            }
        }
        .background(WindowAccessor { hostWindow = $0 })
        .onPerformedMenuCommand { event in
            guard event.targets(hostWindow, keyWindow: WindowFocus.keyWindow),
                  code.advance(event.command) else {
                return
            }
            probe.completions += 1
        }
    }
}

extension MenuFocusTests {
    @Test func konamiDirectionsReachViewsWatchingPerformedCommands() async {
        let probe = CodeProbe()
        let harness = MenuFocusHarness(width: 400, height: 300) { _ in
            MenuFocusHostingView(rootView: KonamiFixture(probe: probe))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.send([.up, .up, .down, .down, .left, .right, .left])
        #expect(probe.completions == 0)
        await harness.send(.right)
        #expect(probe.completions == 1)
        await harness.send([.up, .confirm, .up])
        #expect(probe.completions == 1)
    }
}

extension MenuFocusTests {
    private func railLibrary(quits: LockIsolated<Int>) -> MenuFocusHarness {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = []
        }
        let store = Store(initialState: LibraryFeature.State(section: .consoles)) {
            LibraryFeature()
        }
        return MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store)
                .environment(\.quitControlShown, true)
                .environment(\.requestQuit, RequestQuitAction { _ in
                    quits.withValue {
                        $0 += 1
                    }
                }))
        }
    }

    @Test func railQuitAsksToQuit() async {
        let quits = LockIsolated(0)
        let harness = railLibrary(quits: quits)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send([.left] + Array(repeating: .down, count: 7) + [.confirm])
        await harness.pause(100)
        #expect(quits.value == 1)
    }

    @Test func railSettingsAsksForSettings() async {
        let quits = LockIsolated(0)
        let harness = railLibrary(quits: quits)
        defer {
            harness.close()
        }
        let settings = LockIsolated(0)
        let listener = Task { @MainActor in
            for await event in testNavigator.commands.events() where event.command == .settings {
                settings.withValue {
                    $0 += 1
                }
            }
        }
        defer {
            listener.cancel()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send([.left] + Array(repeating: .down, count: 7) + [.up, .up, .confirm])
        await harness.pause(100)
        #expect(settings.value == 1)
    }
}

extension MenuFocusTests {
    @Test func emptyShelfKeepsAddConsoleFocusedAcrossACatalogReload() async {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = []
        }
        let requests = LockIsolated(0)
        let store = Store(initialState: LibraryFeature.State(section: .consoles)) {
            LibraryFeature()
            Reduce { _, action in
                if case .requested(.addConsole) = action {
                    requests.withValue {
                        $0 += 1
                    }
                }
                return .none
            }
        } withDependencies: {
            $0.continuousClock = ContinuousClock()
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        store.send(.activityChanged(LibraryActivity(catalog: .loading)))
        await harness.pause(100)
        store.send(.activityChanged(LibraryActivity(catalog: .loaded)))
        await harness.pause(600)
        await harness.send([.confirm])
        await harness.pause(100)
        #expect(requests.value == 1)
    }
}

extension MenuFocusTests {
    private func menuLibrary(
        section: LibrarySection,
        quits: LockIsolated<Int>,
        addConsoles: LockIsolated<Int>
    ) throws -> (StoreOf<LibraryFeature>, MenuFocusHarness) {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = []
        }
        var state = LibraryFeature.State(section: section)
        state.cloudLibrary.accountID = profileID
        state.cloudLibrary.snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"first","name":"First","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"first"},
        {"productId":"second","name":"Second","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"second"}]}
        """.utf8))
        state.cloudLibrary.phase = .ready
        let store = Store(initialState: state) {
            LibraryFeature()
            Reduce { _, action in
                if case .requested(.addConsole) = action {
                    addConsoles.withValue {
                        $0 += 1
                    }
                }
                return .none
            }
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store)
                .environment(\.quitControlShown, true)
                .environment(\.requestQuit, RequestQuitAction { _ in
                    quits.withValue {
                        $0 += 1
                    }
                }))
        }
        return (store, harness)
    }

    @Test(arguments: LibrarySection.allCases)
    func triangleMovesFromTheContentToTheMenu(section: LibrarySection) async throws {
        let quits = LockIsolated(0)
        let (_, harness) = try menuLibrary(section: section, quits: quits, addConsoles: LockIsolated(0))
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        let sectionsBelow = LibrarySection.allCases
            .count - 1 - (LibrarySection.allCases.firstIndex(of: section) ?? 0)
        await harness.send([.focusToolbar] + Array(repeating: .down, count: sectionsBelow + 5) + [.confirm])
        await harness.pause(100)
        #expect(quits.value == 1)
    }

    @Test func triangleReturnsFromTheMenuToAddConsole() async throws {
        let addConsoles = LockIsolated(0)
        let (_, harness) = try menuLibrary(
            section: .consoles,
            quits: LockIsolated(0),
            addConsoles: addConsoles
        )
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        await harness.send([.left, .focusToolbar, .confirm])
        await harness.pause(100)
        #expect(addConsoles.value == 1)
    }

    @Test func triangleReturnsFromTheMenuToTheCloudGameItLeft() async throws {
        let (store, harness) = try menuLibrary(
            section: .cloud,
            quits: LockIsolated(0),
            addConsoles: LockIsolated(0)
        )
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        await harness.send([.right, .focusToolbar, .down, .focusToolbar, .confirm])
        await harness.pause(200)
        #expect(store.cloudLibrary.selectedGame?.id == "second")
    }

    @Test(arguments: LibrarySection.allCases)
    func theStreamMenuButtonsMoveBetweenTheContentAndTheMenuOutsideAStream(
        section: LibrarySection
    ) async throws {
        let quits = LockIsolated(0)
        let (_, harness) = try menuLibrary(section: section, quits: quits, addConsoles: LockIsolated(0))
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        let content = harness.focusedFrame.integral
        let sectionsBelow = LibrarySection.allCases
            .count - 1 - (LibrarySection.allCases.firstIndex(of: section) ?? 0)
        await harness.send(.streamMenu)
        #expect(harness.focusedFrame.integral != content)
        await harness.send(.streamMenu)
        #expect(harness.focusedFrame.integral == content)
        await harness.send([.streamMenu] + Array(repeating: .down, count: sectionsBelow + 5) + [.confirm])
        await harness.pause(100)
        #expect(quits.value == 1)
    }
}

extension MenuFocusTests {
    @Test func theRailLogStopOpensTheLogAndBackReturnsToIt() async {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = []
        }
        let log = Store(initialState: LiveLogReducer.State()) {
            LiveLogReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        }
        let store = Store(initialState: LibraryFeature.State(section: .consoles)) {
            LibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store)
                .overlay(alignment: .topTrailing) {
                    LiveLogControl(
                        store: log, failure: nil, size: CGSize(width: 1300, height: 900),
                        trailingInset: 0, inStream: false, allowsQuit: false, showsButton: false
                    )
                }
                .environment(\.liveLogButtonShown, true))
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        await harness.open()
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(400)
        let rail = store.state.rail(edge: .left, showsQuit: false, showsLog: true)
        let stops = rail.stops
        guard let entered = stops.firstIndex(of: rail.entry(for: .consoles)),
              let logStop = stops.firstIndex(of: .log), logStop > entered else {
            Issue.record("the rail does not reach the log from Consoles: \(stops)")
            return
        }
        await harness.send([.left] + Array(repeating: .down, count: logStop - entered) + [.confirm])
        await harness.pause(250)
        #expect(log.visible)
        #expect(LiveLogFocus.focus(in: harness.window) == .pauseResume)
        await harness.send(.back)
        await harness.pause(250)
        #expect(!log.visible)
        await harness.send(.confirm)
        await harness.pause(250)
        #expect(log.visible)
    }
}
