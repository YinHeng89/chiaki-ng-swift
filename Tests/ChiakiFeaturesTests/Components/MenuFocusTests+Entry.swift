@testable import ChiakiFeatures
import ChiakiModels
import DesignSystem
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

extension MenuFocusTests {
    @Test func welcomeStartsOnThePSNAccountAndWalksAlongItsTiles() async {
        let sent = EntryActionLog()
        let store = entryStore(.welcome, log: sent)
        let harness = entryHarness(store)
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        await harness.send(.confirm)
        #expect(sent.views == [.chooseSignIn])
        await harness.send([.down, .confirm])
        #expect(sent.views.last == .chooseAccountID)
        let lastChoice: RootFeature.Action.View = KakusanBuild.included
            ? .joinGame
            : .chooseAccountID
        await harness.send([.down, .confirm])
        #expect(sent.views.last == lastChoice)
        await harness.send([.down, .confirm])
        #expect(sent.views.last == lastChoice)
        await harness.send([.up, .up, .up, .up, .confirm])
        #expect(sent.views.last == .chooseSignIn)
    }

    @Test func theSignInPageStartsOnSignInOffersAQRCodeAndBackLeaves() async {
        var signIn = SignInFeature.State()
        signIn.method = .browser
        signIn.acknowledged = true
        let sent = EntryActionLog()
        let harness = entryHarness(entryStore(.signIn(signIn), log: sent))
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        await harness.send(.confirm)
        #expect(sent.routes.last == .signIn(.view(.start)))
        await harness.send([.down, .confirm])
        #expect(sent.routes.last == .signIn(.view(.choose(.qrCode))))
        await harness.send([.down, .confirm])
        #expect(sent.routes.last == .signIn(.view(.back)))
        await harness.send([.up, .up, .confirm])
        #expect(sent.routes.last == .signIn(.view(.start)))
        await harness.send(.back)
        #expect(sent.routes.last == .signIn(.view(.back)))
    }

    @Test func reconnectingWalksSignInAndBackWithoutACodeChoice() async {
        let sent = EntryActionLog()
        let harness = entryHarness(entryStore(.signIn(SignInFeature.State(reconnecting: UUID())), log: sent))
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        await harness.send([.down, .confirm])
        #expect(sent.routes.last == .signIn(.view(.back)))
        await harness.send([.up, .confirm])
        #expect(sent.routes.last == .signIn(.view(.start)))
    }

    @Test func aShownCodeStartsOnTheOtherMethodAndBackLeaves() async {
        var signIn = SignInFeature.State()
        signIn.acknowledged = true
        signIn.phase = .showingCode(
            OperationID(uuid: UUID()),
            QRSignInCode(
                attempt: 1,
                approvalURL: "https://example.invalid/approve",
                userCode: "012345",
                expiresAt: nil
            )
        )
        let sent = EntryActionLog()
        let harness = entryHarness(entryStore(.signIn(signIn), log: sent))
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        #expect(sent.routes.first == .signIn(.view(.appeared)))
        await harness.send(.confirm)
        #expect(sent.routes.last == .signIn(.view(.choose(.browser))))
        await harness.send([.down, .confirm])
        #expect(sent.routes.last == .signIn(.view(.back)))
        await harness.send([.down, .up, .confirm])
        #expect(sent.routes.last == .signIn(.view(.choose(.browser))))
        await harness.send(.back)
        #expect(sent.routes.last == .signIn(.view(.back)))
    }

    @Test func aFailedCodeStartsOnANewCodeAndWalksToBack() async {
        var signIn = SignInFeature.State()
        signIn.acknowledged = true
        signIn.phase = .failed(.navigationFailed)
        let sent = EntryActionLog()
        let harness = entryHarness(entryStore(.signIn(signIn), log: sent))
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        await harness.send(.confirm)
        #expect(sent.routes.last == .signIn(.view(.start)))
        await harness.send([.down, .confirm])
        #expect(sent.routes.last == .signIn(.view(.choose(.browser))))
        await harness.send([.down, .confirm])
        #expect(sent.routes.last == .signIn(.view(.back)))
        await harness.send([.up, .up, .confirm])
        #expect(sent.routes.last == .signIn(.view(.start)))
    }

    @Test func addConsoleByAddressStartsInTheAddressAndReachesBack() async {
        let sent = EntryActionLog()
        let store = entryStore(
            .addConsole(AddConsoleFeature.State(account: UUID(), modes: [.manual])),
            log: sent
        )
        let harness = entryHarness(store)
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            harness.window.firstResponder is NSTextView
        }
        #expect(harness.window.firstResponder is NSTextView)
        let address = harness.window.firstResponder
        await harness.send([.down, .down])
        #expect(harness.window.firstResponder !== address)
        await harness.send(.confirm)
        #expect(sent.routes.last == .addConsole(.view(.back)))
        await harness.send([.up, .up])
        #expect(harness.window.firstResponder === address)
    }

    @Test func pairingStartsInThePINAndBackCancels() async {
        let sent = EntryActionLog()
        let pairing = PairingFeature.State(
            account: AccountID(value: 0x0101_0101_0101_0101),
            target: .atHome(address: "127.0.0.1", kind: .ps5)
        )
        let store = entryStore(.pairing(pairing), log: sent)
        let harness = entryHarness(store)
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            harness.window.firstResponder is NSTextView
        }
        #expect(harness.window.firstResponder is NSTextView)
        let pin = harness.window.firstResponder
        await harness.send(.down)
        #expect(harness.window.firstResponder !== pin)
        await harness.send(.confirm)
        #expect(sent.routes.last == .pairing(.view(.cancel)))
        await harness.send(.up)
        #expect(harness.window.firstResponder === pin)
    }

    private func entryStore(_ route: RootFeature.Route.State, log: EntryActionLog) -> StoreOf<RootFeature> {
        Store(initialState: RootFeature.State(route: route)) {
            Reduce<RootFeature.State, RootFeature.Action> { _, action in
                log.record(action)
                return .none
            }
        }
    }

    private func entryHarness(
        _ store: StoreOf<RootFeature>,
        size: CGSize = CGSize(width: 900, height: 760),
        layout: ScreenLayout = ScreenLayout()
    ) -> MenuFocusHarness {
        MenuFocusHarness(width: size.width, height: size.height) { _ in
            MenuFocusHostingView(rootView: EntryScreen(store: store, height: size.height)
                .environment(\.screenLayout, layout))
        }
    }

    @Test func welcomeOnAShortTouchScreenKeepsItsWalkWithFingerSizedChoices() async {
        let sent = EntryActionLog()
        let store = entryStore(.welcome, log: sent)
        let harness = entryHarness(
            store,
            size: CGSize(width: 820, height: 380),
            layout: ScreenLayout(room: .compact, stature: .short, touch: true, sideInset: 59)
        )
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        let primary = harness.focusedFrame
        await harness.send(.down)
        let secondary = harness.focusedFrame
        #expect(secondary.height >= ScreenLayout.touchTarget - 1, "\(secondary)")
        #expect(abs(secondary.midY - primary.midY) < 4, "\(primary) \(secondary)")
        #expect(secondary.minX > primary.maxX, "\(primary) \(secondary)")
        await harness.send(.confirm)
        #expect(sent.views.last == .chooseAccountID)
        await harness.send([.up, .confirm])
        #expect(sent.views.last == .chooseSignIn)
    }
}

@MainActor
private final class EntryActionLog {
    private(set) var views: [RootFeature.Action.View] = []
    private(set) var routes: [RootFeature.Route.Action] = []

    func record(_ action: RootFeature.Action) {
        switch action {
        case .view(let view):
            views.append(view)
        case .route(let route):
            routes.append(route)
        default:
            break
        }
    }
}
