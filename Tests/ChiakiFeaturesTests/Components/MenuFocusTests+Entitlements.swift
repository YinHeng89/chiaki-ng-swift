import ChiakiClients
import ChiakiModels
import ChiakiTestSupport
@testable import ChiakiFeatures
import ComposableArchitecture
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

extension MenuFocusTests {
    private struct EntitlementsPage {
        let store: StoreOf<SettingsFeature>
        let window: HeadlessWindow
        let host: NSView
    }

    private static let entitlementsAccount = EntitlementAccount(
        id: UUID(),
        name: "Player",
        accountID: AccountID(value: 0x0101_0101_0101_0101)
    )

    private static let ownedTitle = ExplainedTitle(
        game: CloudGame(
            productId: "UP9000-PPSA09006_00-FULLGAME00000000",
            name: "Owned",
            standing: .inLibrary
        ),
        explanation: CatalogExplanation(listed: true, steps: [
            .init(rule: .listedInCatalog, outcome: .passed)
        ])
    )

    private func entitlementsSettings(
        titles: [ExplainedTitle]
    ) async -> EntitlementsPage {
        _ = NSApplication.shared
        let account = Self.entitlementsAccount
        var state = SettingsFeature.State()
        state.psnReach = .signedIn
        state.route = .entitlements
        state.entitlements.accounts = [account]
        state.entitlements.account = account.id
        state.entitlements.titles = titles
        state.entitlements.service = .psCloud
        state.entitlements.phase = .loaded
        let store = Store(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.logSettings = .testValue
            $0.controllers = .testValue
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()
            $0.catalog.entitlementAccounts = {
                [account]
            }
            $0.catalog.explainedTitles = { _, _ in
                titles
            }
        }
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 900),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: SettingsView(
            store: store,
            pageLayoutWidth: 900,
            window: window
        ))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        await settle(host)
        try? await Task.sleep(for: .milliseconds(300))
        await settle(host)
        return EntitlementsPage(store: store, window: window, host: host)
    }

    private func moveToSearch(in window: HeadlessWindow, host: NSView, backward: Bool = false) async -> Bool {
        for _ in 0..<30 where !(window.firstResponder is NSTextView) {
            testNavigator.move(backward: backward, in: window)
            await settle(host)
        }
        return window.firstResponder is NSTextView
    }

    private func closeEntitlements(_ window: HeadlessWindow) {
        window.attachedSheet?.close()
        window.contentView = nil
        window.close()
    }

    @Test func entitlementsSearchIsAControllerStopThatOpensTheKeyboard() async {
        let page = await entitlementsSettings(titles: [])
        let window = page.window
        let host = page.host
        defer {
            closeEntitlements(window)
        }
        #expect(await moveToSearch(in: window, host: host))
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(window.attachedSheet != nil)
    }

    @Test func entitlementsFiltersAndTitlesAreControllerStops() async {
        let owned = Self.ownedTitle
        let page = await entitlementsSettings(titles: [owned])
        let store = page.store
        let window = page.window
        let host = page.host
        defer {
            closeEntitlements(window)
        }
        #expect(store.entitlements.rows.map(\.id) == [owned.id])
        #expect(store.entitlements.selection == nil)
        #expect(await moveToSearch(in: window, host: host))
        testNavigator.move(backward: false, in: window)
        await settle(host)
        #expect(!(window.firstResponder is NSTextView))
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.entitlements.selection == owned.id)
        #expect(window.attachedSheet == nil)
        #expect(await moveToSearch(in: window, host: host, backward: true))
        testNavigator.move(backward: true, in: window)
        await settle(host)
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.entitlements.filter != .all)
    }
}
