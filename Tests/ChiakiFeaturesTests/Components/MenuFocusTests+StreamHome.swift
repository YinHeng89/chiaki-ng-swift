@testable import ChiakiFeatures
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
import MenuFocus
import ChiakiTestSupport

private let homeSession = StreamSessionID()

extension MenuFocusTests {
    private func homeStream(_ calls: StreamSessionCalls = StreamSessionCalls()) -> StoreOf<StreamFeature> {
        var state = StreamFeature.State()
        state.session = .playing(homeSession)
        state.source = StreamFeature.source(
            account: UUID(),
            console: RegistrationFlow.ConsoleTarget(address: "127.0.0.1", kind: .ps5),
            route: .local
        )
        return Store(initialState: state) {
            StreamFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
            $0.streamSession = calls.client(on: $0.streamSession)
            $0.idleKakusanHosting()
        }
    }

    private func homeHarness(stream: StoreOf<StreamFeature>) -> MenuFocusHarness {
        MenuFocusHarness(width: 1200, height: 800) { _ in
            MenuFocusHostingView(
                rootView: StreamView(store: stream) {
                    EmptyView()
                }
                .environment(\.controllerNavigation, testControllerNavigation)
            )
        }
    }

    @Test func homeButtonTakesFocusWhenTheScreenCannotBeShownAndReleasesItAfter() async {
        let calls = StreamSessionCalls()
        let stream = homeStream(calls)
        let harness = homeHarness(stream: stream)
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            _ = testNavigator.inputMode.pointerAction()
            stream.send(.event(homeSession, .displayProhibited(false)))
            testControllerNavigation.streamNavigationActive = false
            StreamHomeFocus.record(false, in: harness.window)
            StreamHomeFocus.recordHolding(false, in: harness.window)
            override.restore()
            harness.close()
        }
        await harness.pause(150)
        _ = testNavigator.inputMode.controllerInput()
        stream.send(.event(homeSession, .displayProhibited(true)))
        await harness.pause(200)
        #expect(StreamHomeFocus.focused(in: harness.window))
        #expect(testControllerNavigation.streamNavigationActive)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(calls.homes.value == 1)
        stream.send(.event(homeSession, .displayProhibited(false)))
        await harness.pause(200)
        #expect(!StreamHomeFocus.focused(in: harness.window))
        #expect(!StreamHomeFocus.holdsController(in: harness.window))
        #expect(!testControllerNavigation.streamNavigationActive)
        #expect(!testNavigator.hasControlFocus(in: harness.window))
    }

    @Test func downFromHomeOpensTheStreamMenuOnTheSessionPanel() async {
        let stream = homeStream()
        let harness = homeHarness(stream: stream)
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            _ = testNavigator.inputMode.pointerAction()
            stream.send(.event(homeSession, .displayProhibited(false)))
            testControllerNavigation.streamNavigationActive = false
            StreamHomeFocus.record(false, in: harness.window)
            testNavigator.commands.send(.streamMenu, to: harness.window)
            override.restore()
            harness.close()
        }
        await harness.pause(150)
        _ = testNavigator.inputMode.controllerInput()
        stream.send(.event(homeSession, .displayProhibited(true)))
        await harness.pause(200)
        #expect(StreamHomeFocus.focused(in: harness.window))
        await harness.send(.down)
        await harness.pause(250)
        #expect(stream.menu.navigation == .panel(.session))
        #expect(!StreamHomeFocus.focused(in: harness.window))
        #expect(testControllerNavigation.streamNavigationActive)
    }
}

extension MenuFocusTests {
    @Test func homeButtonDoesNotTakeFocusWithThePointerOrFromAnOpenPresentation() async {
        let stream = homeStream()
        let harness = homeHarness(stream: stream)
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        let presentation = UUID()
        defer {
            _ = testNavigator.inputMode.pointerAction()
            testNavigator.inputGate.presentations.remove(presentation)
            stream.send(.event(homeSession, .displayProhibited(false)))
            testControllerNavigation.streamNavigationActive = false
            StreamHomeFocus.record(false, in: harness.window)
            StreamHomeFocus.recordHolding(false, in: harness.window)
            override.restore()
            harness.close()
        }
        await harness.pause(150)
        _ = testNavigator.inputMode.pointerAction()
        stream.send(.event(homeSession, .displayProhibited(true)))
        await harness.pause(200)
        #expect(!StreamHomeFocus.focused(in: harness.window))
        stream.send(.event(homeSession, .displayProhibited(false)))
        await harness.pause(150)
        _ = testNavigator.inputMode.controllerInput()
        testNavigator.inputGate.presentations.insert(presentation)
        stream.send(.event(homeSession, .displayProhibited(true)))
        await harness.pause(200)
        #expect(!StreamHomeFocus.focused(in: harness.window))
    }
}
