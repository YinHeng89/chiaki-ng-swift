import PlatformUI
import Foundation
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func autoConnectProgressStaysOnCancelAcrossStepsAndBackCancels() async {
        let plan = AutoConnect.Plan(
            account: UUID(), consoleID: UUID(),
            console: .init(address: "192.0.2.5", kind: .ps5, id: UUID(), name: "Living room"),
            mode: .stream(.local)
        )
        let model = AutoConnectCardModel(state: .discovering(UUID(), plan))
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            MenuFocusHostingView(rootView: AutoConnectCardHost(model: model))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        #expect(testNavigator.inputGate.isBlocking)
        #expect(testNavigator.hasControlFocus(in: harness.window))
        let cancelFrame = harness.focusedFrame
        model.state = .awaitingWake(UUID(), plan)
        await harness.pause(300)
        await harness.send([.left, .right])
        #expect(testNavigator.hasControlFocus(in: harness.window))
        #expect(harness.focusedFrame.size == cancelFrame.size)
        await harness.send(.back)
        await harness.pause(300)
        #expect(model.cancels == 1)
        #expect(model.state == .idle)
        #expect(!testNavigator.inputGate.isBlocking)
    }

    @Test func autoConnectFailureIsAcknowledgedWithConfirm() async {
        let model = AutoConnectCardModel(state: .failed("Living room", .wakeTimedOut))
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            MenuFocusHostingView(rootView: AutoConnectCardHost(model: model))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        #expect(testNavigator.inputGate.isBlocking)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(model.cancels == 1)
        #expect(!testNavigator.inputGate.isBlocking)
    }

    @Test func launchSettingCheckShowsNoCard() {
        #expect(AutoConnectPresentation.confirmation(for: .awaitingLibrary(UUID(), .launchSetting)) == nil)
        #expect(AutoConnectPresentation.confirmation(for: .checkingLaunchSetting(UUID())) == nil)
        #expect(AutoConnectPresentation.confirmation(for: .idle) == nil)
        let request = AutoConnectPresentation.confirmation(for: .awaitingLibrary(
            UUID(),
            .console(UUID(), .wake)
        ))
        #expect(request?.progress == true)
        #expect(request?.confirmTitle == nil)
    }
}

@MainActor
@Observable
private final class AutoConnectCardModel {
    var state: AutoConnect
    var cancels = 0

    init(state: AutoConnect) {
        self.state = state
    }

    func cancel() {
        cancels += 1
        state = .idle
    }
}

private struct AutoConnectCardHost: View {
    let model: AutoConnectCardModel

    var body: some View {
        Color.clear
            .frame(width: 700, height: 500)
            .appConfirmation(AutoConnectPresentation.confirmation(for: model.state)) {
                model.cancel()
            }
    }
}
