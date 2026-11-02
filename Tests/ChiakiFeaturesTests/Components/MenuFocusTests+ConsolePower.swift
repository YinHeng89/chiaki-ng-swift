@testable import ChiakiFeatures
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
import DesignSystem
import ChiakiTestSupport
import MenuFocus

@MainActor
private final class ExitChoiceProbe {
    var actions = [StreamMenuReducer.Action]()
}

extension MenuFocusTests {
    private func exitStore(
        leaveAction: ConsoleLeaveAction,
        context: StreamTuningContext = .console(.local),
        probe: ExitChoiceProbe
    ) -> StoreOf<StreamMenuReducer> {
        var state = StreamMenuReducer.State(context: context)
        state.leaveAction = leaveAction
        state.hasLoaded = true
        state.phase = .ready
        state.exitRequest = "Escape"
        return Store(initialState: state) {
            Reduce<StreamMenuReducer.State, StreamMenuReducer.Action> { _, action in
                probe.actions.append(action)
                return .none
            }
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
        }
    }

    private func exitHarness(_ store: StoreOf<StreamMenuReducer>) -> MenuFocusHarness {
        MenuFocusHarness(width: 900, height: 600) { _ in
            MenuFocusHostingView(rootView: StreamExitConfirmationOverlay(
                store: store,
                stream: .console,
                leaveTitle: "Disconnect"
            ))
        }
    }

    @Test func exitConfirmationReachesRestModeWithTheController() async {
        let probe = ExitChoiceProbe()
        let store = exitStore(leaveAction: .ask, probe: probe)
        let harness = exitHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(150)
        #expect(testNavigator.inputGate.isBlocking)
        await harness.send([.right, .right, .right])
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(probe.actions.contains(.confirmExit(.restMode)))
        #expect(probe.actions.contains(.delegate(.stopRequested(.restMode))))
    }

    @Test func exitConfirmationStepsBackToDisconnectAndBackKeepsPlaying() async {
        let probe = ExitChoiceProbe()
        let store = exitStore(leaveAction: .ask, probe: probe)
        let harness = exitHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(150)
        await harness.send([.right, .right, .left])
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(probe.actions.contains(.confirmExit(.disconnect)))
        #expect(probe.actions.contains(.delegate(.stopRequested(.disconnect))))

        let backProbe = ExitChoiceProbe()
        let backStore = exitStore(leaveAction: .ask, probe: backProbe)
        let backHarness = exitHarness(backStore)
        defer {
            backHarness.close()
        }
        await backHarness.open()
        await backHarness.pause(150)
        await backHarness.send([.right, .right])
        await backHarness.send(.back)
        await backHarness.pause(100)
        #expect(backProbe.actions == [.cancelExit])
        #expect(backStore.exitRequest == nil)
    }

    @Test func alwaysRestModeOffersOnlyStayAndLeave() async {
        let probe = ExitChoiceProbe()
        let store = exitStore(leaveAction: .restMode, probe: probe)
        let harness = exitHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(150)
        await harness.send([.right, .right])
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(probe.actions.contains(.delegate(.stopRequested(.restMode))))
    }

    @Test func cloudExitNeverOffersRestMode() async {
        let probe = ExitChoiceProbe()
        let store = exitStore(leaveAction: .ask, context: .cloud("pscloud"), probe: probe)
        let harness = exitHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(150)
        await harness.send([.right, .right, .right])
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(probe.actions.contains(.delegate(.stopRequested(.disconnect))))
    }

    @Test func consolePowerSettingsAreReachedFromTheNetworkTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .network)
        let harness = MenuFocusHarness(width: 1000, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        #expect(store.consolePower.isEditable)
        var previous = window.firstResponder
        for _ in 0..<16 {
            await harness.send(.down)
            if window.firstResponder === previous {
                break
            }
            previous = window.firstResponder
        }
        await harness.send(.up)
        let reconnectToggle = window.firstResponder
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(!store.consolePower.draft.reconnectAfterDrop)
        #expect(window.firstResponder === reconnectToggle)
        await harness.send(.up)
        let bottom = window.firstResponder
        #expect(bottom !== reconnectToggle)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(!store.consolePower.draft.resumeAfterWake)
        #expect(window.firstResponder === bottom)
        await harness.send(.up)
        let sleepToggle = window.firstResponder
        #expect(sleepToggle !== bottom)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(store.consolePower.draft.restOnMacSleep)
        await harness.send(.up)
        #expect(window.firstResponder !== sleepToggle)
        await harness.send([.left, .left])
        let ask = window.firstResponder
        await harness.send(.left)
        #expect(window.firstResponder === ask)
        await harness.send(.right)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(store.consolePower.draft.leaveAction == .restMode)
        await harness.send(.down)
        #expect(window.firstResponder === sleepToggle)
        await harness.send(.down)
        #expect(window.firstResponder === bottom)
        await harness.send(.down)
        #expect(window.firstResponder === reconnectToggle)
    }

    @Test func audioBufferSliderIsReachedAndAdjustedFromTheSoundTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .sound)
        let harness = MenuFocusHarness(width: 1000, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        #expect(store.sound.sound.isEditable)
        var previous = window.firstResponder
        for _ in 0..<8 {
            await harness.send(.down)
            if window.firstResponder === previous {
                break
            }
            previous = window.firstResponder
        }
        await harness.send(.confirm)
        await harness.send(.right)
        await harness.pause(100)
        #expect(store.sound.sound.draft.bufferMilliseconds == SoundSettings
            .defaultBufferMilliseconds + SoundSettings.bufferStep)
        await harness.send(.left)
        await harness.send(.left)
        await harness.pause(100)
        #expect(store.sound.sound.draft.bufferMilliseconds == SoundSettings
            .defaultBufferMilliseconds - SoundSettings.bufferStep)
    }

    @Test func streamerModeIsTheLastStopOnTheNetworkTabAndToggles() async {
        let store = FeatureFocusStores.settingsStore(tab: .network)
        let harness = MenuFocusHarness(width: 1000, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        var previous = window.firstResponder
        for _ in 0..<16 {
            await harness.send(.down)
            if window.firstResponder === previous {
                break
            }
            previous = window.firstResponder
        }
        let streamer = window.firstResponder
        #expect(!store.logSettings.streamerMode)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.logSettings.streamerMode)
        #expect(window.firstResponder === streamer)
        await harness.send(.down)
        #expect(window.firstResponder === streamer)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(!store.logSettings.streamerMode)
    }
}
