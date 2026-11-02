import ChiakiModels
import PlatformUI
import ComposableArchitecture
import Observation
import SwiftUI
import Testing
import ChiakiClients
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func backOnTheCloudLibraryAsksToQuitOnlyWhenNothingIsOpen() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"first","name":"First","platform":"ps5","category":"owned",
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
        let requests = LockIsolated(0)
        let harness = MenuFocusHarness(width: 1100, height: 800) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600)
                .environment(\.requestQuit, RequestQuitAction { _ in
                    requests.withValue {
                        $0 += 1
                    }
                }))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.send(.confirm)
        #expect(store.selectedGame?.id == "first")
        await harness.send(.back)
        #expect(store.selectedGame == nil)
        #expect(requests.value == 0)
        await harness.send(.back)
        #expect(requests.value == 1)
        await harness.send(.up)
        for _ in 0..<8 where !(harness.window.firstResponder is NSTextView) {
            await harness.send(.right)
        }
        #expect(harness.window.firstResponder is NSTextView)
        #expect(!testNavigator.isEditingText(in: harness.window))
        await harness.send(.back)
        #expect(requests.value == 2)
    }

    @Test func quitPromptStartsOnCancelAndBackDismissesIt() async {
        let quits = LockIsolated(0)
        let store = Store(initialState: RootFeature.State(route: .library)) {
            RootFeature()
        } withDependencies: {
            $0.platform = PlatformClient(
                shutdown: {},
                quit: {
                    quits.withValue {
                        $0 += 1
                    }
                }
            )
        }
        let harness = MenuFocusHarness(width: 600, height: 400) { _ in
            MenuFocusHostingView(rootView: QuitPromptHost(store: store))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(100)
        store.send(.view(.quitRequested(.screen)))
        await harness.pause(300)
        #expect(testNavigator.inputGate.isBlocking)
        #expect(harness.window.attachedSheet == nil)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(quits.value == 0)
        #expect(store.destination == nil)
        #expect(!testNavigator.inputGate.isBlocking)
        store.send(.view(.quitRequested(.screen)))
        await harness.pause(300)
        await harness.send(.back)
        #expect(!testNavigator.inputGate.isBlocking)
        store.send(.view(.quitRequested(.screen)))
        await harness.pause(300)
        await harness.send([MenuCommand.right, .confirm])
        await harness.pause(200)
        #expect(quits.value == 1)
    }

    private func runConfirmation(
        _ request: AppConfirmation,
        _ commands: [MenuCommand]
    ) async -> (confirms: Int, cancels: Int) {
        var confirms = 0
        var cancels = 0
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            MenuFocusHostingView(rootView: AppConfirmationCard(
                request: request, confirm: { confirms += 1 }, cancel: { cancels += 1 }
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        #expect(testNavigator.inputGate.isBlocking)
        await harness.send(commands)
        #expect(!testNavigator.inputGate.isBlocking)
        await harness.send([.left, .confirm, .back])
        return (confirms, cancels)
    }

    @Test func destructiveConfirmationStartsOnCancelAndNeedsAnExplicitChoice() async {
        let request = AppConfirmation(
            title: "Delete this console?", message: "Gone for good.",
            confirmTitle: "Delete console", tone: .destructive
        )
        let pressed = await runConfirmation(request, [.confirm])
        #expect(pressed.confirms == 0 && pressed.cancels == 1)
        let backed = await runConfirmation(request, [.back])
        #expect(backed.confirms == 0 && backed.cancels == 1)
        let chosen = await runConfirmation(request, [.right, .confirm])
        #expect(chosen.confirms == 1 && chosen.cancels == 0)
    }

    @Test func acknowledgementHasASingleFocusedButton() async {
        let request = AppConfirmation(
            title: "Couldn’t update the console", message: "Try again.", cancelTitle: "OK"
        )
        let result = await runConfirmation(request, [.right, .confirm])
        #expect(result.confirms == 0 && result.cancels == 1)
    }

    @Test func replacingOneConfirmationWithAnotherKeepsTheNewOneUsable() async {
        let model = ConfirmationSwapModel()
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            MenuFocusHostingView(rootView: ConfirmationSwapHost(model: model))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send(.back)
        await harness.pause(300)
        #expect(model.request?.title == "Couldn’t update the console")
        #expect(testNavigator.inputGate.isBlocking)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(model.request == nil)
        #expect(!testNavigator.inputGate.isBlocking)
    }
}

@MainActor
@Observable
private final class ConfirmationSwapModel {
    var request: AppConfirmation? = AppConfirmation(
        title: "Delete this account?", confirmTitle: "Delete account", tone: .destructive
    )

    func cancel() {
        if request?.title == "Delete this account?" {
            request = AppConfirmation(title: "Couldn’t update the console", cancelTitle: "OK")
        } else {
            request = nil
        }
    }
}

private struct ConfirmationSwapHost: View {
    let model: ConfirmationSwapModel

    var body: some View {
        Color.clear
            .frame(width: 700, height: 500)
            .appConfirmation(model.request) {
                model.cancel()
            }
    }
}

private struct QuitPromptHost: View {
    let store: StoreOf<RootFeature>

    var body: some View {
        Color.clear
            .frame(width: 600, height: 400)
            .modifier(AppAlertPresentation(alert: alert, systemImage: nil) { action in
                guard let action else {
                    store.send(.destination(.dismiss))
                    return
                }
                store.send(.destination(.presented(.alert(action))))
            })
    }

    private var alert: AlertState<RootFeature.Destination.Alert>? {
        if case .alert(let alert) = store.destination {
            return alert
        }
        return nil
    }
}
