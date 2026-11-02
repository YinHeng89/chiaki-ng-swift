import ChiakiModels
import ComposableArchitecture
import PlatformUI
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

private let keyboardSession = StreamSessionID()

extension MenuFocusTests {
    private func keyboardStream(_ calls: StreamSessionCalls) -> (StoreOf<StreamFeature>, MenuFocusHarness) {
        var state = StreamFeature.State()
        state.session = .playing(keyboardSession)
        state.source = StreamFeature.source(
            account: UUID(),
            console: RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5),
            route: .local
        )
        let store = Store(initialState: state) {
            StreamFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
            $0.streamSession = calls.client(on: $0.streamSession)
            $0.idleKakusanHosting()
        }
        let harness = MenuFocusHarness(width: 900, height: 600) { _ in
            MenuFocusHostingView(rootView: StreamView(store: store) {
                EmptyView()
            }
            .environment(\.controllerNavigation, testControllerNavigation))
        }
        return (store, harness)
    }

    private func keyboard(_ signal: ConsoleKeyboardSignal, in store: StoreOf<StreamFeature>) {
        store.send(.event(keyboardSession, .keyboard(signal)))
    }

    @Test func consoleKeyboardOpensOnTheFirstKeyAndControllerTypesIntoIt() async throws {
        let calls = StreamSessionCalls()
        let (store, harness) = keyboardStream(calls)
        defer {
            harness.close()
        }
        await harness.open()
        let baseline = testNavigator.inputGate.presentations.count
        keyboard(.opened("Hi"), in: store)
        await harness.pause(300)
        let sheet = try #require(harness.window.attachedSheet)
        #expect(testNavigator.inputGate.presentations.count == baseline + 1)
        await harness.send([.confirm], in: sheet)
        #expect(store.keyboard.session?.text == "Hiq")
        await harness.send([.right, .confirm], in: sheet)
        #expect(store.keyboard.session?.text == "Hiqw")
        await harness.send([.alternate], in: sheet)
        await harness.pause(100)
        #expect(calls.keyboard.value.first == .setText("Hiq"))
        await harness.send([.down, .down, .down, .right, .right, .right, .right, .confirm], in: sheet)
        await harness.pause(200)
        #expect(harness.window.attachedSheet == nil)
        #expect(calls.keyboard.value.last == .accept("Hiq"))
        #expect(store.keyboard.session == nil)
        #expect(testNavigator.inputGate.presentations.count == baseline)
    }

    @Test func consoleKeyboardBackDismissesAndRejects() async throws {
        let calls = StreamSessionCalls()
        let (store, harness) = keyboardStream(calls)
        defer {
            harness.close()
        }
        await harness.open()
        let baseline = testNavigator.inputGate.presentations.count
        keyboard(.opened(""), in: store)
        await harness.pause(300)
        let sheet = try #require(harness.window.attachedSheet)
        await harness.send([.back], in: sheet)
        await harness.pause(200)
        #expect(harness.window.attachedSheet == nil)
        #expect(calls.keyboard.value == [.reject])
        #expect(store.keyboard.session == nil)
        #expect(testNavigator.inputGate.presentations.count == baseline)
    }

    @Test func consoleKeyboardFollowsConsoleTextAndClosesWhenTheConsoleDoes() async throws {
        let calls = StreamSessionCalls()
        let (store, harness) = keyboardStream(calls)
        defer {
            harness.close()
        }
        await harness.open()
        let baseline = testNavigator.inputGate.presentations.count
        keyboard(.opened("abc"), in: store)
        await harness.pause(300)
        let sheet = try #require(harness.window.attachedSheet)
        keyboard(.textChanged("abcd"), in: store)
        await harness.pause(150)
        await harness.send([.confirm], in: sheet)
        #expect(store.keyboard.session?.text == "abcdq")
        keyboard(.closed, in: store)
        await harness.pause(300)
        #expect(harness.window.attachedSheet == nil)
        #expect(!calls.keyboard.value.contains(.reject))
        #expect(testNavigator.inputGate.presentations.count == baseline)
        keyboard(.opened(""), in: store)
        await harness.pause(300)
        #expect(harness.window.attachedSheet != nil)
        store.send(.stop)
        await harness.pause(300)
        #expect(harness.window.attachedSheet == nil)
        #expect(testNavigator.inputGate.presentations.count == baseline)
    }

    @Test func consoleKeyboardEndedByTheWindowRejectsOnceAndReleasesTheGate() async throws {
        let calls = StreamSessionCalls()
        let (store, harness) = keyboardStream(calls)
        defer {
            harness.close()
        }
        await harness.open()
        let baseline = testNavigator.inputGate.presentations.count
        keyboard(.opened("abc"), in: store)
        await harness.pause(300)
        let sheet = try #require(harness.window.attachedSheet)
        harness.window.endSheet(sheet)
        await harness.pause(300)
        #expect(calls.keyboard.value == [.reject])
        #expect(store.keyboard.session == nil)
        #expect(testNavigator.inputGate.presentations.count == baseline)
    }
}
