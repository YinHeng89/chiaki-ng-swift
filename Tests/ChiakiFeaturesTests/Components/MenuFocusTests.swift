import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Synchronization
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

@MainActor @Suite(.serialized, .requiresWindowServer)
struct MenuFocusTests {
    @Test func controllerCanEnterAndSubmitStreamPIN() async {
        let submitted = Mutex<String?>(nil)
        let canceled = Mutex(0)
        let harness = MenuFocusHarness(width: 900, height: 560) { _ in
            MenuFocusHostingView(rootView: StreamAccessCodeOverlay(
                phase: .requested(.loginPIN(retry: false)),
                submit: { code in
                    submitted.withLock { $0 = code.digits }
                },
                cancel: {
                    canceled.withLock { $0 += 1 }
                }
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        let promptPresentationCount = testNavigator.inputGate.presentations.count
        #expect(window.firstResponder is NSTextView)
        var underlyingActivations = 0
        let underlyingHandlerID = testNavigator.handlers.registerActivation { _ in
            underlyingActivations += 1
            return true
        }
        defer {
            testNavigator.handlers.unregister(underlyingHandlerID)
        }
        testNavigator.move(backward: false, in: window)
        await harness.settle()
        #expect(!(window.firstResponder is NSTextView))
        #expect(canceled.withLock { $0 } == 0)

        await harness.send(.confirm)
        #expect(canceled.withLock { $0 } == 0)
        #expect(underlyingActivations == 0)
        #expect(window.attachedSheet != nil)
        #expect(testNavigator.inputGate.presentations.count > promptPresentationCount)
        if let sheet = window.attachedSheet {
            harness.perform(Array(repeating: .confirm, count: 4), in: sheet)
            #expect(underlyingActivations == 0)
            harness.perform(Array(repeating: .down, count: 4) + [.right, .right, .confirm], in: sheet)
            await harness.settle()
        }
        #expect(window.attachedSheet == nil)
        #expect(testNavigator.inputGate.presentations.count == promptPresentationCount)
        harness.perform([.confirm], in: window)
        #expect(submitted.withLock { $0 } == "1111")
    }

    @Test func controllerKeyboardOpensForFocusedTextField() async {
        _ = NSApplication.shared
        let host = MenuFocusHostingView(rootView: TextEntryFixture())
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 450),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.attachedSheet?.close()
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(window.firstResponder is NSTextView)
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(window.attachedSheet != nil)
        if let sheet = window.attachedSheet {
            #expect(sheet.frame.width <= window.contentView!.bounds.width)
            testNavigator.perform(.back, in: sheet) { sheet.sendEvent($0) }
            await settle(host)
        }
        #expect(window.attachedSheet == nil)
    }

    @Test func controllerKeyboardAcceptsInputInsideSettingsFocusScope() async {
        _ = NSApplication.shared
        let value = Mutex("")
        let host = MenuFocusHostingView(rootView: TextEntryFixture { updated in
            value.withLock { $0 = updated }
        }.environment(\.settingsMenuFocus, true))
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 450),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.attachedSheet?.close()
            window.contentView = nil
            window.close()
        }
        await settle(host)
        #expect(window.firstResponder is NSTextView)
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(window.attachedSheet != nil)
        if let sheet = window.attachedSheet {
            #expect(testNavigator.activeWindow === sheet)
            testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
            await settle(sheet.contentView ?? host)
            #expect(value.withLock { $0 } == "q")
            testNavigator.perform(.right, in: window) { window.sendEvent($0) }
            testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
            await settle(sheet.contentView ?? host)
            #expect(value.withLock { $0 } == "qw")
            #expect(sheet.firstResponder is NSTextView)
            if let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: sheet.windowNumber, context: nil,
                characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7
            ) {
                sheet.sendEvent(event)
            }
            await settle(sheet.contentView ?? host)
            #expect(value.withLock { $0 } == "qwx")
        }
    }

    @Test func controllerCanOpenCloudSearchKeyboardAndEnterACharacter() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[{"productId":"first","name":"First","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"first"}]}
        """.utf8))
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) { CloudLibraryFeature() }
        let harness = MenuFocusHarness(width: 1200, height: 650) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 500))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        let filters = CloudLibraryFeature.State().filters.count
        await harness.send([.up] + Array(repeating: .right, count: filters))
        #expect(window.firstResponder is NSTextView)
        await harness.send(.confirm)
        #expect(window.attachedSheet != nil)
        if let sheet = window.attachedSheet {
            harness.perform([.confirm], in: sheet)
            await harness.settle()
            #expect(store.query == "q")
            await harness.send([.down, .down, .down, .right, .right, .right, .confirm], in: sheet)
            #expect(store.query.isEmpty)
            await harness.send([.up, .confirm], in: sheet)
            #expect(store.query == "v")
            await harness.send([.down, .right, .confirm], in: sheet)
            #expect(store.query.isEmpty)
            await harness.send([.right], in: sheet)
            harness.perform([.confirm], in: sheet)
            await harness.settle()
        }
        #expect(window.attachedSheet == nil)
    }

    @Test func optionsCommandRequestsSettingsForTheCurrentWindow() async {
        _ = NSApplication.shared
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        let navigator = AppKitMenuNavigator(policy: StandaloneMenuInputPolicy())
        var events = navigator.commands.events().makeAsyncIterator()
        navigator.perform(.settings, in: window)
        let event = await events.next()
        #expect(event?.command == .settings)
        #expect(event?.targets(window) == true)
    }

    func settle(_ host: NSView) async {
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }
}
